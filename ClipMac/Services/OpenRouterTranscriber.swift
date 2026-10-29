import AVFoundation
import ClipCore
import Foundation

actor OpenRouterTranscriber {
    private let cache: TranscriptCache
    private let client: OpenRouterTranscriptionClient
    // Version the export format and chunk boundaries along with the model.
    private let cacheModel = "openrouter-whisper-large-v3-m4a-180s-context2-v1"

    init(cache: TranscriptCache = .shared, client: OpenRouterTranscriptionClient = OpenRouterTranscriptionClient()) {
        self.cache = cache
        self.client = client
    }

    func transcribe(
        audio: [AudioSource],
        apiKey: String,
        spendingLimitUSD: Double,
        update: @escaping @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> [MacTranscriptWord] {
        update(.cacheLookup)
        let hash = try await cache.audioSetHash(audio.map(\.url))
        if let words = try? await cache.load(hash: hash, model: cacheModel) {
            update(.cloudSpending(0))
            update(.listening(fraction: 1, cacheHit: true))
            return words
        }

        var work: [ChunkWork] = []
        var offset: TimeInterval = 0
        for (fileIndex, source) in audio.enumerated() {
            guard let duration = source.duration, duration.isFinite, duration > 0 else {
                throw MacAppError.unreadableAudio(source.url.lastPathComponent)
            }
            work += OpenRouterAudioChunk.plan(duration: duration).map {
                ChunkWork(url: source.url, fileIndex: fileIndex, fileOffset: offset, chunk: $0)
            }
            offset += duration
        }

        let spending = SpendingMeter(limitUSD: spendingLimitUSD, update: update)
        var words: [MacTranscriptWord] = []
        var pending: [ChunkWork] = []
        var completed = 0
        for item in work {
            if let cached = try? await cache.load(hash: hash, model: cacheKey(item)) {
                words += cached
                completed += 1
            } else {
                pending.append(item)
            }
        }
        update(.cloudSpending(0))
        update(.listening(fraction: Double(completed) / Double(max(1, work.count)), cacheHit: completed > 0))

        for batchStart in stride(from: 0, to: pending.count, by: 2) {
            try Task.checkCancellation()
            let batch = Array(pending[batchStart..<min(batchStart + 2, pending.count)])
            let estimatedCharge = batch.reduce(0) { $0 + $1.chunk.uploadDuration }
                * OpenRouterTranscriptionClient.estimatedRatesUSD.upperBound * 1.1
            try await spending.check(estimatedNextCharge: estimatedCharge)
            try await withThrowingTaskGroup(of: [MacTranscriptWord].self) { group in
                for item in batch {
                    group.addTask {
                        try await self.transcribeChunk(
                            item, hash: hash, apiKey: apiKey, spending: spending, estimatedBatchCharge: estimatedCharge
                        )
                    }
                }
                for try await result in group {
                    words += result
                    completed += 1
                    update(.listening(fraction: Double(completed) / Double(work.count), cacheHit: false))
                }
            }
        }

        guard !words.isEmpty else { throw MacAppError.noTranscript("the audiobook") }
        words.sort { $0.start < $1.start }
        try await cache.save(words, hash: hash, model: cacheModel)
        update(.listening(fraction: 1, cacheHit: pending.isEmpty))
        return words
    }

    private func transcribeChunk(
        _ item: ChunkWork, hash: String, apiKey: String, spending: SpendingMeter, estimatedBatchCharge: Double
    ) async throws -> [MacTranscriptWord] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-audio-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: item.url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MacAppError.unreadableAudio(item.url.lastPathComponent)
        }
        export.outputURL = url
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: item.chunk.uploadStart, preferredTimescale: 48_000),
            duration: CMTime(seconds: item.chunk.uploadDuration, preferredTimescale: 48_000)
        )
        await withCheckedContinuation { continuation in
            export.exportAsynchronously { continuation.resume() }
        }
        try Task.checkCancellation()
        guard export.status == .completed else {
            throw export.error ?? MacAppError.unreadableAudio(item.url.lastPathComponent)
        }
        let audio = try Data(contentsOf: url)
        let result: OpenRouterTranscription
        do {
            result = try await requestTranscript(audio: audio, apiKey: apiKey, duration: item.chunk.uploadDuration, spending: spending)
        } catch OpenRouterTranscriptionError.missingWordTimestamps {
            try Task.checkCancellation()
            // Allow one retry for an intermittent untimed response. Reserve the whole
            // batch estimate so the other in-flight chunk is also covered.
            try await spending.check(estimatedNextCharge: estimatedBatchCharge)
            result = try await requestTranscript(audio: audio, apiKey: apiKey, duration: item.chunk.uploadDuration, spending: spending)
        }
        let words = item.chunk.globalWords(result.words, fileOffset: item.fileOffset).map {
            MacTranscriptWord(text: $0.word, start: $0.start, end: $0.end, confidence: 1)
        }
        let costWasReported = await spending.record(result.costUSD)
        try await cache.save(words, hash: hash, model: cacheKey(item))
        guard costWasReported else { throw OpenRouterTranscriptionError.missingCost }
        return words
    }

    private func requestTranscript(
        audio: Data, apiKey: String, duration: TimeInterval, spending: SpendingMeter
    ) async throws -> OpenRouterTranscription {
        do {
            return try await client.transcribe(audio: audio, apiKey: apiKey, duration: duration)
        } catch let OpenRouterTranscriptionError.missingWordTimestamps(costUSD) {
            // HTTP 200 can be billed even when its timestamps are missing.
            guard await spending.record(costUSD) else { throw OpenRouterTranscriptionError.missingCost }
            throw OpenRouterTranscriptionError.missingWordTimestamps(costUSD: costUSD)
        }
    }

    private func cacheKey(_ item: ChunkWork) -> String {
        "\(cacheModel)-file\(item.fileIndex)-chunk\(item.chunk.index)"
    }

    private struct ChunkWork: Sendable {
        let url: URL
        let fileIndex: Int
        let fileOffset: TimeInterval
        let chunk: OpenRouterAudioChunk
    }

    private actor SpendingMeter {
        private var budget: OpenRouterTranscriptionBudget
        private var hasUnknownCharge = false
        private let update: @Sendable (TranscriptionUpdate) -> Void

        init(limitUSD: Double, update: @escaping @Sendable (TranscriptionUpdate) -> Void) {
            budget = OpenRouterTranscriptionBudget(limitUSD: limitUSD)
            self.update = update
        }

        func check(estimatedNextCharge: Double) throws {
            guard !hasUnknownCharge else { throw OpenRouterTranscriptionError.missingCost }
            try budget.check(estimatedNextCharge: estimatedNextCharge)
        }

        func record(_ cost: Double?) -> Bool {
            do {
                try budget.record(costUSD: cost)
                update(.cloudSpending(budget.spentUSD))
                return true
            } catch {
                hasUnknownCharge = true
                return false
            }
        }
    }
}

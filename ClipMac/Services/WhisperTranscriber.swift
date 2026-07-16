import Foundation
import ClipCore
import CoreML
import WhisperKit

enum TranscriptionUpdate: Sendable {
    case cacheLookup
    case modelDownload(fraction: Double)
    case modelLoading
    case listening(fraction: Double, cacheHit: Bool)
}

actor WhisperTranscriber {
    private let cache = TranscriptCache.shared
    private let defaults = UserDefaults.standard
    private var loadedKit: WhisperKit?
    private var loadedModel: String?

    func transcribe(
        audio: [AudioSource],
        quality: AlignmentQuality,
        update: @escaping @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> [MacTranscriptWord] {
        let urls = audio.map(\.url)
        update(.cacheLookup)
        let hash = try await cache.audioSetHash(urls)
        let modelVariant = ClipShared.whisperKitRepositoryVariant(
            for: quality.modelName,
            supportedModels: WhisperKit.recommendedModels().supported
        )
        if let words = try await cache.load(hash: hash, model: modelVariant) {
            update(.listening(fraction: 1, cacheHit: true))
            return words
        }

        let modelPath = try await resolveModel(modelVariant, update: update)
        update(.modelLoading)
        let kit = try await loadedKit(for: modelVariant, at: modelPath)
        let options = DecodingOptions(
            wordTimestamps: true,
            concurrentWorkerCount: 1,
            chunkingStrategy: .vad
        )

        let totalDuration = max(1, audio.compactMap(\.duration).reduce(0, +))
        var completedDuration: TimeInterval = 0
        var words: [MacTranscriptWord] = []

        for source in audio {
            let fileDuration = source.duration ?? 0
            let fileOffset = completedDuration
            let results: [TranscriptionResult] = try await kit.transcribe(
                audioPath: source.url.path,
                decodeOptions: options
            ) { progress in
                let fraction = ClipShared.transcriptionFraction(
                    fileOffset: fileOffset,
                    fileDuration: fileDuration,
                    totalDuration: totalDuration,
                    activeWindowIndex: Double(progress.windowId)
                )
                update(.listening(fraction: fraction, cacheHit: false))
                return true
            }

            let localWords = results.flatMap(\.allWords)
            guard !localWords.isEmpty else {
                throw MacAppError.noTranscript(source.url.lastPathComponent)
            }
            words.append(contentsOf: localWords.map {
                MacTranscriptWord(
                    text: $0.word,
                    start: fileOffset + Double($0.start),
                    end: fileOffset + Double($0.end),
                    confidence: Double($0.probability)
                )
            })
            completedDuration += fileDuration
            update(.listening(fraction: min(0.995, completedDuration / totalDuration), cacheHit: false))
        }

        try await cache.save(words, hash: hash, model: modelVariant)
        update(.listening(fraction: 1, cacheHit: false))
        return words
    }

    private func loadedKit(for model: String, at modelPath: URL) async throws -> WhisperKit {
        if loadedModel == model, let loadedKit { return loadedKit }
        // WhisperKit defaults the encoder and decoder to the Neural Engine on
        // recent macOS versions. The current large-v3 model repeatedly fails
        // there on M1 Macs, while Core ML's CPU/GPU path runs it reliably.
        let computeOptions = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndGPU,
            textDecoderCompute: .cpuAndGPU,
            prefillCompute: .cpuOnly
        )
        let kit = try await WhisperKit(
            modelFolder: modelPath.path,
            computeOptions: computeOptions,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        loadedModel = model
        loadedKit = kit
        return kit
    }

    private func resolveModel(
        _ modelVariant: String,
        update: @escaping @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> URL {
        let key = "Clip.WhisperModelPath.\(modelVariant)"
        if let path = defaults.string(forKey: key), FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelRoot = support
            .appendingPathComponent("Clip", isDirectory: true)
            .appendingPathComponent("Speech Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)

        let path = try await WhisperKit.download(
            variant: modelVariant,
            downloadBase: modelRoot,
            progressCallback: { progress in
                update(.modelDownload(fraction: progress.fractionCompleted))
            }
        )
        defaults.set(path.path, forKey: key)
        return path
    }
}

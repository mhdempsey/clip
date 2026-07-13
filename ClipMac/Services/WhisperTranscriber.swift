import Foundation
import WhisperKit

enum TranscriptionUpdate: Sendable {
    case cacheLookup
    case modelDownload(fraction: Double)
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
        if let words = try await cache.load(hash: hash, model: quality.modelName) {
            update(.listening(fraction: 1, cacheHit: true))
            return words
        }

        let modelPath = try await resolveModel(quality.modelName, update: update)
        let kit = try await loadedKit(for: quality.modelName, at: modelPath)
        let options = DecodingOptions(wordTimestamps: true, chunkingStrategy: .vad)

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
                let heardSeconds = min(fileDuration, progress.timings.totalDecodingWindows * 30)
                let fraction = min(0.995, (fileOffset + heardSeconds) / totalDuration)
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

        try await cache.save(words, hash: hash, model: quality.modelName)
        update(.listening(fraction: 1, cacheHit: false))
        return words
    }

    private func loadedKit(for model: String, at modelPath: URL) async throws -> WhisperKit {
        if loadedModel == model, let loadedKit { return loadedKit }
        let kit = try await WhisperKit(
            modelFolder: modelPath.path,
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
        _ model: String,
        update: @escaping @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> URL {
        let key = "Clip.WhisperModelPath.\(model)"
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
            variant: model,
            downloadBase: modelRoot,
            progressCallback: { progress in
                update(.modelDownload(fraction: progress.fractionCompleted))
            }
        )
        defaults.set(path.path, forKey: key)
        return path
    }
}

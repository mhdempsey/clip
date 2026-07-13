import Foundation
import WhisperKit

struct TranscriptionUpdate {
    enum Phase {
        case cacheLookup
        case modelDownload
        case listening
    }

    let phase: Phase
    let fraction: Double
    let cacheHit: Bool
}

actor WhisperTranscriber {
    private let cache = TranscriptCache.shared
    private let defaults = UserDefaults.standard

    func transcribe(
        audio: [AudioSource],
        quality: AlignmentQuality,
        update: @escaping @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> [MacTranscriptWord] {
        let urls = audio.map(\.url)
        update(.init(phase: .cacheLookup, fraction: 0, cacheHit: false))
        let hash = try await cache.audioSetHash(urls)
        if let words = try await cache.load(hash: hash, model: quality.modelName) {
            update(.init(phase: .listening, fraction: 1, cacheHit: true))
            return words
        }

        let modelPath = try await resolveModel(quality.modelName, update: update)
        let kit = try await WhisperKit(
            modelFolder: modelPath.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
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
                update(.init(phase: .listening, fraction: fraction, cacheHit: false))
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
            update(.init(phase: .listening, fraction: min(0.995, completedDuration / totalDuration), cacheHit: false))
        }

        try await cache.save(words, hash: hash, model: quality.modelName)
        update(.init(phase: .listening, fraction: 1, cacheHit: false))
        return words
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
                update(.init(phase: .modelDownload, fraction: progress.fractionCompleted, cacheHit: false))
            }
        )
        defaults.set(path.path, forKey: key)
        return path
    }
}


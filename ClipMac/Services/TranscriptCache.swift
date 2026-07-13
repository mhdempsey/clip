import CryptoKit
import Foundation

struct MacTranscriptWord: Codable, Hashable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double
}

private struct CachedTranscript: Codable {
    let version: Int
    let model: String
    let createdAt: Date
    let words: [MacTranscriptWord]
}

actor TranscriptCache {
    static let shared = TranscriptCache()

    private let fileManager = FileManager.default

    func audioSetHash(_ urls: [URL]) throws -> String {
        var digest = SHA256()
        for url in urls {
            digest.update(data: Data(url.lastPathComponent.utf8))
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while true {
                guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else {
                    break
                }
                digest.update(data: chunk)
            }
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func load(hash: String, model: String) throws -> [MacTranscriptWord]? {
        let url = try cacheURL(hash: hash, model: model)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let cached = try JSONDecoder().decode(CachedTranscript.self, from: Data(contentsOf: url))
        guard cached.version == 1, cached.model == model else { return nil }
        return cached.words
    }

    func save(_ words: [MacTranscriptWord], hash: String, model: String) throws {
        let url = try cacheURL(hash: hash, model: model)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cached = CachedTranscript(version: 1, model: model, createdAt: Date(), words: words)
        let data = try JSONEncoder().encode(cached)
        try data.write(to: url, options: .atomic)
    }

    private func cacheURL(hash: String, model: String) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let safeModel = model.replacingOccurrences(of: "/", with: "-")
        return support
            .appendingPathComponent("Clip", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
            .appendingPathComponent("\(safeModel).json")
    }
}

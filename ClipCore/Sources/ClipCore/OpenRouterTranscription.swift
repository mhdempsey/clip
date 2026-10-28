import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenRouterTranscription: Sendable {
    public struct Word: Codable, Equatable, Sendable {
        public let word: String
        public let start: TimeInterval
        public let end: TimeInterval

        public init(word: String, start: TimeInterval, end: TimeInterval) {
            self.word = word
            self.start = start
            self.end = end
        }
    }

    public let words: [Word]
    public let costUSD: Double?
}

public struct OpenRouterTranscriptionClient: Sendable {
    public static let model = "openai/whisper-large-v3"
    // Published provider rates, used for estimates only. The response meters actual spend.
    public static let estimatedRatesUSD = 0.000008...0.000031
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? CredentialedSession.shared
    }

    public func transcribe(audio: Data, apiKey: String, duration: TimeInterval) async throws -> OpenRouterTranscription {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model,
            "input_audio": ["data": audio.base64EncodedString(), "format": "m4a"],
            "response_format": "verbose_json",
            "timestamp_granularities": ["word"]
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenRouterTranscriptionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenRouterTranscriptionError.httpStatus(http.statusCode)
        }
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OpenRouterTranscriptionError.invalidResponse
        }
        guard let words = decoded.words else {
            throw OpenRouterTranscriptionError.missingWordTimestamps(costUSD: decoded.usage?.cost)
        }
        guard duration.isFinite, duration > 0,
              words.isEmpty || words.contains(where: { $0.end > $0.start }),
              words.allSatisfy({
                  !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.start.isFinite && $0.end.isFinite &&
                  $0.start >= 0 && $0.end >= $0.start && $0.end <= duration + 1
              }) else {
            throw OpenRouterTranscriptionError.invalidResponse
        }
        if words.isEmpty, !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OpenRouterTranscriptionError.missingWordTimestamps(costUSD: decoded.usage?.cost)
        }
        return OpenRouterTranscription(words: words, costUSD: decoded.usage?.cost)
    }

    private struct Response: Decodable {
        let text: String
        let words: [OpenRouterTranscription.Word]?
        let usage: Usage?
        struct Usage: Decodable { let cost: Double? }
    }

}

/// Each chunk owns a contiguous span, with context on both sides of its upload.
/// Keeping words by their midpoint avoids duplicate words at chunk boundaries.
public struct OpenRouterAudioChunk: Sendable {
    public let index: Int
    public let start: TimeInterval
    public let end: TimeInterval
    public let uploadStart: TimeInterval
    public let uploadDuration: TimeInterval

    public static func plan(duration: TimeInterval) -> [Self] {
        guard duration.isFinite, duration > 0 else { return [] }
        let length: TimeInterval = 180
        let context: TimeInterval = 2
        return (0..<Int(ceil(duration / length))).map { index in
            let start = Double(index) * length
            let end = min(start + length, duration)
            let uploadStart = max(0, start - context)
            return Self(
                index: index, start: start, end: end,
                uploadStart: uploadStart,
                uploadDuration: min(duration, end + context) - uploadStart
            )
        }
    }

    public func globalWords(_ words: [OpenRouterTranscription.Word], fileOffset: TimeInterval) -> [OpenRouterTranscription.Word] {
        words.compactMap { word in
            let midpoint = uploadStart + (word.start + word.end) / 2
            guard midpoint >= start, midpoint < end else { return nil }
            return .init(
                word: word.word,
                start: fileOffset + uploadStart + word.start,
                end: fileOffset + uploadStart + min(word.end, uploadDuration)
            )
        }
    }
}

/// Checks between upload batches. Provider rate changes can put the final batch
/// over the limit; no further requests start after that charge is reported.
public struct OpenRouterTranscriptionBudget: Sendable {
    public let limitUSD: Double
    public private(set) var spentUSD: Double = 0

    public init(limitUSD: Double) { self.limitUSD = limitUSD }

    public func check(estimatedNextCharge: Double) throws {
        guard limitUSD.isFinite, limitUSD > 0, estimatedNextCharge.isFinite,
              estimatedNextCharge >= 0, spentUSD + estimatedNextCharge <= limitUSD else {
            throw OpenRouterTranscriptionError.spendingLimit
        }
    }

    public mutating func record(costUSD: Double?) throws {
        guard let costUSD, costUSD.isFinite, costUSD >= 0 else {
            throw OpenRouterTranscriptionError.missingCost
        }
        spentUSD += costUSD
    }
}

public enum OpenRouterTranscriptionError: LocalizedError, Sendable {
    case invalidResponse
    case missingWordTimestamps(costUSD: Double?)
    case missingCost
    case spendingLimit
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "OpenRouter returned an unreadable transcript or invalid word timing. Try again; completed chunks are saved."
        case .missingWordTimestamps:
            "OpenRouter didn’t return word timestamps. Clip needs them to sync the book. Try again or use On this Mac."
        case .missingCost:
            "OpenRouter didn’t report this chunk’s cost. Clip stopped further uploads; completed chunks are saved. Check usage in OpenRouter before resuming."
        case .spendingLimit:
            "Clip stopped before the next upload to stay within your spending limit. Completed chunks are saved. Raise the limit in Settings and retry to continue."
        case .httpStatus(401), .httpStatus(403):
            "OpenRouter rejected the API key. Update it in Clip Settings and retry."
        case .httpStatus(402):
            "OpenRouter needs more credits. Add credits to your existing account and retry."
        case .httpStatus(429):
            "OpenRouter is rate limiting requests. Wait a moment, then retry; completed chunks are saved."
        case let .httpStatus(status):
            "OpenRouter returned HTTP \(status). Retry to continue from saved chunks."
        }
    }
}

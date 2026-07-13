import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ReadwiseHighlightRequest: Codable, Equatable, Sendable {
    public var highlights: [ReadwiseHighlight]

    public init(highlights: [ReadwiseHighlight]) {
        self.highlights = highlights
    }
}

public struct ReadwiseHighlight: Codable, Equatable, Sendable {
    public var text: String
    public var title: String
    public var author: String
    public var sourceType: String
    public var category: String
    public var location: Int
    public var locationType: String
    public var note: String
    public var highlightedAt: Date

    public init(text: String, title: String, author: String, location: Int, note: String, highlightedAt: Date = Date()) {
        self.text = text
        self.title = title
        self.author = author
        self.sourceType = "clip"
        self.category = "books"
        self.location = location
        self.locationType = "order"
        self.note = note
        self.highlightedAt = highlightedAt
    }

    enum CodingKeys: String, CodingKey {
        case text, title, author, category, location, note
        case sourceType = "source_type"
        case locationType = "location_type"
        case highlightedAt = "highlighted_at"
    }
}

public enum ReadwiseSendStatus: Equatable, Sendable {
    case sent
    case invalidToken
    case retryable
    case permanentFailure(statusCode: Int)
}

public enum ReadwiseError: Error, LocalizedError, Sendable {
    case invalidResponse
    case unexpectedStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Readwise returned an invalid response."
        case let .unexpectedStatus(status): "Readwise returned HTTP \(status)."
        }
    }
}

public actor ReadwiseClient {
    public static let authenticationURL = URL(string: "https://readwise.io/api/v2/auth/")!
    public static let highlightsURL = URL(string: "https://readwise.io/api/v2/highlights/")!

    private var token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func updateToken(_ token: String) {
        self.token = token
    }

    public func validateToken() async throws -> Bool {
        var request = URLRequest(url: Self.authenticationURL)
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReadwiseError.invalidResponse }
        if http.statusCode == 204 { return true }
        if http.statusCode == 401 { return false }
        throw ReadwiseError.unexpectedStatus(http.statusCode)
    }

    public func send(_ highlight: ReadwiseHighlight) async throws -> ReadwiseSendStatus {
        var request = URLRequest(url: Self.highlightsURL)
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.readwise.encode(ReadwiseHighlightRequest(highlights: [highlight]))
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReadwiseError.invalidResponse }
        return Self.classify(statusCode: http.statusCode)
    }

    public nonisolated static func classify(statusCode: Int) -> ReadwiseSendStatus {
        switch statusCode {
        case 200..<300: .sent
        case 401: .invalidToken
        case 429, 500..<600: .retryable
        default: .permanentFailure(statusCode: statusCode)
        }
    }
}

public extension JSONEncoder {
    static var readwise: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

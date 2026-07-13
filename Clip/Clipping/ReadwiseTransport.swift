import ClipCore
import Foundation

actor ReadwiseTransport {
    enum SendResult: Sendable {
        case sent
        case invalidToken
        case retryable(String)
        case rejected(String)
    }

    typealias Highlight = ReadwiseHighlight

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(token: String) async -> Bool {
        (try? await ReadwiseClient(token: token, session: session).validateToken()) ?? false
    }

    func send(_ highlight: Highlight, token: String) async -> SendResult {
        do {
            switch try await ReadwiseClient(token: token, session: session).send(highlight) {
            case .sent: return .sent
            case .invalidToken: return .invalidToken
            case .retryable: return .retryable("Readwise is temporarily unavailable")
            case .permanentFailure(let statusCode): return .rejected("Readwise returned \(statusCode)")
            }
        } catch {
            return .retryable(error.localizedDescription)
        }
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum CredentialedSession {
    static let shared = make()

    static func make(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }
}

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

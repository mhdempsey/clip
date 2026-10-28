import Foundation
import XCTest
@testable import ClipCore

final class CredentialedSessionTests: XCTestCase {
    func testCredentialedRequestsHaveNoCacheCookiesOrSharedCredentialStorage() {
        let session = CredentialedSession.make()
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertNil(session.configuration.urlCredentialStorage)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testRedirectCannotForwardAnAuthenticatedUpload() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CredentialRedirectProtocol.self]
        let session = CredentialedSession.make(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.example.test/upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer unit-test", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("private audio".utf8)
        let (body, response) = try await session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 307)
        XCTAssertNotEqual(String(data: body, encoding: .utf8), "redirect followed")
    }
}

private final class CredentialRedirectProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".example.test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.host == "api.example.test" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://other.example.test/collect"])!
            var redirect = request
            redirect.url = URL(string: "https://other.example.test/collect")!
            client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("redirect followed".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() { }
}

import Foundation
import XCTest
@testable import ClipCore

final class OpenRouterTranscriptionTests: XCTestCase {
    override func tearDown() {
        TranscriptionURLProtocol.handler = nil
        super.tearDown()
    }

    func testRequestsWordTimestampsAndDecodesMeteredTranscript() async throws {
        TranscriptionURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/audio/transcriptions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body: Data
            if let data = request.httpBody {
                body = data
            } else {
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                body = data
            }
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "openai/whisper-large-v3")
            XCTAssertEqual(json["response_format"] as? String, "verbose_json")
            XCTAssertEqual(json["timestamp_granularities"] as? [String], ["word"])
            let audio = try XCTUnwrap(json["input_audio"] as? [String: String])
            XCTAssertEqual(audio["format"], "m4a")
            XCTAssertEqual(audio["data"], Data([1, 2, 3]).base64EncodedString())
            return (200, Data(#"{"text":"Call me Ishmael.","words":[{"word":"Call","start":0.2,"end":0.5},{"word":"me","start":0.5,"end":0.7},{"word":"Ishmael.","start":0.7,"end":1.4}],"usage":{"cost":0.0012}}"#.utf8))
        }
        let result = try await client().transcribe(audio: Data([1, 2, 3]), apiKey: "test-key", duration: 2)
        XCTAssertEqual(result.words.map(\.word), ["Call", "me", "Ishmael."])
        XCTAssertEqual(result.words.last?.end, 1.4)
        XCTAssertEqual(result.costUSD, 0.0012)
    }

    func testRejectsPlainTextOrInvalidTimingsInsteadOfCachingUnusableAlignment() async throws {
        for body in [
            #"{"text":"Hello","usage":{"cost":0.01}}"#,
            #"{"text":"Hello","words":[{"word":"Hello","start":1,"end":0}],"usage":{"cost":0.01}}"#,
            #"{"text":"Hello","words":[{"word":"Hello","start":0,"end":40}],"usage":{"cost":0.01}}"#
        ] {
            TranscriptionURLProtocol.handler = { _ in (200, Data(body.utf8)) }
            do {
                _ = try await client().transcribe(audio: Data(), apiKey: "test-key", duration: 2)
                XCTFail("A transcript without usable word timing must fail")
            } catch is OpenRouterTranscriptionError { }
        }
    }

    func testAcceptsValidWordTimingsReturnedOutOfChronologicalOrder() async throws {
        TranscriptionURLProtocol.handler = { _ in
            (200, Data(#"{"text":"first second third","words":[{"word":"first","start":94,"end":94.4},{"word":"second","start":93.66,"end":94.72},{"word":"third","start":95,"end":95.5}],"usage":{"cost":0.001}}"#.utf8))
        }
        let result = try await client().transcribe(audio: Data(), apiKey: "test-key", duration: 184)
        XCTAssertEqual(result.words.map(\.word), ["first", "second", "third"])
        XCTAssertEqual(result.words.map(\.start), [94, 93.66, 95])
        XCTAssertEqual(result.costUSD, 0.001)
    }

    func testMissingTimestampsPreservesTheChargeForBothOmittedAndEmptyWordArrays() async throws {
        for words in ["", #","words":[]"#] {
            let body = "{\"text\":\"Hello\"\(words),\"usage\":{\"cost\":0.003}}"
            TranscriptionURLProtocol.handler = { _ in (200, Data(body.utf8)) }
            do {
                _ = try await client().transcribe(audio: Data(), apiKey: "test-key", duration: 6)
                XCTFail("Untimed speech must fail without discarding its charge")
            } catch let OpenRouterTranscriptionError.missingWordTimestamps(costUSD) {
                XCTAssertEqual(costUSD, 0.003)
            }
        }
    }

    func testAuthenticationAndCreditFailuresHaveActionableErrorsWithoutLeakingResponse() async throws {
        for status in [401, 402, 429, 503] {
            TranscriptionURLProtocol.handler = { _ in (status, Data("secret provider response".utf8)) }
            do {
                _ = try await client().transcribe(audio: Data(), apiKey: "test-key", duration: 2)
                XCTFail("HTTP \(status) must fail")
            } catch {
                XCTAssertFalse(error.localizedDescription.contains("secret"))
                XCTAssertFalse(error.localizedDescription.contains("test-key"))
                XCTAssertTrue(error.localizedDescription.contains("OpenRouter"))
            }
        }
    }

    func testOverlappingChunksKeepOneCopyOfBoundaryWordsAndPreserveFileOffsets() throws {
        let chunks = OpenRouterAudioChunk.plan(duration: 361)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].uploadStart, 0)
        XCTAssertEqual(chunks[1].uploadStart, 178)
        XCTAssertEqual(chunks[2].uploadDuration, 3)
        let before = OpenRouterTranscription.Word(word: "before", start: 179.2, end: 179.8)
        let boundary = OpenRouterTranscription.Word(word: "after", start: 179.8, end: 180.6)
        let first = chunks[0].globalWords([before, boundary], fileOffset: 1_000)
        let second = chunks[1].globalWords([
            .init(word: "before", start: 1.2, end: 1.8),
            .init(word: "after", start: 1.8, end: 2.6)
        ], fileOffset: 1_000)
        XCTAssertEqual((first + second).map(\.word), ["before", "after"])
        XCTAssertEqual(second[0].start, 1_179.8, accuracy: 0.0001)
        XCTAssertEqual(second[0].end, 1_180.6, accuracy: 0.0001)
        XCTAssertTrue(OpenRouterAudioChunk.plan(duration: 0).isEmpty)
        XCTAssertTrue(OpenRouterAudioChunk.plan(duration: .infinity).isEmpty)
    }

    func testBudgetCountsNewChargesAndRefusesAnotherBatch() throws {
        var budget = OpenRouterTranscriptionBudget(limitUSD: 0.02)
        try budget.check(estimatedNextCharge: 0.01)
        try budget.record(costUSD: 0.012)
        XCTAssertEqual(budget.spentUSD, 0.012)
        XCTAssertThrowsError(try budget.check(estimatedNextCharge: 0.01))
        XCTAssertThrowsError(try budget.record(costUSD: nil))
        XCTAssertThrowsError(try OpenRouterTranscriptionBudget(limitUSD: .nan).check(estimatedNextCharge: 0.01))
    }

    func testRejectsTranscriptWhoseWordTimingsAreAllZero() async throws {
        TranscriptionURLProtocol.handler = { _ in
            (200, Data(#"{"text":"Hello","words":[{"word":"Hello","start":0,"end":0}],"usage":{"cost":0.01}}"#.utf8))
        }
        do {
            _ = try await client().transcribe(audio: Data(), apiKey: "test-key", duration: 2)
            XCTFail("All-zero timing cannot sync an audiobook")
        } catch OpenRouterTranscriptionError.invalidResponse { }
    }

    func testSmallTimestampPaddingDoesNotExtendPastTheAudioFile() async throws {
        TranscriptionURLProtocol.handler = { _ in
            (200, Data(#"{"text":"Hello","words":[{"word":"Hello","start":8.8,"end":10.6}],"usage":{"cost":0.01}}"#.utf8))
        }
        let transcript = try await client().transcribe(audio: Data(), apiKey: "test-key", duration: 10)
        let chunk = try XCTUnwrap(OpenRouterAudioChunk.plan(duration: 10).first)
        let word = try XCTUnwrap(chunk.globalWords(transcript.words, fileOffset: 900).first)
        XCTAssertEqual(word.start, 908.8, accuracy: 0.0001)
        XCTAssertEqual(word.end, 910)
    }

    private func client() -> OpenRouterTranscriptionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranscriptionURLProtocol.self]
        return OpenRouterTranscriptionClient(session: URLSession(configuration: configuration))
    }
}

private final class TranscriptionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() { }
}

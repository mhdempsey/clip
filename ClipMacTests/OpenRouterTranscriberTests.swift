import AVFoundation
import ClipCore
import XCTest
@testable import Clip

final class OpenRouterTranscriberTests: XCTestCase {
    func testDuplicateAudioNamesFailDuringPreflight() async throws {
        let source = PairingSnapshot(
            epubURL: URL(fileURLWithPath: "/unused/book.epub"),
            audio: [
                AudioSource(url: URL(fileURLWithPath: "/part-one/Chapter.mp3"), duration: 180),
                AudioSource(url: URL(fileURLWithPath: "/part-two/chapter.mp3"), duration: 180)
            ],
            title: "Book", author: "Author", coverData: nil
        )
        do {
            _ = try await AlignmentPipeline.run(
                source: source, quality: .standard, transcriber: WhisperTranscriber(),
                cloudTranscriber: OpenRouterTranscriber(), location: .openRouter,
                apiKey: "test-key", spendingLimitUSD: 1
            ) { _ in }
            XCTFail("Duplicate destination names must fail before any transcription work")
        } catch BundleWriterError.duplicateAudioFilename("chapter.mp3") { }
    }

    func testInsufficientBudgetDoesNotStartPaidUploads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("book.m4a")
        try Data().write(to: url)
        let state = UploadState()
        MacTranscriptionURLProtocol.state = state
        defer { MacTranscriptionURLProtocol.state = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MacTranscriptionURLProtocol.self]
        let client = OpenRouterTranscriptionClient(session: URLSession(configuration: configuration))
        let transcriber = OpenRouterTranscriber(cache: TranscriptCache(directory: directory), client: client)
        do {
            _ = try await transcriber.transcribe(audio: [AudioSource(url: url, duration: 400)], apiKey: "test-key", spendingLimitUSD: 0.001) { _ in }
            XCTFail("An insufficient budget must stop before uploading")
        } catch OpenRouterTranscriptionError.spendingLimit { }
        XCTAssertEqual(state.requestCount, 0)
    }

    func testExportsRealAudioAndResumesWithoutUploadingCompletedChunksAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("book.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
            buffer.frameLength = 8_000
            buffer.floatChannelData![0].initialize(repeating: 0, count: 8_000)
            for _ in 0..<400 { try file.write(from: buffer) }
        }

        let state = UploadState()
        MacTranscriptionURLProtocol.state = state
        defer { MacTranscriptionURLProtocol.state = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MacTranscriptionURLProtocol.self]
        let cache = TranscriptCache(directory: directory.appendingPathComponent("cache"))
        let client = OpenRouterTranscriptionClient(session: URLSession(configuration: configuration))
        let transcriber = OpenRouterTranscriber(cache: cache, client: client)
        let audio = [AudioSource(url: url, duration: 400)]

        do {
            _ = try await transcriber.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 1) { _ in }
            XCTFail("The second upload should fail")
        } catch OpenRouterTranscriptionError.httpStatus(503) { }
        XCTAssertEqual(state.requestCount, 2)

        // A fresh service simulates quitting and opening the app again.
        let resumed = OpenRouterTranscriber(cache: cache, client: client)
        let result = try await resumed.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 1) { _ in }
        XCTAssertEqual(state.requestCount, 4, "Only the two unfinished chunks should upload")
        XCTAssertEqual(result.map(\.text), ["Hello", "there", "Hello", "there", "Hello", "there"])
        XCTAssertEqual(result.map(\.start), [3, 4, 181, 182, 361, 362])
        XCTAssertEqual(Set(state.uploadDurations.map { Int($0.rounded()) }), [42, 182, 184], "The wire payloads must contain the requested audio spans, including overlap")

        let cached = try await resumed.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 1) { _ in }
        XCTAssertEqual(cached, result)
        XCTAssertEqual(state.requestCount, 4, "The finished transcript should be reused for free")
    }

    func testRetriesMissingTimestampsAndCountsBothChargesBeforeCaching() async throws {
        try await withMissingTimestampFixture { transcriber, audio, state in
            let result = try await transcriber.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 1) {
                state.record(update: $0)
            }
            XCTAssertEqual(result.map(\.text), ["Hello", "there"])
            XCTAssertEqual(state.requestCount, 2)
            XCTAssertEqual(state.spentUSD, 0.002, accuracy: 0.000001)
            let cached = try await transcriber.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 1) { _ in }
            XCTAssertEqual(cached, result)
            XCTAssertEqual(state.requestCount, 2, "Successful recovery must be cached")
        }
    }

    func testMissingTimestampRetryStopsAtBudgetAndDoesNotCacheUntimedText() async throws {
        try await withMissingTimestampFixture { transcriber, audio, state in
            do {
                _ = try await transcriber.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 0.0011) {
                    state.record(update: $0)
                }
                XCTFail("The first charge leaves insufficient budget for another upload")
            } catch OpenRouterTranscriptionError.spendingLimit { }
            XCTAssertEqual(state.requestCount, 1)
            XCTAssertEqual(state.spentUSD, 0.001, accuracy: 0.000001)
            let result = try await transcriber.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 1) { _ in }
            XCTAssertEqual(result.count, 2)
            XCTAssertEqual(state.requestCount, 2, "Untimed text must not be cached as completed audio")
        }
    }

    func testPersistentMissingTimestampsOnlyRetriesOnceAndCountsFailedCharges() async throws {
        try await withMissingTimestampFixture(missingResponses: 10) { transcriber, audio, state in
            do {
                _ = try await transcriber.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 1) {
                    state.record(update: $0)
                }
                XCTFail("Persistently missing timestamps must stop the run")
            } catch let error as OpenRouterTranscriptionError {
                XCTAssertTrue(error.localizedDescription.contains("word timestamps"))
            }
            XCTAssertEqual(state.requestCount, 2, "A bad response must not cause unlimited paid retries")
            XCTAssertEqual(state.spentUSD, 0.002, accuracy: 0.000001)
        }
    }

    func testMissingTimestampResponseWithoutCostStopsBeforeRetrying() async throws {
        try await withMissingTimestampFixture(reportedCost: nil) { transcriber, audio, state in
            do {
                _ = try await transcriber.transcribe(audio: audio, apiKey: "test-key", spendingLimitUSD: 1) { _ in }
                XCTFail("An unknown charge must stop further paid uploads")
            } catch OpenRouterTranscriptionError.missingCost { }
            XCTAssertEqual(state.requestCount, 1)
        }
    }

    private func withMissingTimestampFixture(
        missingResponses: Int = 1, reportedCost: Double? = 0.001,
        run: (OpenRouterTranscriber, [AudioSource], UploadState) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("book.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
            buffer.frameLength = 48_000
            buffer.floatChannelData![0].initialize(repeating: 0, count: 48_000)
            try file.write(from: buffer)
        }
        let state = UploadState(missingResponses: missingResponses, reportedCost: reportedCost, failsSecondUpload: false)
        MacTranscriptionURLProtocol.state = state
        defer { MacTranscriptionURLProtocol.state = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MacTranscriptionURLProtocol.self]
        let client = OpenRouterTranscriptionClient(session: URLSession(configuration: configuration))
        let transcriber = OpenRouterTranscriber(cache: TranscriptCache(directory: directory.appendingPathComponent("cache")), client: client)
        try await run(transcriber, [AudioSource(url: url, duration: 6)], state)
    }
}

private final class UploadState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var durations: [TimeInterval] = []
    private var spending: Double = 0
    private let missingResponses: Int
    private let reportedCost: Double?
    private let failsSecondUpload: Bool
    var requestCount: Int { lock.withLock { count } }
    var uploadDurations: [TimeInterval] { lock.withLock { durations } }
    var spentUSD: Double { lock.withLock { spending } }

    init(missingResponses: Int = 0, reportedCost: Double? = 0.001, failsSecondUpload: Bool = true) {
        self.missingResponses = missingResponses
        self.reportedCost = reportedCost
        self.failsSecondUpload = failsSecondUpload
    }

    func record(update: TranscriptionUpdate) {
        if case let .cloudSpending(cost) = update { lock.withLock { spending = cost } }
    }

    func record(duration: TimeInterval) {
        lock.withLock { durations.append(duration) }
    }

    func nextResponse() throws -> (Int, Data) {
        try lock.withLock {
            count += 1
            let status = failsSecondUpload && count == 2 ? 503 : 200
            var body: [String: Any] = ["text": "there Hello"]
            if count > missingResponses {
                body["words"] = [["word": "there", "start": 4, "end": 5], ["word": "Hello", "start": 3, "end": 4]]
            }
            if let reportedCost { body["usage"] = ["cost": reportedCost] }
            return (status, try JSONSerialization.data(withJSONObject: body))
        }
    }
}

private final class MacTranscriptionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var state: UploadState?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
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
            let audio = try XCTUnwrap(json["input_audio"] as? [String: String])
            let data = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(audio["data"])))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: url) }
            try data.write(to: url)
            let file = try AVAudioFile(forReading: url)
            Self.state!.record(duration: Double(file.length) / file.processingFormat.sampleRate)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let status: Int
        let data: Data
        do { (status, data) = try Self.state!.nextResponse() }
        catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        // Let the first successful chunk reach its durable cache before failing.
        if status == 503 { Thread.sleep(forTimeInterval: 1) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

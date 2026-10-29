import XCTest
import ClipCore
import GRDB
@testable import Clip

@MainActor
final class ReaderHighlightTests: XCTestCase {
    func testMissingPassagesAndFailedWritesNeverConfirmASavedClip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try ClipDatabase(url: root.appendingPathComponent("failure.sqlite"))
        defer { try? database.writer.close(); try? FileManager.default.removeItem(at: root) }
        let book = BookRecord(id: "failure", title: "Book", author: "Author", bundleURL: root.path, durationS: 10, positionS: 0, addedAt: Date())
        let sentence = SentenceRecord(bookId: book.id, i: 0, startS: 0, endS: 5, text: "A passage worth saving.", chapter: 0, p: 0, conf: 1)
        try database.save(book: book, sentences: [sentence])
        let log = ClipFeedbackLog()
        let service = ClipService(database: database, tokenProvider: { nil }, feedbackPublisher: { _, feedback in log.record(feedback.outcome) })
        let missing = try await service.clipSelection(bookID: book.id, sentenceIndices: 9...9)
        XCTAssertNil(missing)
        try await database.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_clip_save BEFORE INSERT ON clip_queue BEGIN SELECT RAISE(FAIL, 'simulated write failure'); END")
        }
        do {
            _ = try await service.clipSelection(bookID: book.id, sentenceIndices: 0...0)
            XCTFail("The failed write must propagate to the intent's error confirmation")
        } catch { }
        XCTAssertTrue(try database.clips(bookID: book.id).isEmpty)
        XCTAssertTrue(log.outcomes.isEmpty, "Only committed clips may show Saved")
    }

    func testClipIsConfirmedAfterDurableSaveAndBeforeReadwiseRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try ClipDatabase(url: root.appendingPathComponent("ack.sqlite"))
        defer { try? database.writer.close(); try? FileManager.default.removeItem(at: root) }
        let book = BookRecord(id: "ack", title: "Book", author: "Author", bundleURL: root.path, durationS: 10, positionS: 0, addedAt: Date())
        let sentence = SentenceRecord(bookId: book.id, i: 0, startS: 0, endS: 5, text: "A passage worth saving.", chapter: 0, p: 0, conf: 1)
        try database.save(book: book, sentences: [sentence])
        let log = ClipFeedbackLog()
        ClipAcknowledgementProtocol.checkBeforeSend = { XCTAssertEqual(log.outcomes, [.saved], "Confirmation must not wait for Readwise") }
        defer { ClipAcknowledgementProtocol.checkBeforeSend = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClipAcknowledgementProtocol.self]
        let service = ClipService(database: database, syncStore: SyncStore(database: database), transport: ReadwiseTransport(session: URLSession(configuration: configuration)), tokenProvider: { "fake-readwise-test-token" }, feedbackPublisher: { id, feedback in
            XCTAssertEqual(id, book.id)
            do {
                let clipID = try XCTUnwrap(feedback.clipID)
                XCTAssertEqual(try database.clips(bookID: id).map(\.id), [clipID], "Saved must mean the record is already committed")
            } catch { XCTFail("Confirmation arrived without a saved clip: \(error)") }
            log.record(feedback.outcome)
        })
        _ = try await service.clipSelection(bookID: book.id, sentenceIndices: 0...0)
        XCTAssertEqual(log.outcomes, [.saved])
        XCTAssertNotNil(try database.clips(bookID: book.id).first?.sentAt)
    }

    func testBookClipHistoryIncludesSentAndPendingClipsAndExcludesOtherBooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try ClipDatabase(url: root.appendingPathComponent("history.sqlite"))
        defer { try? database.writer.close(); try? FileManager.default.removeItem(at: root) }
        for id in ["first", "second"] {
            try database.save(book: BookRecord(id: id, title: id, author: "Author", bundleURL: root.path, durationS: 20, positionS: 0, addedAt: Date()), sentences: [])
        }
        let older = ClipQueueRecord(id: "sent", bookId: "first", text: "A sent highlight", note: "", location: 0, createdAt: Date(timeIntervalSince1970: 1), sentAt: Date(), attempts: 0)
        let newer = ClipQueueRecord(id: "pending", bookId: "first", text: "A saved highlight", note: "", location: 3, createdAt: Date(timeIntervalSince1970: 2), attempts: 0)
        let other = ClipQueueRecord(id: "other", bookId: "second", text: "Another book", note: "", location: 0, createdAt: Date(), attempts: 0)
        for item in [older, newer, other] { try database.insert(queueItem: item) }
        XCTAssertEqual(try database.clips(bookID: "first").map(\.id), ["pending", "sent"])
        XCTAssertEqual(try database.pendingClips().map(\.id), ["pending", "other"])
    }

    func testNativeSelectionQueuesExactWordsWithSentenceLocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try ClipDatabase(url: root.appendingPathComponent("reader.sqlite"))
        defer { try? database.writer.close(); try? FileManager.default.removeItem(at: root) }
        let book = BookRecord(id: "reader-selection", title: "A book", author: "An author", bundleURL: root.path, durationS: 10, positionS: 0, addedAt: Date())
        let sentence = SentenceRecord(bookId: book.id, i: 7, startS: nil, endS: nil, text: "A sentence worth keeping forever.", chapter: 0, p: 0, conf: 0)
        try database.save(book: book, sentences: [sentence])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderOfflineProtocol.self]
        let service = ClipService(database: database, syncStore: SyncStore(database: database), transport: ReadwiseTransport(session: URLSession(configuration: configuration)))

        _ = try await service.clipSelection(bookID: book.id, sentenceIndices: 7...7, selectedText: " worth keeping ")

        let queued = try XCTUnwrap(database.pendingClips().first)
        XCTAssertEqual(queued.text, "worth keeping")
        XCTAssertEqual(queued.location, 7)
        XCTAssertEqual(queued.bookId, book.id)
    }
}

private final class ClipFeedbackLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ClipActivityFeedback.Outcome] = []
    var outcomes: [ClipActivityFeedback.Outcome] { lock.withLock { values } }
    func record(_ outcome: ClipActivityFeedback.Outcome) { lock.withLock { values.append(outcome) } }
}

private final class ClipAcknowledgementProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var checkBeforeSend: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.checkBeforeSend?()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class ReaderOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

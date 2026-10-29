import ClipCore
import XCTest
@testable import Clip

final class ClipCaptureStoreTests: XCTestCase {
    func testBackgroundCaptureCommitsToBookHistoryWithoutThePlayerOrNetwork() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try ClipDatabase(url: root.appendingPathComponent("capture.sqlite"))
        defer { try? database.writer.close(); try? FileManager.default.removeItem(at: root) }
        let book = BookRecord(id: "background", title: "Book", author: "Author", bundleURL: root.path, durationS: 100, positionS: 0, addedAt: Date())
        let sentences = [
            SentenceRecord(bookId: book.id, i: 0, startS: 0, endS: 8, text: "Earlier words.", chapter: 0, p: 0, conf: 1),
            SentenceRecord(bookId: book.id, i: 1, startS: 8, endS: 20, text: "The first part.", chapter: 0, p: 1, conf: 1),
            SentenceRecord(bookId: book.id, i: 2, startS: 20, endS: 30, text: "The second part.", chapter: 0, p: 1, conf: 1)
        ]
        try database.save(book: book, sentences: sentences)
        let store = ClipCaptureStore(database: database, syncStore: SyncStore(database: database))
        let saved = try XCTUnwrap(store.capture(bookID: book.id, anchor: 25, window: 10))
        XCTAssertEqual(saved.item.text, "The first part. The second part.")
        XCTAssertEqual(saved.item.location, 1)
        XCTAssertNil(saved.item.sentAt)
        XCTAssertEqual(try database.clips(bookID: book.id).map(\.id), [saved.item.id])
        XCTAssertNil(try store.capture(bookID: book.id, anchor: 90, window: 10))
        XCTAssertEqual(try database.clips(bookID: book.id).count, 1, "Unmatched audio must not create a false saved clip")
    }

    func testOldLiveActivityStateStillDecodesWithoutFeedback() throws {
        let data = Data(#"{"elapsedS":10,"durationS":100,"isPlaying":true,"windowSeconds":15}"#.utf8)
        let state = try JSONDecoder().decode(ClipActivityAttributes.ContentState.self, from: data)
        XCTAssertNil(state.clipFeedback)
        XCTAssertEqual(state.elapsedS, 10)
    }
}

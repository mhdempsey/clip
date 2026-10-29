import Foundation
import XCTest
@testable import Clip

final class SyncStoreTests: XCTestCase {
    func testNearestPrecedingSentenceDoesNotReturnStaleText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let database = try ClipDatabase(url: root.appendingPathComponent("clip.sqlite"))
        defer {
            try? database.writer.close()
            try? FileManager.default.removeItem(at: root)
        }
        let book = BookRecord(
            id: "book",
            title: "Book",
            author: "Author",
            bundleURL: root.appendingPathComponent("Book.clipbook").path,
            durationS: 300,
            coverPath: nil,
            positionS: 0,
            addedAt: Date(),
            lastPlayedAt: nil
        )
        let sentence = SentenceRecord(
            bookId: book.id,
            i: 0,
            startS: 0,
            endS: 4,
            text: "A nearby sentence.",
            chapter: 0,
            p: 0,
            conf: 1
        )
        let oversized = SentenceRecord(
            bookId: book.id,
            i: 1,
            startS: 30,
            endS: 200,
            text: "A corrupted sentence stretched across several minutes.",
            chapter: 0,
            p: 1,
            conf: 1
        )
        let lowConfidence = SentenceRecord(
            bookId: book.id,
            i: 2,
            startS: 210,
            endS: 214,
            text: "An accidental low-confidence match.",
            chapter: 0,
            p: 2,
            conf: 0.25
        )
        try database.save(book: book, sentences: [sentence, oversized, lowConfidence])
        let store = SyncStore(database: database)

        XCTAssertNotNil(try store.nearestPrecedingSentence(bookId: book.id, at: 20))
        XCTAssertNil(try store.nearestPrecedingSentence(bookId: book.id, at: 40))
        XCTAssertTrue(try store.sentences(bookId: book.id, overlapping: 100...100).isEmpty)
        XCTAssertNil(try store.containingSentence(bookId: book.id, at: 100))
        XCTAssertTrue(try store.sentences(bookId: book.id, overlapping: 210...212).isEmpty)
        XCTAssertNil(try store.containingSentence(bookId: book.id, at: 212))
        XCTAssertNil(try store.nearestPrecedingSentence(bookId: book.id, at: 220))
    }
}

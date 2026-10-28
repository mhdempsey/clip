import Foundation
import GRDB
import XCTest
@testable import Clip

final class LibraryTests: XCTestCase {
    func testSortsAndReadFiltersHaveStableResults() {
        var a = book("a", title: "Chapter 10", author: "Zed", added: 10)
        var b = book("b", title: "Chapter 2", author: "Alice", added: 20)
        let c = book("c", title: "Chapter 2", author: "Alice", added: 30)
        a.lastPlayedAt = Date(timeIntervalSince1970: 100)
        a.positionS = 80
        b.readAt = Date()
        let books = [c, a, b]
        XCTAssertEqual(LibrarySort.title.sorted(books).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(LibrarySort.author.sorted(books).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(LibrarySort.recent.sorted(books).map(\.id), ["a", "c", "b"])
        XCTAssertEqual(LibrarySort.added.sorted(books).map(\.id), ["c", "b", "a"])
        XCTAssertEqual(LibrarySort.progress.sorted(books).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(books.filter(LibraryFilter.reading.includes).map(\.id), ["c", "a"])
        XCTAssertEqual(books.filter(LibraryFilter.read.includes).map(\.id), ["b"])
        XCTAssertEqual(books.filter(LibraryFilter.all.includes).count, 3)
    }

    func testReadArchiveSurvivesReimportAndCanBeRestoredWithoutLosingProgress() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try ClipDatabase(url: directory.appendingPathComponent("test.sqlite"))
        defer { try? database.writer.close(); try? FileManager.default.removeItem(at: directory) }
        let original = book("book", title: "A book", author: "Author", added: 1)
        let sentence = SentenceRecord(bookId: original.id, i: 0, startS: 0, endS: 1, text: "A passage.", chapter: 0, p: 0, conf: 1)
        try database.save(book: original, sentences: [sentence])
        try database.updatePosition(bookID: original.id, position: 42)
        try database.setRead(bookID: original.id, isRead: true)
        let archived = try XCTUnwrap(database.book(id: original.id))
        XCTAssertTrue(archived.isRead)
        try database.save(book: original, sentences: [sentence])
        let imported = try XCTUnwrap(database.book(id: original.id))
        XCTAssertEqual(imported.readAt, archived.readAt)
        XCTAssertEqual(imported.positionS, 42)
        XCTAssertEqual(try database.sentences(bookID: original.id), [sentence])
        try database.setRead(bookID: original.id, isRead: false)
        XCTAssertFalse(try XCTUnwrap(database.book(id: original.id)).isRead)
        XCTAssertEqual(try database.book(id: original.id)?.positionS, 42)
    }

    func testExistingLibraryMigratesWithoutLosingBooksOrPlaybackPosition() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("old.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try DatabaseQueue(path: url.path)
        try old.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('createClipSchema');
                CREATE TABLE book (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL,
                  bundleURL TEXT NOT NULL, durationS DOUBLE NOT NULL, coverPath TEXT,
                  positionS DOUBLE NOT NULL, addedAt DATETIME NOT NULL, lastPlayedAt DATETIME);
                INSERT INTO book VALUES ('old', 'Existing book', 'Author', '/book', 100, NULL, 37, '2026-01-01 00:00:00', NULL);
                """)
        }
        try old.close()
        let database = try ClipDatabase(url: url)
        defer { try? database.writer.close() }
        let migrated = try XCTUnwrap(database.books().first)
        XCTAssertEqual(migrated.title, "Existing book")
        XCTAssertEqual(migrated.positionS, 37)
        XCTAssertFalse(migrated.isRead)
        try database.setRead(bookID: migrated.id, isRead: true)
        XCTAssertTrue(try XCTUnwrap(database.book(id: migrated.id)).isRead)
    }

    private func book(_ id: String, title: String, author: String, added: Double) -> BookRecord {
        BookRecord(id: id, title: title, author: author, bundleURL: "/unused", durationS: 100, positionS: 0, addedAt: Date(timeIntervalSince1970: added))
    }
}

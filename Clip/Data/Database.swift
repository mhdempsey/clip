import Foundation
import GRDB

struct BookRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "book"

    var id: String
    var title: String
    var author: String
    var bundleURL: String
    var durationS: Double
    var coverPath: String?
    var positionS: Double
    var addedAt: Date
    var lastPlayedAt: Date?

    var bundleFileURL: URL { URL(fileURLWithPath: bundleURL, isDirectory: true) }
    var coverURL: URL? { coverPath.map { bundleFileURL.appendingPathComponent($0) } }
}

struct SentenceRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "sentence"

    var bookId: String
    var i: Int
    var startS: Double?
    var endS: Double?
    var text: String
    var chapter: Int
    var p: Int
    var conf: Double

    var id: String { "\(bookId):\(i)" }
    var isTimed: Bool { conf > 0 && startS != nil && endS != nil }
}

struct ClipQueueRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "clip_queue"

    var id: String
    var bookId: String
    var text: String
    var note: String
    var location: Int
    var createdAt: Date
    var sentAt: Date?
    var attempts: Int
    var lastError: String?

    var isFlagged: Bool { attempts >= 10 }
}

final class ClipDatabase: @unchecked Sendable {
    static let shared: ClipDatabase = {
        do { return try ClipDatabase() }
        catch { fatalError("Could not open Clip database: \(error)") }
    }()

    let writer: any DatabaseWriter

    init(url: URL = AppGroup.databaseURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        writer = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(writer)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createClipSchema") { db in
            try db.create(table: "book", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("author", .text).notNull()
                table.column("bundleURL", .text).notNull()
                table.column("durationS", .double).notNull()
                table.column("coverPath", .text)
                table.column("positionS", .double).notNull().defaults(to: 0)
                table.column("addedAt", .datetime).notNull()
                table.column("lastPlayedAt", .datetime)
            }
            try db.create(table: "sentence", ifNotExists: true) { table in
                table.column("bookId", .text).notNull()
                    .references("book", onDelete: .cascade)
                table.column("i", .integer).notNull()
                table.column("startS", .double)
                table.column("endS", .double)
                table.column("text", .text).notNull()
                table.column("chapter", .integer).notNull()
                table.column("p", .integer).notNull()
                table.column("conf", .double).notNull()
                table.primaryKey(["bookId", "i"])
            }
            try db.create(index: "sentence_time", on: "sentence", columns: ["bookId", "startS"], ifNotExists: true)
            try db.create(table: "clip_queue", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("bookId", .text).notNull()
                    .references("book", onDelete: .cascade)
                table.column("text", .text).notNull()
                table.column("note", .text).notNull()
                table.column("location", .integer).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("sentAt", .datetime)
                table.column("attempts", .integer).notNull().defaults(to: 0)
                table.column("lastError", .text)
            }
        }
        return migrator
    }

    func books() throws -> [BookRecord] {
        try writer.read { db in
            try BookRecord.order(
                Column("lastPlayedAt").desc,
                Column("addedAt").desc
            ).fetchAll(db)
        }
    }

    func book(id: String) throws -> BookRecord? {
        try writer.read { db in try BookRecord.fetchOne(db, key: id) }
    }

    func save(book: BookRecord, sentences: [SentenceRecord]) throws {
        try writer.write { db in
            var preserved = book
            if let existing = try BookRecord.fetchOne(db, key: book.id) {
                preserved.positionS = existing.positionS
                preserved.lastPlayedAt = existing.lastPlayedAt
                preserved.addedAt = existing.addedAt
            }
            try preserved.save(db)
            try SentenceRecord
                .filter(Column("bookId") == book.id)
                .deleteAll(db)
            let insertSentence = try db.makeStatement(sql: """
                INSERT INTO sentence (bookId, i, startS, endS, text, chapter, p, conf)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for sentence in sentences {
                try insertSentence.execute(arguments: [
                    sentence.bookId,
                    sentence.i,
                    sentence.startS,
                    sentence.endS,
                    sentence.text,
                    sentence.chapter,
                    sentence.p,
                    sentence.conf
                ])
            }
        }
    }

    func updatePosition(bookID: String, position: Double) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE book SET positionS = ?, lastPlayedAt = ? WHERE id = ?",
                arguments: [max(0, position), Date(), bookID]
            )
        }
    }

    func sentences(bookID: String) throws -> [SentenceRecord] {
        try writer.read { db in
            try SentenceRecord
                .filter(Column("bookId") == bookID)
                .order(Column("i"))
                .fetchAll(db)
        }
    }

    func sentences(bookID: String, indices: ClosedRange<Int>) throws -> [SentenceRecord] {
        try writer.read { db in
            try SentenceRecord
                .filter(
                    Column("bookId") == bookID &&
                    Column("i") >= indices.lowerBound &&
                    Column("i") <= indices.upperBound
                )
                .order(Column("i"))
                .fetchAll(db)
        }
    }

    func insert(queueItem: ClipQueueRecord) throws {
        try writer.write { db in try queueItem.insert(db) }
    }

    func pendingClips() throws -> [ClipQueueRecord] {
        try writer.read { db in
            try ClipQueueRecord
                .filter(Column("sentAt") == nil)
                .order(Column("createdAt"))
                .fetchAll(db)
        }
    }

    func queueItem(id: String) throws -> ClipQueueRecord? {
        try writer.read { db in try ClipQueueRecord.fetchOne(db, key: id) }
    }

    func pendingClipCount() throws -> Int {
        try writer.read { db in
            try ClipQueueRecord.filter(Column("sentAt") == nil).fetchCount(db)
        }
    }

    func update(queueItem: ClipQueueRecord) throws {
        try writer.write { db in try queueItem.update(db) }
    }

    func deleteQueueItem(id: String) throws {
        _ = try writer.write { db in try ClipQueueRecord.deleteOne(db, key: id) }
    }
}

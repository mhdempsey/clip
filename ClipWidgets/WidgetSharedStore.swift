import ClipCore
import Foundation
import GRDB

enum WidgetAppGroup {
    static let identifier = ClipShared.appGroupIdentifier

    enum Key {
        static let currentBookID = ClipShared.DefaultsKey.currentBookID
        static let currentPosition = ClipShared.DefaultsKey.currentPosition
        static let clipWindow = ClipShared.DefaultsKey.clipWindow
        static let playbackCommand = ClipShared.DefaultsKey.playbackCommand
        static let isPlaying = ClipShared.DefaultsKey.isPlaying
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
    static var databaseURL: URL? { containerURL?.appendingPathComponent("clip.sqlite") }
    static var windowSeconds: Int {
        let stored = defaults.integer(forKey: Key.clipWindow)
        return ClipShared.validatedClipWindow(stored)
    }
}

struct WidgetClipStore {
    struct Book: Decodable, FetchableRecord {
        let id: String
        let bundleURL: String
        let coverPath: String?
    }

    struct Sentence: Decodable, FetchableRecord {
        let i: Int
        let text: String
        let p: Int
    }

    func enqueueCurrentClip() throws -> Bool {
        guard let databaseURL = WidgetAppGroup.databaseURL,
              FileManager.default.fileExists(atPath: databaseURL.path),
              let bookID = WidgetAppGroup.defaults.string(forKey: WidgetAppGroup.Key.currentBookID) else { return false }
        let position = max(0, WidgetAppGroup.defaults.double(forKey: WidgetAppGroup.Key.currentPosition))
        let window = Double(WidgetAppGroup.windowSeconds)
        let queue = try DatabaseQueue(path: databaseURL.path)
        return try queue.write { db in
            guard let book = try Book.fetchOne(db, sql: "SELECT id, bundleURL, coverPath FROM book WHERE id = ?", arguments: [bookID]) else {
                return false
            }
            let chapter: Int? = try Int.fetchOne(
                db,
                sql: "SELECT chapter FROM sentence WHERE bookId = ? AND conf > 0 AND startS <= ? ORDER BY startS DESC LIMIT 1",
                arguments: [bookID, position]
            )
            guard let chapter else { return false }
            var sentences = try overlappingSentences(
                in: db,
                bookID: bookID,
                chapter: chapter,
                upperBound: position,
                lowerBound: max(0, position - window)
            )
            if sentences.isEmpty {
                sentences = try overlappingSentences(
                    in: db,
                    bookID: bookID,
                    chapter: chapter,
                    upperBound: position,
                    lowerBound: max(0, position - window - 5)
                )
            }
            if sentences.isEmpty, let preceding = try Sentence.fetchOne(
                db,
                sql: """
                    SELECT i, text, p FROM sentence
                    WHERE bookId = ? AND conf > 0 AND endS <= ? ORDER BY endS DESC LIMIT 1
                    """,
                arguments: [bookID, position]
            ) {
                sentences = [preceding]
            }
            guard let first = sentences.first else { return false }
            var text = ""
            for (index, sentence) in sentences.enumerated() {
                if index > 0 { text += sentence.p == sentences[index - 1].p ? " " : "\n\n" }
                text += sentence.text
            }
            try db.execute(
                sql: """
                    INSERT INTO clip_queue
                    (id, bookId, text, note, location, createdAt, sentAt, attempts, lastError)
                    VALUES (?, ?, ?, ?, ?, ?, NULL, 0, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    book.id,
                    text,
                    "audio @ \(ClipShared.formattedAudioTime(position))",
                    first.i,
                    Date(),
                    "Queued from Live Activity"
                ]
            )
            return true
        }
    }

    func coverImagePath(bookID: String) -> String? {
        guard let url = WidgetAppGroup.databaseURL,
              let queue = try? DatabaseQueue(path: url.path),
              let book = try? queue.read({ db in
                  try Book.fetchOne(db, sql: "SELECT id, bundleURL, coverPath FROM book WHERE id = ?", arguments: [bookID])
              }), let cover = book.coverPath else { return nil }
        return URL(fileURLWithPath: book.bundleURL).appendingPathComponent(cover).path
    }

    private func overlappingSentences(
        in database: Database,
        bookID: String,
        chapter: Int,
        upperBound: Double,
        lowerBound: Double
    ) throws -> [Sentence] {
        try Sentence.fetchAll(
            database,
            sql: """
                SELECT i, text, p FROM sentence
                WHERE bookId = ? AND chapter = ? AND conf > 0
                  AND startS <= ? AND endS >= ? ORDER BY i
                """,
            arguments: [bookID, chapter, upperBound, lowerBound]
        )
    }
}

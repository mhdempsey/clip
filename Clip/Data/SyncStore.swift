import Foundation
import GRDB

struct SyncStore: Sendable {
    let database: ClipDatabase

    init(database: ClipDatabase = .shared) {
        self.database = database
    }

    /// Returns complete timed sentences intersecting `range`, constrained to the
    /// chapter at the range's trailing edge. The `sentence_time` index makes the
    /// upper-bound scan cheap; GRDB performs no in-memory full-book filtering.
    func sentences(bookId: String, overlapping range: ClosedRange<Double>) throws -> [SentenceRecord] {
        let lower = max(0, range.lowerBound)
        let upper = max(lower, range.upperBound)

        return try database.writer.read { db in
            let chapter: Int? = try Int.fetchOne(
                db,
                sql: """
                    SELECT chapter FROM sentence
                    WHERE bookId = ? AND conf > 0 AND startS <= ? AND endS >= ?
                    ORDER BY startS DESC LIMIT 1
                    """,
                arguments: [bookId, upper, upper]
            ) ?? Int.fetchOne(
                db,
                sql: """
                    SELECT chapter FROM sentence
                    WHERE bookId = ? AND conf > 0 AND startS <= ?
                    ORDER BY startS DESC LIMIT 1
                    """,
                arguments: [bookId, upper]
            )

            guard let chapter else { return [] }
            return try SentenceRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM sentence
                    WHERE bookId = ? AND chapter = ? AND conf > 0
                      AND startS <= ? AND endS >= ?
                    ORDER BY i
                    """,
                arguments: [bookId, chapter, upper, lower]
            )
        }
    }

    func containingSentence(bookId: String, at time: Double) throws -> SentenceRecord? {
        try database.writer.read { db in
            try SentenceRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM sentence
                    WHERE bookId = ? AND conf > 0 AND startS <= ? AND endS >= ?
                    ORDER BY startS DESC LIMIT 1
                    """,
                arguments: [bookId, time, time]
            )
        }
    }

    func nearestPrecedingSentence(bookId: String, at time: Double) throws -> SentenceRecord? {
        try database.writer.read { db in
            try SentenceRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM sentence
                    WHERE bookId = ? AND conf > 0 AND endS <= ?
                    ORDER BY endS DESC LIMIT 1
                    """,
                arguments: [bookId, time]
            )
        }
    }
}

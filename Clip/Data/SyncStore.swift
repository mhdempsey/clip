import Foundation
import GRDB

struct SyncStore: Sendable {
    private static let minimumClippingConfidence = 0.5
    private static let maximumSentenceDuration = 120.0
    private static let maximumApproximationGap = 30.0
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
                    WHERE bookId = ? AND conf >= ? AND startS <= ? AND endS >= ?
                      AND endS - startS <= ?
                    ORDER BY startS DESC LIMIT 1
                    """,
                arguments: [bookId, Self.minimumClippingConfidence, upper, upper, Self.maximumSentenceDuration]
            ) ?? Int.fetchOne(
                db,
                sql: """
                    SELECT chapter FROM sentence
                    WHERE bookId = ? AND conf >= ? AND startS <= ?
                      AND endS - startS <= ?
                    ORDER BY startS DESC LIMIT 1
                    """,
                arguments: [bookId, Self.minimumClippingConfidence, upper, Self.maximumSentenceDuration]
            )

            guard let chapter else { return [] }
            return try SentenceRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM sentence
                    WHERE bookId = ? AND chapter = ? AND conf >= ?
                      AND endS - startS <= ?
                      AND startS <= ? AND endS >= ?
                    ORDER BY i
                    """,
                arguments: [
                    bookId, chapter, Self.minimumClippingConfidence,
                    Self.maximumSentenceDuration, upper, lower,
                ]
            )
        }
    }

    func containingSentence(bookId: String, at time: Double) throws -> SentenceRecord? {
        try database.writer.read { db in
            try SentenceRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM sentence
                    WHERE bookId = ? AND conf >= ? AND startS <= ? AND endS >= ?
                      AND endS - startS <= ?
                    ORDER BY startS DESC LIMIT 1
                    """,
                arguments: [bookId, Self.minimumClippingConfidence, time, time, Self.maximumSentenceDuration]
            )
        }
    }

    func nearestPrecedingSentence(bookId: String, at time: Double) throws -> SentenceRecord? {
        let earliestEnd = max(0, time - Self.maximumApproximationGap)
        return try database.writer.read { db in
            try SentenceRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM sentence
                    WHERE bookId = ? AND conf >= ? AND endS <= ? AND endS >= ?
                      AND endS - startS <= ?
                    ORDER BY endS DESC LIMIT 1
                    """,
                arguments: [
                    bookId, Self.minimumClippingConfidence, time, earliestEnd,
                    Self.maximumSentenceDuration,
                ]
            )
        }
    }
}

import ClipCore
import Foundation

struct ClipCaptureStore: Sendable {
    let database: ClipDatabase
    let syncStore: SyncStore

    func capture(bookID: String, anchor: Double, window: Double) throws -> (book: BookRecord, item: ClipQueueRecord)? {
        guard anchor.isFinite, anchor >= 0, let book = try database.book(id: bookID) else { return nil }
        let anchor = min(anchor, book.durationS)
        var sentences = try syncStore.sentences(bookId: book.id, overlapping: max(0, anchor - window)...anchor)
        if sentences.isEmpty {
            sentences = try syncStore.sentences(bookId: book.id, overlapping: max(0, anchor - window - 5)...anchor)
        }
        var approximate = false
        if sentences.isEmpty, let containing = try syncStore.containingSentence(bookId: book.id, at: anchor) { sentences = [containing] }
        if sentences.isEmpty, let preceding = try syncStore.nearestPrecedingSentence(bookId: book.id, at: anchor) {
            sentences = [preceding]
            approximate = true
        }
        guard !sentences.isEmpty else { return nil }
        return try save(book: book, sentences: sentences, anchor: anchor, approximate: approximate)
    }

    func selection(bookID: String, indices: ClosedRange<Int>, text: String?) throws -> (book: BookRecord, item: ClipQueueRecord)? {
        guard let book = try database.book(id: bookID) else { return nil }
        let sentences = try database.sentences(bookID: bookID, indices: indices)
        guard !sentences.isEmpty else { return nil }
        return try save(book: book, sentences: sentences, anchor: sentences.compactMap(\.endS).max() ?? book.positionS, approximate: false, selectedText: text)
    }

    private func save(book: BookRecord, sentences: [SentenceRecord], anchor: Double, approximate: Bool, selectedText: String? = nil) throws -> (book: BookRecord, item: ClipQueueRecord) {
        let ordered = sentences.sorted { $0.i < $1.i }
        var fragments: [String] = []
        for (index, sentence) in ordered.enumerated() {
            if index > 0, sentence.p != ordered[index - 1].p { fragments.append("\n\n") }
            fragments.append(sentence.text.trimmingCharacters(in: .whitespacesAndNewlines))
            if index + 1 < ordered.count, ordered[index + 1].p == sentence.p { fragments.append(" ") }
        }
        let selected = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ClipQueueRecord(
            id: UUID().uuidString, bookId: book.id,
            text: selected.flatMap { $0.isEmpty ? nil : $0 } ?? fragments.joined(),
            note: "audio @ \(ClipShared.formattedAudioTime(anchor))" + (approximate ? " · approximate" : ""),
            location: ordered[0].i, createdAt: Date(), attempts: 0
        )
        try database.insert(queueItem: item)
        return (book, item)
    }
}

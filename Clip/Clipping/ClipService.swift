import Foundation
import ClipCore
import UIKit

struct ClipResult: Sendable {
    let queuedOffline: Bool
}

@MainActor
final class ClipService: ObservableObject {
    static let shared = ClipService()

    @Published private(set) var toast: String?
    @Published private(set) var pendingCount = 0

    private let database: ClipDatabase
    private let syncStore: SyncStore
    private let transport: ReadwiseTransport
    private var toastTask: Task<Void, Never>?
    private var externalClipObserver: DarwinNotificationObservation?

    init(
        database: ClipDatabase = .shared,
        syncStore: SyncStore = SyncStore(),
        transport: ReadwiseTransport = ReadwiseTransport()
    ) {
        self.database = database
        self.syncStore = syncStore
        self.transport = transport
        refreshPendingCount()
        externalClipObserver = DarwinNotificationObservation(
            name: ClipShared.DarwinNotification.clipCommand
        ) { [weak self] in
            Task { @MainActor in self?.processExternalClipCommands() }
        }
        processExternalClipCommands()
    }

    func processExternalClipCommands() {
        let defaults = AppGroup.defaults
        let sequence = defaults.integer(forKey: AppGroup.Key.clipCommandSequence)
        let handled = defaults.integer(forKey: AppGroup.Key.handledClipCommandSequence)
        guard sequence > handled else { return }

        defaults.set(sequence, forKey: AppGroup.Key.handledClipCommandSequence)
        let count = min(sequence - handled, 20)
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<count {
                _ = try? await clipNow()
            }
        }
    }

    func clipNow() async throws -> ClipResult? {
        let defaults = AppGroup.defaults
        let player = PlayerEngine.shared
        guard let bookID = player.currentBook?.id ?? defaults.string(forKey: AppGroup.Key.currentBookID) else {
            return nil
        }
        let resolvedBook: BookRecord?
        if let currentBook = player.currentBook {
            resolvedBook = currentBook
        } else {
            resolvedBook = try database.book(id: bookID)
        }
        guard let book = resolvedBook, let anchor = player.clipAnchorTime() else { return nil }

        let window = Double(AppGroup.clipWindowSeconds)
        var sentences = try syncStore.sentences(
            bookId: book.id,
            overlapping: max(0, anchor - window)...anchor
        )
        if sentences.isEmpty {
            sentences = try syncStore.sentences(
                bookId: book.id,
                overlapping: max(0, anchor - window - 5)...anchor
            )
        }

        var approximate = false
        if sentences.isEmpty, let containing = try syncStore.containingSentence(bookId: book.id, at: anchor) {
            sentences = [containing]
        }
        if sentences.isEmpty, let preceding = try syncStore.nearestPrecedingSentence(bookId: book.id, at: anchor) {
            sentences = [preceding]
            approximate = true
        }
        guard !sentences.isEmpty else { return nil }
        return try await enqueue(book: book, sentences: sentences, anchor: anchor, approximate: approximate)
    }

    func clipSelection(bookID: String, sentenceIndices: ClosedRange<Int>) async throws -> ClipResult? {
        guard let book = try database.book(id: bookID) else { return nil }
        let selected = try database.sentences(bookID: bookID, indices: sentenceIndices)
        guard !selected.isEmpty else { return nil }
        let anchor = selected.compactMap(\.endS).max() ?? book.positionS
        return try await enqueue(book: book, sentences: selected, anchor: anchor, approximate: false)
    }

    func flushPending(force: Bool = false) async {
        guard let token = KeychainStore.readwiseToken, !token.isEmpty else {
            refreshPendingCount()
            return
        }
        do {
            var booksByID: [String: BookRecord] = [:]
            for item in try database.pendingClips() {
                if !force && !eligibleForRetry(item) { continue }
                let book: BookRecord
                if let cached = booksByID[item.bookId] {
                    book = cached
                } else {
                    guard let fetched = try database.book(id: item.bookId) else { continue }
                    booksByID[item.bookId] = fetched
                    book = fetched
                }
                _ = await send(item, book: book, token: token)
            }
        } catch {
            // The durable queue remains the source of truth; a later trigger retries.
        }
        refreshPendingCount()
        NotificationCenter.default.post(name: .clipQueueDidChange, object: nil)
        ClipBackgroundRefresh.schedule()
    }

    func retry(id: String) async {
        guard let item = try? database.queueItem(id: id),
              let book = try? database.book(id: item.bookId),
              let token = KeychainStore.readwiseToken else { return }
        _ = await send(item, book: book, token: token)
        refreshPendingCount()
        NotificationCenter.default.post(name: .clipQueueDidChange, object: nil)
    }

    func delete(id: String) {
        try? database.deleteQueueItem(id: id)
        refreshPendingCount()
        NotificationCenter.default.post(name: .clipQueueDidChange, object: nil)
    }

    func refreshPendingCount() {
        pendingCount = (try? database.pendingClipCount()) ?? 0
    }

    private func enqueue(
        book: BookRecord,
        sentences: [SentenceRecord],
        anchor: Double,
        approximate: Bool
    ) async throws -> ClipResult {
        let ordered = sentences.sorted { $0.i < $1.i }
        var fragments: [String] = []
        for (index, sentence) in ordered.enumerated() {
            if index > 0, sentence.p != ordered[index - 1].p { fragments.append("\n\n") }
            fragments.append(sentence.text.trimmingCharacters(in: .whitespacesAndNewlines))
            if index + 1 < ordered.count, ordered[index + 1].p == sentence.p { fragments.append(" ") }
        }
        var note = "audio @ \(ClipFormatters.time(anchor))"
        if approximate { note += " · approximate" }
        let item = ClipQueueRecord(
            id: UUID().uuidString,
            bookId: book.id,
            text: fragments.joined(),
            note: note,
            location: ordered[0].i,
            createdAt: Date(),
            sentAt: nil,
            attempts: 0,
            lastError: nil
        )
        try database.insert(queueItem: item)
        refreshPendingCount()
        NotificationCenter.default.post(name: .clipQueueDidChange, object: nil)

        var queued = true
        if let token = KeychainStore.readwiseToken, !token.isEmpty {
            queued = !(await send(item, book: book, token: token))
        }
        refreshPendingCount()
        confirmClip()
        ClipBackgroundRefresh.schedule()
        return ClipResult(queuedOffline: queued)
    }

    private func send(_ item: ClipQueueRecord, book: BookRecord, token: String) async -> Bool {
        let highlight = ReadwiseTransport.Highlight(
            text: item.text,
            title: book.title,
            author: book.author,
            location: item.location,
            note: item.note,
            highlightedAt: item.createdAt
        )
        let result = await transport.send(highlight, token: token)
        var updated = item
        switch result {
        case .sent:
            updated.sentAt = Date()
            updated.lastError = nil
        case .invalidToken:
            updated.attempts += 1
            updated.lastError = "Readwise token invalid"
        case .retryable(let message), .rejected(let message):
            updated.attempts += 1
            updated.lastError = message
        }
        try? database.update(queueItem: updated)
        return updated.sentAt != nil
    }

    private func eligibleForRetry(_ item: ClipQueueRecord) -> Bool {
        guard !item.isFlagged else { return false }
        guard item.attempts > 0 else { return true }
        let exponent = min(item.attempts - 1, 8)
        let delay = min(pow(2, Double(exponent)) * 60, 6 * 60 * 60)
        return Date().timeIntervalSince(item.createdAt) >= delay
    }

    private func confirmClip() {
        guard UIApplication.shared.applicationState == .active else { return }
        Haptics.success()
        toastTask?.cancel()
        toast = "❦  Clipped."
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

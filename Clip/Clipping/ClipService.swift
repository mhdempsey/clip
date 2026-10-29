import Foundation
import ClipCore
import UIKit

struct ClipResult: Sendable {
    let queuedOffline: Bool
}

@MainActor
final class ClipService: ObservableObject {
    static let shared: ClipService = {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-player-fixture") { return ClipService(tokenProvider: { nil }) }
#endif
        return ClipService()
    }()

    @Published private(set) var toast: String?
    @Published private(set) var pendingCount = 0

    private let database: ClipDatabase
    private let captureStore: ClipCaptureStore
    private let transport: ReadwiseTransport
    private let tokenProvider: @MainActor () -> String?
    private let feedbackPublisher: @MainActor (String, ClipActivityFeedback) async -> Void
    private var toastTask: Task<Void, Never>?
    private var externalClipObserver: DarwinNotificationObservation?
    private var externalSavedObserver: DarwinNotificationObservation?

    init(
        database: ClipDatabase = .shared,
        syncStore: SyncStore? = nil,
        transport: ReadwiseTransport = ReadwiseTransport(),
        tokenProvider: @escaping @MainActor () -> String? = { KeychainStore.readwiseToken },
        feedbackPublisher: @escaping @MainActor (String, ClipActivityFeedback) async -> Void = { bookID, feedback in await feedback.publish(for: bookID) }
    ) {
        self.database = database
        self.captureStore = ClipCaptureStore(database: database, syncStore: syncStore ?? SyncStore(database: database))
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.feedbackPublisher = feedbackPublisher
        refreshPendingCount()
        externalClipObserver = DarwinNotificationObservation(
            name: ClipShared.DarwinNotification.clipCommand
        ) { [weak self] in
            Task { @MainActor in self?.processExternalClipCommands() }
        }
        externalSavedObserver = DarwinNotificationObservation(name: ClipShared.DarwinNotification.clipSaved) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshPendingCount()
                NotificationCenter.default.post(name: .clipQueueDidChange, object: nil)
                await self.flushPending()
            }
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
        guard let anchor = player.clipAnchorTime(),
              let capture = try captureStore.capture(bookID: bookID, anchor: anchor, window: Double(AppGroup.clipWindowSeconds)) else { return nil }
        return await completeCapture(capture.item, book: capture.book)
    }

    func clipSelection(bookID: String, sentenceIndices: ClosedRange<Int>, selectedText: String? = nil) async throws -> ClipResult? {
        guard let capture = try captureStore.selection(bookID: bookID, indices: sentenceIndices, text: selectedText) else { return nil }
        return await completeCapture(capture.item, book: capture.book)
    }

    func flushPending(force: Bool = false) async {
        guard let token = tokenProvider(), !token.isEmpty else {
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
              let token = tokenProvider() else { return }
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

    private func completeCapture(_ item: ClipQueueRecord, book: BookRecord) async -> ClipResult {
        refreshPendingCount()
        NotificationCenter.default.post(name: .clipQueueDidChange, object: nil)
        await feedbackPublisher(book.id, ClipActivityFeedback(outcome: .saved, clipID: item.id))
        confirmClip()
        ClipBackgroundRefresh.schedule()

        var queued = true
        if let token = tokenProvider(), !token.isEmpty {
            queued = !(await send(item, book: book, token: token))
        }
        refreshPendingCount()
        NotificationCenter.default.post(name: .clipQueueDidChange, object: nil)
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
        toast = "✓  Saved in Clip."
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

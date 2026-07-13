import Foundation
import ClipCore

@MainActor
final class BundleImporter: NSObject, ObservableObject {
    struct Download: Identifiable, Equatable {
        let id: String
        let title: String
        let progress: Double
    }

    @Published private(set) var downloads: [Download] = []
    @Published private(set) var iCloudAvailable = true
    @Published private(set) var lastError: String?

    var onImport: (() -> Void)?

    private let query = NSMetadataQuery()
    private let database: ClipDatabase
    private var observers: [NSObjectProtocol] = []
    private var inFlightPaths: Set<String> = []

    init(database: ClipDatabase = .shared) {
        self.database = database
        super.init()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K ENDSWITH[c] %@", NSMetadataItemFSNameKey, ".clipbook")
        query.notificationBatchingInterval = 0.5
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.consumeResults() }
            },
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.consumeResults() }
            }
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        query.stop()
    }

    func refresh() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        guard iCloudAvailable else {
            downloads = []
            query.stop()
            return
        }
        query.stop()
        query.start()
    }

    func deleteLocalCopy(of book: BookRecord) {
        do {
            try FileManager.default.evictUbiquitousItem(at: book.bundleFileURL)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func consumeResults() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var currentDownloads: [Download] = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                currentDownloads.append(.init(
                    id: url.path,
                    title: url.deletingPathExtension().lastPathComponent,
                    progress: min(max(percent / 100, 0), 1)
                ))
            } else {
                guard inFlightPaths.insert(url.path).inserted else { continue }
                Task { await importBundle(at: url) }
            }
        }
        downloads = currentDownloads
    }

    private func importBundle(at url: URL) async {
        defer { inFlightPaths.remove(url.path) }
        let syncURL = url.appendingPathComponent("sync.json")
        do {
            let values = try syncURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            var importDates = AppGroup.defaults.dictionary(forKey: AppGroup.Key.importDates) as? [String: Double] ?? [:]
            if importDates[url.path] == modified { return }

            let id = Self.stableID(for: url)
            let prepared = try await Task.detached(priority: .utility) {
                let data = try Data(contentsOf: syncURL, options: .mappedIfSafe)
                let sync = try JSONDecoder.clipSync.decode(ClipBookSync.self, from: data)
                try sync.validate()
                let cover = ["cover.jpg", "cover.jpeg", "cover.png"].first {
                    FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path)
                }
                let book = BookRecord(
                    id: id,
                    title: sync.book.title,
                    author: sync.book.author,
                    bundleURL: url.path,
                    durationS: sync.book.durationS,
                    coverPath: cover,
                    positionS: 0,
                    addedAt: Date(),
                    lastPlayedAt: nil
                )
                let sentences = sync.sentences.map {
                    SentenceRecord(
                        bookId: id,
                        i: $0.i,
                        startS: $0.startS,
                        endS: $0.endS,
                        text: $0.text,
                        chapter: $0.chapter,
                        p: $0.p,
                        conf: $0.conf
                    )
                }
                return (book, sentences)
            }.value
            try await Task.detached(priority: .utility) { [database] in
                try database.save(book: prepared.0, sentences: prepared.1)
            }.value
            importDates[url.path] = modified
            AppGroup.defaults.set(importDates, forKey: AppGroup.Key.importDates)
            onImport?()
        } catch {
            lastError = "Couldn’t open \(url.deletingPathExtension().lastPathComponent): \(error.localizedDescription)"
        }
    }

    nonisolated private static func stableID(for url: URL) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in url.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

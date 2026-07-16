import Foundation
import ClipCore

private enum BundleImportError: LocalizedError {
    case audioStillDownloading
    case invalidFileType
    case invalidPackage

    var errorDescription: String? {
        switch self {
        case .audioStillDownloading:
            "The audiobook audio is still downloading from iCloud. Pull to refresh in a moment."
        case .invalidFileType:
            "Choose a .clipbook audiobook package."
        case .invalidPackage:
            "This Clip book package is invalid or incomplete."
        }
    }
}

private struct PreparedBundle: Sendable {
    let book: BookRecord
    let sentences: [SentenceRecord]
}

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
    private let localBooksDirectory: URL
    private let resourceLoader: BundleResourceLoader
    private var observers: [NSObjectProtocol] = []
    private var inFlightPaths: Set<String> = []
    private var pendingImportPaths: Set<String> = []
    private var iCloudContainerURL: URL?
    private var containerLookupTask: Task<Void, Never>?

    init(
        database: ClipDatabase = .shared,
        localBooksDirectory: URL = AppGroup.containerURL.appendingPathComponent("Books", isDirectory: true),
        resourceLoader: BundleResourceLoader = BundleResourceLoader()
    ) {
        self.database = database
        self.localBooksDirectory = localBooksDirectory
        self.resourceLoader = resourceLoader
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
        containerLookupTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        query.stop()
    }

    func refresh() {
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        guard iCloudAvailable else {
            containerLookupTask?.cancel()
            containerLookupTask = nil
            iCloudContainerURL = nil
            downloads = []
            query.stop()
            return
        }

        guard iCloudContainerURL == nil else {
            startQuery()
            return
        }
        guard containerLookupTask == nil else { return }

        query.stop()
        containerLookupTask = Task { [weak self] in
            let containerURL = await Task.detached(priority: .utility) {
                FileManager.default.url(
                    forUbiquityContainerIdentifier: ClipShared.iCloudContainerIdentifier
                )
            }.value

            guard !Task.isCancelled, let self else { return }
            self.containerLookupTask = nil
            guard let containerURL else {
                self.lastError = "Clip couldn’t open its iCloud Drive container. Make sure iCloud Drive is enabled for Clip."
                return
            }

            self.iCloudContainerURL = containerURL
            self.lastError = nil
            self.startQuery()
        }
    }

    private func startQuery() {
        query.stop()
        query.start()
    }

    func importLocalBundle(at sourceURL: URL) async throws -> BookRecord {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let prepared = try await Task.detached(priority: .userInitiated) { [localBooksDirectory] in
            try Self.installLocalBundle(from: sourceURL, in: localBooksDirectory)
        }.value
        try await Task.detached(priority: .utility) { [database] in
            try database.save(book: prepared.book, sentences: prepared.sentences)
        }.value
        onImport?()
        return prepared.book
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
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    lastError = "Couldn’t start downloading \(url.deletingPathExtension().lastPathComponent): \(error.localizedDescription)"
                }
                currentDownloads.append(.init(
                    id: url.path,
                    title: url.deletingPathExtension().lastPathComponent,
                    progress: min(max(percent / 100, 0), 1)
                ))
            } else {
                guard inFlightPaths.insert(url.path).inserted else {
                    pendingImportPaths.insert(url.path)
                    continue
                }
                Task { await importBundle(at: url) }
            }
        }
        downloads = currentDownloads
    }

    private func importBundle(at url: URL) async {
        defer {
            inFlightPaths.remove(url.path)
            if pendingImportPaths.remove(url.path) != nil,
               inFlightPaths.insert(url.path).inserted {
                Task { await importBundle(at: url) }
            }
        }
        let syncURL = url.appendingPathComponent("sync.json")
        do {
            var importDates = AppGroup.defaults.dictionary(forKey: AppGroup.Key.importDates) as? [String: Double] ?? [:]
            let initialModified = try? syncURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate?.timeIntervalSince1970
            if let initialModified, importDates[url.path] == initialModified {
                lastError = nil
                return
            }

            let data = try await resourceLoader.data(at: syncURL, in: url)
            let modified: Double
            if let initialModified {
                modified = initialModified
            } else {
                modified = try syncURL.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate?.timeIntervalSince1970 ?? 0
            }

            let id = Self.stableID(for: url)
            let prepared = try await Task.detached(priority: .utility) {
                try Self.prepareBundle(contentURL: url, bookURL: url, id: id, syncData: data)
            }.value
            try await Task.detached(priority: .utility) { [database] in
                try database.save(book: prepared.book, sentences: prepared.sentences)
            }.value
            importDates[url.path] = modified
            AppGroup.defaults.set(importDates, forKey: AppGroup.Key.importDates)
            lastError = nil
            onImport?()
        } catch {
            lastError = "Couldn’t open \(url.deletingPathExtension().lastPathComponent): \(error.localizedDescription)"
        }
    }

    nonisolated private static func installLocalBundle(
        from sourceURL: URL,
        in localBooksDirectory: URL
    ) throws -> PreparedBundle {
        let sourceURL = sourceURL.standardizedFileURL
        guard sourceURL.pathExtension.caseInsensitiveCompare("clipbook") == .orderedSame,
              try sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        else { throw BundleImportError.invalidFileType }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: localBooksDirectory, withIntermediateDirectories: true)
        let destinationURL = localBooksDirectory
            .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
            .standardizedFileURL
        let id = stableID(for: destinationURL)
        if sourceURL.resolvingSymlinksInPath() == destinationURL.resolvingSymlinksInPath() {
            return try prepareBundle(contentURL: sourceURL, bookURL: destinationURL, id: id)
        }

        let stagingURL = localBooksDirectory.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingURL) }
        try fileManager.copyItem(at: sourceURL, to: stagingURL)
        let prepared = try prepareBundle(contentURL: stagingURL, bookURL: destinationURL, id: id)

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }
        return prepared
    }

    nonisolated private static func prepareBundle(
        contentURL: URL,
        bookURL: URL,
        id: String,
        syncData: Data? = nil
    ) throws -> PreparedBundle {
        let syncURL = contentURL.appendingPathComponent("sync.json")
        let data: Data
        if let syncData {
            data = syncData
        } else {
            data = try Data(contentsOf: syncURL, options: .mappedIfSafe)
        }
        let sync = try JSONDecoder.clipSync.decode(ClipBookSync.self, from: data)
        try sync.validate()

        let rootPath = contentURL.standardizedFileURL.path + "/"
        let audioURLs = sync.audio.map { item in
            contentURL.appendingPathComponent(item.file).standardizedFileURL
        }
        guard !audioURLs.isEmpty,
              audioURLs.allSatisfy({ $0.path.hasPrefix(rootPath) })
        else {
            throw BundleImportError.invalidPackage
        }
        let unavailableAudio = ClipBookBundle.audioFilesRequiringDownload(audioURLs)
        guard unavailableAudio.isEmpty else {
            let isUbiquitous = (try? contentURL.resourceValues(
                forKeys: [.isUbiquitousItemKey]
            ).isUbiquitousItem) == true
            guard isUbiquitous else { throw BundleImportError.invalidPackage }

            try? FileManager.default.startDownloadingUbiquitousItem(at: contentURL)
            for audioURL in unavailableAudio {
                try? FileManager.default.startDownloadingUbiquitousItem(at: audioURL)
            }
            throw BundleImportError.audioStillDownloading
        }

        let cover = ["cover.jpg", "cover.jpeg", "cover.png"].first {
            FileManager.default.fileExists(atPath: contentURL.appendingPathComponent($0).path)
        }
        let book = BookRecord(
            id: id,
            title: sync.book.title,
            author: sync.book.author,
            bundleURL: bookURL.path,
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
        return PreparedBundle(book: book, sentences: sentences)
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

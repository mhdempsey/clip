import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable { case library, player, settings }

    @Published private(set) var books: [BookRecord] = []
    @Published var selectedTab: Tab = .library
    @Published var alertMessage: String?

    let importer: BundleImporter
    let settings: ClipSettings

    private let database: ClipDatabase
    private let player: PlayerEngine
    private var playerLoadTask: Task<Void, Never>?

    init(
        database: ClipDatabase = .shared,
        player: PlayerEngine? = nil,
        localBooksDirectory: URL = AppGroup.containerURL.appendingPathComponent("Books", isDirectory: true)
    ) {
        self.database = database
        self.player = player ?? .shared
        importer = BundleImporter(database: database, localBooksDirectory: localBooksDirectory)
        settings = ClipSettings()
        importer.onImport = { [weak self] in self?.reloadBooks() }
        reloadBooks()
#if DEBUG
        if let fixture = try? ClipUITestFixture.installIfRequested(database: database) {
            reloadBooks()
            selectedTab = .player
            let engine = self.player
            playerLoadTask = Task { await engine.load(fixture, autoplay: false) }
        }
#endif
    }

    func reloadBooks() {
        do { books = try database.books() }
        catch { alertMessage = error.localizedDescription }
        ClipService.shared.refreshPendingCount()
    }

    func open(_ book: BookRecord) {
        selectedTab = .player
        playerLoadTask?.cancel()
        playerLoadTask = Task { await player.load(book, autoplay: false) }
    }

    func importBook(from url: URL) async {
        do {
            let book = try await importer.importLocalBundle(at: url)
            reloadBooks()
            open(book)
        } catch {
            alertMessage = "Couldn’t import \(url.deletingPathExtension().lastPathComponent): \(error.localizedDescription)"
        }
    }
}

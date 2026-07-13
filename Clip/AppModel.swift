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

    init(database: ClipDatabase = .shared) {
        self.database = database
        importer = BundleImporter(database: database)
        settings = ClipSettings()
        importer.onImport = { [weak self] in self?.reloadBooks() }
        reloadBooks()
    }

    func reloadBooks() {
        do { books = try database.books() }
        catch { alertMessage = error.localizedDescription }
        ClipService.shared.refreshPendingCount()
    }

    func open(_ book: BookRecord) {
        selectedTab = .player
        Task { await PlayerEngine.shared.load(book, autoplay: false) }
    }
}

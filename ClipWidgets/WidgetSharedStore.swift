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
        static let clipCommandSequence = ClipShared.DefaultsKey.clipCommandSequence
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

    func coverImagePath(bookID: String) -> String? {
        guard let url = WidgetAppGroup.databaseURL,
              let queue = try? DatabaseQueue(path: url.path),
              let book = try? queue.read({ db in
                  try Book.fetchOne(db, sql: "SELECT id, bundleURL, coverPath FROM book WHERE id = ?", arguments: [bookID])
              }), let cover = book.coverPath else { return nil }
        return URL(fileURLWithPath: book.bundleURL).appendingPathComponent(cover).path
    }
}

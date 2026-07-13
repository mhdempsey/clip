import ClipCore
import Foundation

enum AppGroup {
    static let identifier = ClipShared.appGroupIdentifier
    static let flushTaskIdentifier = "com.michael.clip.flush"

    enum Key {
        static let currentBookID = ClipShared.DefaultsKey.currentBookID
        static let currentPosition = ClipShared.DefaultsKey.currentPosition
        static let clipWindow = ClipShared.DefaultsKey.clipWindow
        static let interruptionPosition = ClipShared.DefaultsKey.interruptionPosition
        static let interruptionDate = ClipShared.DefaultsKey.interruptionDate
        static let playbackCommand = ClipShared.DefaultsKey.playbackCommand
        static let isPlaying = ClipShared.DefaultsKey.isPlaying
        static let importDates = ClipShared.DefaultsKey.importDates
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var databaseURL: URL { containerURL.appendingPathComponent("clip.sqlite") }

    static var clipWindowSeconds: Int {
        get {
            let stored = defaults.integer(forKey: Key.clipWindow)
            return ClipShared.validatedClipWindow(stored)
        }
        set {
            defaults.set(ClipShared.validatedClipWindow(newValue), forKey: Key.clipWindow)
        }
    }
}

extension Notification.Name {
    static let clipWindowDidChange = Notification.Name("clipWindowDidChange")
    static let clipQueueDidChange = Notification.Name("clipQueueDidChange")
}

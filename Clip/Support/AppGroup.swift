import ClipCore
import CoreFoundation
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
        static let clipCommandSequence = ClipShared.DefaultsKey.clipCommandSequence
        static let handledClipCommandSequence = ClipShared.DefaultsKey.handledClipCommandSequence
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

final class DarwinNotificationObservation: @unchecked Sendable {
    private let name: CFNotificationName
    private let handler: @Sendable () -> Void

    init(name: String, handler: @escaping @Sendable () -> Void) {
        self.name = CFNotificationName(rawValue: name as CFString)
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let observation = Unmanaged<DarwinNotificationObservation>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                observation.handler()
            },
            self.name.rawValue,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            name,
            nil
        )
    }
}

extension Notification.Name {
    static let clipWindowDidChange = Notification.Name("clipWindowDidChange")
    static let clipQueueDidChange = Notification.Name("clipQueueDidChange")
}

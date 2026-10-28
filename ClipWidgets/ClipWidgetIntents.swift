import AppIntents
import ClipCore

struct ClipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clip"
    static let description = IntentDescription("Save the last few spoken seconds to Readwise.")
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = WidgetAppGroup.defaults
        defaults.synchronize()
        let snapshot = ClipPlaybackSnapshot.load(defaults: defaults)
        let target = defaults.string(forKey: WidgetAppGroup.Key.currentBookID)
        guard let target else { return .result(dialog: "Open Clip and start a book first.") }
        guard let snapshot, snapshot.bookID == target, let anchor = snapshot.anchor(), let url = WidgetAppGroup.databaseURL else {
            await ClipActivityFeedback(outcome: .unavailable).publish(for: target)
            return .result(dialog: "Open Clip and start this book, then try again.")
        }
        do {
            let database = try ClipDatabase(url: url)
            let store = ClipCaptureStore(database: database, syncStore: SyncStore(database: database))
            guard let capture = try store.capture(bookID: target, anchor: anchor, window: Double(WidgetAppGroup.windowSeconds)) else {
                await ClipActivityFeedback(outcome: .unavailable).publish(for: target)
                return .result(dialog: "No matched passage is available here.")
            }
            await ClipActivityFeedback(outcome: .saved, clipID: capture.item.id).publish(for: target)
            ClipDarwinNotifications.post(ClipShared.DarwinNotification.clipSaved)
            return .result(dialog: "Saved in Clip. Waiting to send to Readwise.")
        } catch {
            await ClipActivityFeedback(outcome: .failed).publish(for: target)
            return .result(dialog: "Couldn’t save this clip. Open Clip and try again.")
        }
    }
}

struct PlayPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult {
        let defaults = WidgetAppGroup.defaults
        let playing = defaults.bool(forKey: WidgetAppGroup.Key.isPlaying)
        defaults.set(playing ? "pause" : "play", forKey: WidgetAppGroup.Key.playbackCommand)
        defaults.synchronize()
        ClipDarwinNotifications.post(ClipShared.DarwinNotification.playbackCommand)
        return .result()
    }
}

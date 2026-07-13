import AppIntents
import ClipCore

struct ClipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clip"
    static let description = IntentDescription("Save the last few spoken seconds to Readwise.")
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = WidgetAppGroup.defaults
        guard defaults.string(forKey: WidgetAppGroup.Key.currentBookID) != nil else {
            return .result(dialog: "Nothing is playing.")
        }
        let sequence = defaults.integer(forKey: WidgetAppGroup.Key.clipCommandSequence) + 1
        defaults.set(sequence, forKey: WidgetAppGroup.Key.clipCommandSequence)
        defaults.synchronize()
        ClipDarwinNotifications.post(ClipShared.DarwinNotification.clipCommand)
        return .result(dialog: "Clipped.")
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

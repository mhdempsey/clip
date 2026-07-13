import AppIntents

struct ClipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clip"
    static let description = IntentDescription("Save the last few spoken seconds to Readwise.")
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard try WidgetClipStore().enqueueCurrentClip() else {
            return .result(dialog: "Nothing is playing.")
        }
        return .result(dialog: "Clipped. I’ll sync it later.")
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
        return .result()
    }
}

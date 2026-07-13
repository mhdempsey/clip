import AppIntents

struct PlayPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult {
        await PlayerEngine.shared.togglePlayback()
        return .result()
    }
}

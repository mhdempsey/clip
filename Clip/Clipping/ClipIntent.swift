import AppIntents

struct ClipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clip"
    static let description = IntentDescription("Save the just-heard passage to Readwise, ready for Marginalia.")
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let result = try await ClipService.shared.clipNow() else {
            return .result(dialog: "Nothing is playing.")
        }
        return .result(
            dialog: result.queuedOffline
                ? "Clipped. I’ll send it to Readwise when you’re back online."
                : "Clipped to Readwise. It’s ready for Marginalia."
        )
    }
}

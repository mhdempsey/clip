import AppIntents

struct ClipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clip"
    static let description = IntentDescription("Save the last few spoken seconds to Readwise.")
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let result = try await ClipService.shared.clipNow() else {
            return .result(dialog: "Nothing is playing.")
        }
        return .result(dialog: result.queuedOffline ? "Clipped. I’ll sync it later." : "Clipped.")
    }
}

import AppIntents
import ClipCore

struct ClipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clip"
    static let description = IntentDescription("Save the just-heard passage to Readwise, ready for Marginalia.")
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = AppGroup.defaults.string(forKey: AppGroup.Key.currentBookID)
        do {
            guard let result = try await ClipService.shared.clipNow() else {
                if let target { await ClipActivityFeedback(outcome: .unavailable).publish(for: target) }
                return .result(dialog: "No matched passage is available here. Open Clip to choose a passage.")
            }
            return .result(dialog: result.queuedOffline ? "Saved in Clip. Waiting to send to Readwise." : "Saved in Clip and sent to Readwise.")
        } catch {
            if let target { await ClipActivityFeedback(outcome: .failed).publish(for: target) }
            return .result(dialog: "Couldn’t save this clip. Open Clip and try again.")
        }
    }
}

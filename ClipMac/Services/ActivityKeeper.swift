import Foundation

@MainActor
final class ActivityKeeper {
    private var token: NSObjectProtocol?

    func begin(for title: String) {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled, .userInitiated],
            reason: "Aligning \(title)"
        )
    }

    func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}


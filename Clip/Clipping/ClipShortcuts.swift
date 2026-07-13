import AppIntents

struct ClipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClipIntent(),
            phrases: [
                "\(.applicationName) that",
                "\(.applicationName) this",
                "\(.applicationName) the last part",
                "Save that in \(.applicationName)",
                "Clip that in \(.applicationName)"
            ],
            shortTitle: "Clip",
            systemImageName: "scissors"
        )
    }
}

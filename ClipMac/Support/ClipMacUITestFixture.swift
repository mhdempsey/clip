#if DEBUG
import Foundation

enum ClipMacUITestFixture {
    private static let pairingLaunchArgument = "--ui-test-pairing-fixture"

    @MainActor
    static func installIfRequested(draft: PairingDraft) {
        guard ProcessInfo.processInfo.arguments.contains(pairingLaunchArgument) else { return }

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipMacUITestFixture", isDirectory: true)
        draft.epubURL = fixtureRoot.appendingPathComponent("The Sentence Worth Keeping.epub")
        draft.audio = [
            AudioSource(
                url: fixtureRoot.appendingPathComponent("The Sentence Worth Keeping.m4b"),
                duration: 9_184
            )
        ]
        draft.title = "The Sentence Worth Keeping"
        draft.author = "Clip Review Fixture"
        draft.metadataWasEdited = true
    }
}
#else
enum ClipMacUITestFixture {
    @MainActor
    static func installIfRequested(draft: PairingDraft) {}
}
#endif

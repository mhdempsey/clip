import AppKit
import ClipCore
import CoreText
import SwiftUI

@main
struct ClipMacApp: App {
    @NSApplicationDelegateAdaptor(ClipMacDelegate.self) private var appDelegate
    @StateObject private var model = ClipMacModel.shared

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(nil)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 780, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Book and Audio…") {
                    model.section = .align
                    model.chooseFiles()
                }
                .keyboardShortcut("o")
            }
        }

        Settings {
            QualitySettingsView(model: model)
        }
    }
}

@MainActor
final class ClipMacDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistrar.registerBundledFonts()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ClipMacModel.shared.hasRunningJob else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Keep this alignment running?"
        alert.informativeText = "Quitting now will stop the current book. Its source files won’t be changed."
        alert.addButton(withTitle: "Keep Aligning")
        alert.addButton(withTitle: "Quit Anyway")
        alert.alertStyle = .informational
        alert.window.backgroundColor = NSColor(ClipDesign.paper)
        alert.buttons.forEach { $0.contentTintColor = NSColor(ClipDesign.ink) }
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

private enum FontRegistrar {
    static func registerBundledFonts() {
        let names = [
            "EBGaramond-Regular",
            "EBGaramond-Medium",
            "EBGaramond-SemiBold",
            "EBGaramond-Italic",
            "EBGaramond-VariableFont_wght"
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}


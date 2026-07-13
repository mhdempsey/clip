import ClipCore
import SwiftUI

final class ClipAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ClipBackgroundRefresh.register()
        return true
    }
}

@main
struct ClipApp: App {
    @UIApplicationDelegateAdaptor(ClipAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var player = PlayerEngine.shared
    @StateObject private var clipService = ClipService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $model.selectedTab) {
                NavigationStack { LibraryView() }
                    .tabItem { Label("Library", systemImage: "books.vertical") }
                    .tag(AppModel.Tab.library)
                NavigationStack { PlayerView() }
                    .tabItem { Label("Listen", systemImage: "headphones") }
                    .tag(AppModel.Tab.player)
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppModel.Tab.settings)
            }
            .environmentObject(model)
            .environmentObject(model.importer)
            .environmentObject(model.settings)
            .environmentObject(player)
            .environmentObject(clipService)
            .tint(ClipDesign.ink)
            .preferredColorScheme(nil)
            .overlay(alignment: .top) {
                if let toast = clipService.toast {
                    ClipToast(message: toast)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: clipService.toast)
            .alert("Clip", isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.alertMessage = nil }
            } message: {
                Text(model.alertMessage ?? "")
            }
            .onAppear { model.importer.refresh() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model.importer.refresh()
                    model.reloadBooks()
                    Task { await clipService.flushPending() }
                case .background:
                    player.sceneDidEnterBackground()
                    ClipBackgroundRefresh.schedule()
                default:
                    break
                }
            }
        }
    }
}

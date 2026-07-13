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
            Group {
                switch model.selectedTab {
                case .library:
                    NavigationStack { LibraryView() }
                case .player:
                    NavigationStack { PlayerView() }
                case .settings:
                    NavigationStack { SettingsView() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ClipTabBar(selection: $model.selectedTab)
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
                    clipService.processExternalClipCommands()
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

private struct ClipTabBar: View {
    @Binding var selection: AppModel.Tab

    var body: some View {
        HStack(spacing: 0) {
            tab(.library, title: "Library", symbol: "books.vertical")
            tab(.player, title: "Listen", symbol: "headphones")
            tab(.settings, title: "Settings", symbol: "gearshape")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(ClipDesign.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ClipDesign.hairline)
                .frame(height: ClipDesign.hairlineWidth)
        }
    }

    private func tab(_ tab: AppModel.Tab, title: String, symbol: String) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: selected ? .semibold : .regular))
                Text(title)
                    .font(ClipDesign.semiboldFont(size: 13, relativeTo: .caption))
            }
            .foregroundStyle(selected ? ClipDesign.ink : ClipDesign.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? ClipDesign.ink.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tab.\(title.lowercased())")
    }
}

import ClipCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: ClipSettings
    @EnvironmentObject private var clipService: ClipService
    @State private var token = ""
    @State private var validationState: ValidationState = .idle
    @State private var pending: [ClipQueueRecord] = []

    private enum ValidationState: Equatable {
        case idle, checking, valid, invalid
    }

    var body: some View {
        List {
            readwiseSection
            durationSection
            pendingSection
            voiceSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(ClipDesign.paper.ignoresSafeArea())
        .foregroundStyle(ClipDesign.ink)
        .navigationTitle("Settings")
        .font(ClipTypography.body())
        .tint(ClipDesign.ink)
        .onAppear {
            token = KeychainStore.readwiseToken ?? ""
            reloadPending()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipQueueDidChange)) { _ in reloadPending() }
        .accessibilityIdentifier("settings.screen")
    }

    private var readwiseSection: some View {
        Section {
            SecureField("Readwise access token", text: $token)
                .textContentType(.password)
                .font(ClipTypography.body())
                .accessibilityIdentifier("settings.readwise-token")
            Button {
                validationState = .checking
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                KeychainStore.readwiseToken = trimmed
                Task {
                    let valid = await ReadwiseTransport().validate(token: trimmed)
                    validationState = valid ? .valid : .invalid
                    if valid { await clipService.flushPending(force: true) }
                }
            } label: {
                HStack {
                    Text("Validate")
                    Spacer()
                    switch validationState {
                    case .checking: ProgressView().tint(ClipDesign.ink)
                    case .valid: Label("Connected", systemImage: "checkmark").foregroundStyle(ClipDesign.ink)
                    case .invalid: Text("Token invalid").foregroundStyle(ClipDesign.terracotta)
                    case .idle: EmptyView()
                    }
                }
                .font(ClipTypography.semibold())
            }
            .buttonStyle(.plain)
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validationState == .checking)
            .accessibilityIdentifier("settings.validate-token")
        } header: {
            SmallCapsLabel(text: "Readwise")
        } footer: {
            Text("Your token stays in this device’s Keychain.")
                .font(ClipTypography.italic(14))
        }
        .listRowBackground(ClipDesign.surface)
    }

    private var durationSection: some View {
        Section {
            DurationStampPicker(selection: $settings.clipWindowSeconds)
                .padding(.vertical, 4)
        } header: {
            SmallCapsLabel(text: "Default clip length")
        }
        .listRowBackground(ClipDesign.surface)
    }

    @ViewBuilder
    private var pendingSection: some View {
        Section {
            if pending.isEmpty {
                Text("No clips waiting.")
                    .foregroundStyle(ClipDesign.inkSecondary)
            } else {
                ForEach(pending) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.text).lineLimit(2)
                        HStack {
                            Text(item.isFlagged ? "Needs attention" : "Attempt \(item.attempts + 1)")
                                .font(ClipTypography.italic(14))
                                .foregroundStyle(item.isFlagged ? ClipDesign.terracotta : ClipDesign.inkSecondary)
                            Spacer()
                            Button("Retry") { Task { await clipService.retry(id: item.id); reloadPending() } }
                                .buttonStyle(.plain)
                                .font(ClipTypography.semibold(14))
                            Button("Delete", role: .destructive) { clipService.delete(id: item.id) }
                                .buttonStyle(.plain)
                                .font(ClipTypography.semibold(14))
                                .foregroundStyle(ClipDesign.inkSecondary)
                        }
                        if let error = item.lastError {
                            Text(error).font(ClipTypography.body(13)).foregroundStyle(ClipDesign.inkSecondary).lineLimit(1)
                        }
                    }
                    .accessibilityIdentifier("settings.pending.\(item.id)")
                }
            }
        } header: {
            SmallCapsLabel(text: "Pending clips")
        }
        .listRowBackground(ClipDesign.surface)
    }

    private var voiceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Say “Clip that,” “Bookmark that,” “Highlight that,” or “Underline that.”")
                Text("If Siri doesn’t recognize one, make a personal Shortcut with that exact phrase and add the Clip action.")
                    .foregroundStyle(ClipDesign.inkSecondary)
            }
        } header: {
            SmallCapsLabel(text: "Voice phrases")
        }
        .listRowBackground(ClipDesign.surface)
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(version).font(ClipTypography.time(14)).foregroundStyle(ClipDesign.inkSecondary)
            }
        }
        .listRowBackground(ClipDesign.surface)
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func reloadPending() {
        pending = (try? ClipDatabase.shared.pendingClips()) ?? []
        clipService.refreshPendingCount()
    }
}

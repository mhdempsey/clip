import ClipCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: ClipMacModel
    @AppStorage("ClipMac.HasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false
    @State private var chooseFilesAfterOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(ClipDesign.hairline)
            ScrollView {
                VStack(spacing: 20) {
                    if let shelfMessage = model.shelfMessage {
                        Text(shelfMessage)
                            .font(ClipFont.italic(14))
                            .foregroundStyle(ClipDesign.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    switch model.section {
                    case .align:
                        DropPairingView(model: model)
                        ForEach(model.jobs) { job in
                            AlignmentJobView(job: job, model: model)
                        }
                    case .shelf:
                        ShelfView(model: model)
                    }
                }
                .padding(28)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ClipDesign.paper)
        .foregroundStyle(ClipDesign.ink)
        .tint(ClipDesign.accent)
        .frame(minWidth: 720, minHeight: 640)
        .onAppear {
            if !hasSeenOnboarding {
                showingOnboarding = true
            }
        }
        .sheet(isPresented: $showingOnboarding, onDismiss: {
            hasSeenOnboarding = true
            if chooseFilesAfterOnboarding {
                chooseFilesAfterOnboarding = false
                model.chooseFiles()
            }
        }) {
            ClipMacOnboardingView(
                chooseFiles: {
                    chooseFilesAfterOnboarding = true
                    showingOnboarding = false
                    model.section = .align
                },
                dismiss: {
                    showingOnboarding = false
                }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 3) {
                ClipWordmark(size: 42)
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(ClipDesign.marigold)
                        .frame(width: 24, height: 2)
                    Text("listen, read, and clip — together")
                        .font(ClipFont.italic(15))
                        .foregroundStyle(ClipDesign.inkSecondary)
                }
            }
            Spacer()
            Button {
                showingOnboarding = true
            } label: {
                Label("How it works", systemImage: "questionmark.circle")
            }
            .buttonStyle(PaperButtonStyle(role: .quiet))
            .accessibilityIdentifier("show-onboarding")
            sectionButton("Align", section: .align)
            sectionButton("Shelf", section: .shelf)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 19)
        .background(ClipDesign.paper)
    }

    private func sectionButton(_ title: String, section: MainSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { model.section = section }
        } label: {
            VStack(spacing: 5) {
                SmallCapsLabel(text: title, color: model.section == section ? ClipDesign.accent : ClipDesign.inkSecondary)
                Rectangle()
                    .fill(model.section == section ? ClipDesign.bloom : Color.clear)
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("section-\(title.lowercased())")
    }
}

private struct ClipMacOnboardingView: View {
    let chooseFiles: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                ClipWordmark(size: 48)
                Text("Listen. Say “Clip that.” Keep the passage.")
                    .font(ClipFont.medium(30))
                    .foregroundStyle(ClipDesign.ink)
                Text("Pair a DRM-free ebook with its matching audiobook on your Mac. Clip syncs them so you can listen and read together on your iPhone.")
                    .font(ClipFont.regular(18))
                    .foregroundStyle(ClipDesign.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                onboardingStep(
                    number: 1,
                    symbol: "doc.badge.plus",
                    title: "Drop or choose the pair",
                    detail: "Add one EPUB and its matching MP3, M4A, or M4B audiobook."
                )
                onboardingDivider
                onboardingStep(
                    number: 2,
                    symbol: "waveform",
                    title: "Click Align",
                    detail: "Clip listens privately on this Mac and matches the audio to the ebook’s exact words."
                )
                onboardingDivider
                onboardingStep(
                    number: 3,
                    symbol: "iphone",
                    title: "Open Clip on your iPhone",
                    detail: "Open the synced book and connect Readwise in Settings. Connect Marginalia to that same Readwise account."
                )
                onboardingDivider
                onboardingStep(
                    number: 4,
                    symbol: "scissors",
                    title: "Say “Clip that” or tap Clip",
                    detail: "Clip turns what you just heard into exact ebook text, sends it to Readwise, and makes it ready for Marginalia."
                )
            }
            .background(ClipDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClipDesign.cardRadius)
                    .stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
            }

            HStack {
                Text("One phrase. One saved passage.")
                    .font(ClipFont.handwritten(17))
                    .foregroundStyle(ClipDesign.bloom)
                    .rotationEffect(.degrees(-1))
                Spacer()
                Button("Not now", action: dismiss)
                    .buttonStyle(PaperButtonStyle(role: .quiet))
                Button("Choose ebook + audiobook", action: chooseFiles)
                    .buttonStyle(PaperButtonStyle(role: .primary))
                    .accessibilityIdentifier("onboarding-choose-files")
            }
        }
        .padding(28)
        .frame(width: 660)
        .background(ClipDesign.paper)
        .tint(ClipDesign.accent)
        .accessibilityIdentifier("mac-onboarding")
    }

    private func onboardingStep(number: Int, symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(ClipDesign.paperStrong)
                    .overlay {
                        Circle().stroke(ClipDesign.bloom, lineWidth: 1.5)
                    }
                Text("\(number)")
                    .font(ClipFont.handwritten(19))
                    .foregroundStyle(ClipDesign.bloom)
            }
            .frame(width: 36, height: 36)

            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(ClipDesign.accent)
                .frame(width: 28, height: 28)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClipFont.semibold(18))
                    .foregroundStyle(ClipDesign.ink)
                Text(detail)
                    .font(ClipFont.regular(16))
                    .foregroundStyle(ClipDesign.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var onboardingDivider: some View {
        Divider()
            .overlay(ClipDesign.hairline)
            .padding(.leading, 69)
    }
}

#Preview("Empty") {
    RootView(model: ClipMacModel())
        .frame(width: 760, height: 720)
}

import ClipCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: ClipMacModel

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
    }

    private var header: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Clip")
                    .font(ClipFont.medium(38))
                    .foregroundStyle(ClipDesign.accent)
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(ClipDesign.marigold)
                        .frame(width: 24, height: 2)
                    Text("easy highlights for audiobooks")
                        .font(ClipFont.italic(15))
                        .foregroundStyle(ClipDesign.inkSecondary)
                }
            }
            Spacer()
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

#Preview("Empty") {
    RootView(model: ClipMacModel())
        .frame(width: 760, height: 720)
}

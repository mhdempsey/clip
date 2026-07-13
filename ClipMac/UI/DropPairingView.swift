import ClipCore
import SwiftUI
import UniformTypeIdentifiers

struct DropPairingView: View {
    @ObservedObject var model: ClipMacModel
    @ObservedObject private var draft: PairingDraft
    @State private var isDropTargeted = false

    init(model: ClipMacModel) {
        self.model = model
        self.draft = model.draft
    }

    var body: some View {
        VStack(spacing: 18) {
            dropZone
            if draft.epubURL != nil || !draft.audio.isEmpty {
                pairingCard
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 13) {
            Fleuron()
            SmallCapsLabel(text: draft.pairStatus, color: isDropTargeted ? ClipDesign.terracotta : ClipDesign.ink)
                .multilineTextAlignment(.center)
            Button("Choose files…") { model.chooseFiles() }
                .buttonStyle(PaperButtonStyle(role: .secondary))
                .accessibilityIdentifier("choose-files")
            if let message = draft.inlineMessage {
                Text(message)
                    .font(ClipFont.italic(15))
                    .foregroundStyle(ClipDesign.inkSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pairing-feedback")
            }
        }
        .frame(maxWidth: .infinity, minHeight: draft.canAlign ? 130 : 210)
        .padding(24)
        .background(ClipDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClipDesign.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClipDesign.cardRadius)
                .stroke(
                    isDropTargeted ? ClipDesign.terracotta : ClipDesign.hairline,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : ClipDesign.hairlineWidth, dash: [6, 5])
                )
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: model.receiveDrop)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("book-audio-drop-zone")
    }

    private var pairingCard: some View {
        HStack(alignment: .top, spacing: 24) {
            StampCover(data: draft.coverData, caption: draft.title.isEmpty ? "Your book" : draft.title)
                .accessibilityIdentifier("pairing-cover")

            VStack(alignment: .leading, spacing: 14) {
                SmallCapsLabel(text: "Book details")
                TextField("Title", text: binding(\.title))
                    .textFieldStyle(PaperTextFieldStyle())
                    .accessibilityLabel("Book title")
                    .accessibilityIdentifier("book-title")
                TextField("Author", text: binding(\.author))
                    .textFieldStyle(PaperTextFieldStyle())
                    .accessibilityLabel("Book author")
                    .accessibilityIdentifier("book-author")

                if let epub = draft.epubURL {
                    fileLine(icon: "book.closed", name: epub.lastPathComponent)
                }

                if !draft.audio.isEmpty {
                    HStack {
                        SmallCapsLabel(text: "Audio order")
                        Spacer()
                        Text("Drag to correct")
                            .font(ClipFont.italic(13))
                            .foregroundStyle(ClipDesign.inkSecondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(draft.audio.enumerated()), id: \.element.id) { index, source in
                            audioLine(source, number: index + 1)
                                .onDrag {
                                    NSItemProvider(object: source.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: AudioReorderDropDelegate(targetID: source.id, move: model.moveAudio))
                            if index < draft.audio.count - 1 {
                                Divider().overlay(ClipDesign.hairline)
                            }
                        }
                    }
                    .background(ClipDesign.paper.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: ClipDesign.controlRadius)
                            .stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
                    }
                    .accessibilityIdentifier("audio-order")
                }

                HStack {
                    if draft.isReadingMetadata {
                        Text("Reading the cover…")
                            .font(ClipFont.italic(14))
                            .foregroundStyle(ClipDesign.inkSecondary)
                    }
                    Spacer()
                    Button("Align") { model.enqueueAlignment() }
                        .buttonStyle(PaperButtonStyle(role: .primary))
                        .disabled(!draft.canAlign)
                        .opacity(draft.canAlign ? 1 : 0.45)
                        .accessibilityIdentifier("align-book")
                }
            }
        }
        .clipCard()
        .accessibilityIdentifier("pairing-card")
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<PairingDraft, String>) -> Binding<String> {
        Binding {
            draft[keyPath: keyPath]
        } set: { value in
            draft[keyPath: keyPath] = value
            draft.metadataWasEdited = true
        }
    }

    private func fileLine(icon: String, name: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(ClipDesign.inkSecondary)
            Text(name)
                .font(ClipFont.regular(15))
                .foregroundStyle(ClipDesign.ink)
                .lineLimit(1)
        }
    }

    private func audioLine(_ source: AudioSource, number: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ClipDesign.inkSecondary)
                .frame(width: 22)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(ClipDesign.inkSecondary)
            Text(source.url.lastPathComponent)
                .font(ClipFont.regular(15))
                .foregroundStyle(ClipDesign.ink)
                .lineLimit(1)
            Spacer()
            if let duration = source.duration {
                Text(ClipFormatting.duration.string(from: duration) ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ClipDesign.inkSecondary)
            }
            Button {
                model.removeAudio(source)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(ClipDesign.inkSecondary)
            }
            .buttonStyle(PaperButtonStyle(role: .quiet))
            .accessibilityLabel("Remove \(source.url.lastPathComponent)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}


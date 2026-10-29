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
        .disabled(model.isPreparingCloud)
        .sheet(item: $model.cloudConfirmation) { request in
            CloudAlignmentConfirmationView(model: model, request: request)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Fleuron()
            Text("Drop an ebook and its matching audiobook.")
                .font(ClipFont.medium(25))
                .foregroundStyle(ClipDesign.ink)
                .multilineTextAlignment(.center)
            Text("Clip syncs them for listening and reading on your iPhone. Then say “Clip that” or tap Clip to send the passage to Readwise, ready for Marginalia.")
                .font(ClipFont.regular(17))
                .foregroundStyle(ClipDesign.inkSecondary)
                .multilineTextAlignment(.center)
            SmallCapsLabel(text: draft.pairStatus, color: isDropTargeted ? ClipDesign.terracotta : ClipDesign.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Button("Choose files…") { model.chooseFiles() }
                .buttonStyle(PaperButtonStyle(role: .secondary))
                .accessibilityIdentifier("choose-files")
            Text("EPUB + MP3, M4A, or M4B")
                .font(ClipFont.handwritten(15))
                .foregroundStyle(ClipDesign.bloom)
                .rotationEffect(.degrees(-1))
            if let message = draft.inlineMessage {
                Text(message)
                    .font(ClipFont.italic(15))
                    .foregroundStyle(ClipDesign.inkSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pairing-feedback")
            }
        }
        .frame(maxWidth: .infinity, minHeight: draft.canAlign ? 180 : 270)
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
                    Picker("Transcription", selection: $model.alignmentLocation) {
                        ForEach(AlignmentLocation.allCases) { location in
                            Text(location.title).tag(location)
                        }
                    }
                    .fixedSize()
                    .accessibilityIdentifier("pairing-alignment-location")
                    SettingsLink { Text("Settings…") }
                        .buttonStyle(PaperButtonStyle(role: .quiet))
                        .accessibilityIdentifier("pairing-settings")
                    Spacer()
                }

                HStack {
                    if draft.isReadingMetadata {
                        Text("Reading the cover…")
                            .font(ClipFont.italic(14))
                            .foregroundStyle(ClipDesign.inkSecondary)
                    }
                    Spacer()
                    Button(model.isPreparingCloud ? "Checking audio…" : (model.alignmentLocation == .openRouter ? "Review cloud alignment…" : "Align")) { model.enqueueAlignment() }
                        .buttonStyle(PaperButtonStyle(role: .primary))
                        .disabled(!draft.canAlign || model.isPreparingCloud)
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

private struct CloudAlignmentConfirmationView: View {
    @ObservedObject var model: ClipMacModel
    let request: CloudAlignmentRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Align with OpenRouter")
                .font(ClipFont.medium(28))
            Text(request.source.title)
                .font(ClipFont.semibold(19))
            Text("Estimated transcription: \(request.estimatedCost)")
                .font(ClipFont.medium(22))
                .accessibilityIdentifier("cloud-cost-estimate")
            Text("Before cache savings, based on published provider rates. OpenRouter chooses the provider; actual cost and speed vary.")
                .font(ClipFont.regular(15))
            Text("Your audiobook audio will be sent to OpenRouter’s transcription providers. The EPUB and matching stay on this Mac. Charges use your existing OpenRouter credits.")
                .font(ClipFont.regular(16))
            Text("Spending limit this run: \(request.spendingLimitUSD.formatted(.currency(code: "USD"))). Clip checks between upload batches; a final batch can put the total slightly over. Completed chunks are saved for retries.")
                .font(ClipFont.italic(14))
                .foregroundStyle(ClipDesign.inkSecondary)
            HStack {
                Spacer()
                Button("Cancel") { model.cloudConfirmation = nil }
                    .buttonStyle(PaperButtonStyle(role: .quiet))
                    .keyboardShortcut(.cancelAction)
                Button("Upload audio and align") { model.confirmCloudAlignment() }
                    .buttonStyle(PaperButtonStyle(role: .primary))
                    .accessibilityIdentifier("confirm-cloud-alignment")
            }
        }
        .foregroundStyle(ClipDesign.ink)
        .padding(28)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .background(ClipDesign.paper)
    }
}

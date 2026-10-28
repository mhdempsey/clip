import SwiftUI

struct BookClipsList: View {
    let bookID: String
    var onSelect: ((ClipQueueRecord) -> Void)? = nil
    @State private var clips: [ClipQueueRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView("Couldn’t load clips", systemImage: "exclamationmark.circle", description: Text(errorMessage))
            } else if clips.isEmpty {
                ContentUnavailableView("No clips yet", systemImage: "highlighter", description: Text("Use Clip while listening, or select text and choose Highlight. Saved clips stay here, including after they sync to Readwise."))
            } else {
                List(clips) { clip in
                    Group {
                        if let onSelect {
                            Button { onSelect(clip) } label: { row(clip) }
                                .buttonStyle(.plain)
                        } else { row(clip) }
                    }
                    .accessibilityIdentifier("book.clip.\(clip.id)")
                }
            }
        }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .clipQueueDidChange)) { _ in reload() }
        .accessibilityIdentifier("book.clips")
    }

    private func row(_ clip: ClipQueueRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(clip.text).font(.body).foregroundStyle(.primary)
            HStack(alignment: .firstTextBaseline) {
                Label(clip.sentAt != nil ? "Sent to Readwise" : clip.isFlagged ? "Saved · sync needs attention" : "Saved · waiting for Readwise", systemImage: clip.sentAt != nil ? "checkmark.circle" : "checkmark")
                Spacer(minLength: 4)
                Text(clip.createdAt, format: .dateTime.month(.abbreviated).day())
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func reload() {
        do { clips = try ClipDatabase.shared.clips(bookID: bookID); errorMessage = nil }
        catch { errorMessage = "Try opening this book’s clips again." }
    }
}

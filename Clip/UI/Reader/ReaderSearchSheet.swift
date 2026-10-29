import SwiftUI

struct ReaderSearchSheet: View {
    let document: ReaderDocument
    @Binding var query: String
    var onSelect: (ReaderDocument.SearchMatch) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var matches: [ReaderDocument.SearchMatch] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Group {
                if searching {
                    ProgressView("Searching this book…")
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Find a passage", systemImage: "magnifyingglass", description: Text("Search for a word or phrase. Browsing results keeps your audio where it is."))
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        Section("\(matches.count) \(matches.count == 1 ? "match" : "matches")") {
                            ForEach(matches) { match in
                                Button { onSelect(match) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(match.snippet).foregroundStyle(.primary)
                                        if let chapter = match.chapterTitle {
                                            Text(chapter).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                .accessibilityIdentifier("reader.search.result.\(match.id)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search this book")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Word or phrase")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: query) {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { matches = []; searching = false; return }
            searching = true
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) { document.search(term) }.value
            guard !Task.isCancelled else { return }
            matches = result
            searching = false
        }
        .accessibilityIdentifier("reader.search.screen")
    }
}

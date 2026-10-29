import ClipCore
import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, added, title, author, progress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Recently opened"
        case .added: "Recently added"
        case .title: "Title"
        case .author: "Author"
        case .progress: "Progress"
        }
    }

    func sorted(_ books: [BookRecord]) -> [BookRecord] {
        books.sorted { left, right in
            switch self {
            case .recent:
                let a = left.lastPlayedAt ?? left.addedAt, b = right.lastPlayedAt ?? right.addedAt
                if a != b { return a > b }
            case .added:
                if left.addedAt != right.addedAt { return left.addedAt > right.addedAt }
            case .author:
                let order = left.author.localizedStandardCompare(right.author)
                if order != .orderedSame { return order == .orderedAscending }
            case .progress:
                if left.progress != right.progress { return left.progress > right.progress }
            case .title: break
            }
            let order = left.title.localizedStandardCompare(right.title)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case reading, read, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reading: "Reading"
        case .read: "Read"
        case .all: "All"
        }
    }
    func includes(_ book: BookRecord) -> Bool {
        switch self {
        case .reading: !book.isRead
        case .read: book.isRead
        case .all: true
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var importer: BundleImporter
    @AppStorage("Clip.Library.Sort") private var sort: LibrarySort = .recent
    @AppStorage("Clip.Library.Filter") private var filter: LibraryFilter = .reading
    @AppStorage("Clip.Library.ListView") private var listView = true
    @State private var clipsBook: BookRecord?

    private let columns = [GridItem(.adaptive(minimum: 138), spacing: 22)]
    private var visibleBooks: [BookRecord] { sort.sorted(model.books.filter(filter.includes)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    ClipScreenTitle("Library")
                    Spacer()
                    Menu {
                        Picker("Sort books", selection: $sort) {
                            ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down").font(.subheadline).frame(minHeight: 44)
                    }
                    .accessibilityLabel("Sort books: \(sort.title)")
                    .accessibilityIdentifier("library.sort")
                    Menu {
                        Picker("Library view", selection: $listView) {
                            Label("Compact list", systemImage: "list.bullet").tag(true)
                            Label("Cover grid", systemImage: "square.grid.2x2").tag(false)
                        }
                    } label: {
                        Image(systemName: listView ? "list.bullet" : "square.grid.2x2").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Library view: \(listView ? "Compact list" : "Cover grid")")
                    .accessibilityIdentifier("library.layout")
                }
                .padding(.top, 12)
                .foregroundStyle(ClipDesign.ink)
                if !importer.iCloudAvailable {
                    statusLine("iCloud Drive is off. AirDrop or open a .clipbook from Files, or sign in to sync books from your Mac.")
                }
                if let error = importer.lastError {
                    statusLine(error)
                }
                if model.books.isEmpty && importer.downloads.isEmpty {
                    emptyState
                } else {
                    Picker("Books", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("library.filter")
                    if !importer.downloads.isEmpty { downloadSection }
                    if visibleBooks.isEmpty { filteredEmptyState }
                    else if listView { compactList }
                    else { coverGrid }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(ClipDesign.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            importer.refresh()
            model.reloadBooks()
        }
        .accessibilityIdentifier("library.screen")
        .onAppear { model.reloadBooks() }
        .onChange(of: model.selectedTab) { _, tab in if tab == .library { model.reloadBooks() } }
        .sheet(item: $clipsBook) { book in
            NavigationStack {
                BookClipsList(bookID: book.id)
                    .navigationTitle("Clips & highlights")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .top) { Text(book.title).font(.subheadline).foregroundStyle(.secondary).padding() }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { clipsBook = nil } } }
            }
        }
    }

    private var compactList: some View {
        LazyVStack(spacing: 0) {
            ForEach(visibleBooks) { book in
                HStack(spacing: 10) {
                    Button { model.open(book) } label: {
                        HStack(spacing: 12) {
                            StampCover(book: book, width: 34, caption: false)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                    .foregroundStyle(ClipDesign.ink)
                                Text(book.author).font(.caption).lineLimit(1).foregroundStyle(ClipDesign.inkSecondary)
                                Text(book.isRead ? "Read" : book.progress > 0 ? "\(Int(book.progress * 100))% · \(remainingTime(book)) left" : remainingTime(book))
                                    .font(.caption2).foregroundStyle(ClipDesign.inkSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.book.\(book.id)")
                    .contextMenu { bookActions(book) }
                    Menu { bookActions(book) } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                            .foregroundStyle(ClipDesign.inkSecondary)
                    }
                    .accessibilityLabel("Actions for \(book.title)")
                    .accessibilityIdentifier("library.actions.\(book.id)")
                }
                .padding(.vertical, 10)
                Divider().overlay(ClipDesign.hairline)
            }
        }
    }

    private var coverGrid: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 28) {
            ForEach(visibleBooks) { book in
                Button { model.open(book) } label: { StampCover(book: book) }
                    .buttonStyle(.plain)
                    .contextMenu { bookActions(book) }
                    .accessibilityIdentifier("library.book.\(book.id)")
            }
        }
    }

    @ViewBuilder private func bookActions(_ book: BookRecord) -> some View {
        Button("Clips & highlights", systemImage: "highlighter") { clipsBook = book }
        Button(book.isRead ? "Move to Reading" : "Mark as Read", systemImage: book.isRead ? "book" : "checkmark.circle") {
            model.setRead(book, isRead: !book.isRead)
        }
        Button("Delete local copy", systemImage: "icloud.and.arrow.up") { importer.deleteLocalCopy(of: book) }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Text(filter == .read ? "No finished books yet" : "No books here")
                .font(ClipTypography.title(24)).foregroundStyle(ClipDesign.ink)
            Text(filter == .read ? "Mark a book as Read from its menu. You can move it back to Reading anytime." : "Your finished books are in Read.")
                .font(.subheadline).foregroundStyle(ClipDesign.inkSecondary).multilineTextAlignment(.center)
            Button("Show all books") { filter = .all }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    private func remainingTime(_ book: BookRecord) -> String {
        let minutes = max(0, Int((book.durationS - book.positionS) / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Text("❦")
                .font(ClipTypography.title(36))
                .foregroundStyle(ClipDesign.inkSecondary)
            Text("Bring a book from your Mac")
                .font(ClipTypography.title(28))
                .foregroundStyle(ClipDesign.ink)
            Text("On your Mac, drop a DRM-free EPUB and its matching audiobook into Clip. The finished book syncs here for listening and reading together.")
                .font(ClipTypography.body(18))
                .foregroundStyle(ClipDesign.inkSecondary)
                .multilineTextAlignment(.center)
            Text("While it plays, say “Clip that” or tap Clip to send the matched passage to Readwise, ready for Marginalia.")
                .font(ClipTypography.italic(16))
                .foregroundStyle(ClipDesign.ink)
                .multilineTextAlignment(.center)
            Text("No iCloud? AirDrop a .clipbook or open one from Files.")
                .font(ClipTypography.italic(15))
                .foregroundStyle(ClipDesign.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .accessibilityIdentifier("library.empty")
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SmallCapsLabel(text: "Arriving from iCloud")
            ForEach(importer.downloads) { download in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(download.title).font(ClipTypography.body())
                        Spacer()
                        Text(download.progress, format: .percent.precision(.fractionLength(0)))
                            .font(ClipTypography.time(12))
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ClipDesign.ink.opacity(0.2)).frame(height: 2)
                            Capsule().fill(ClipDesign.terracotta)
                                .frame(width: geometry.size.width * download.progress, height: 2)
                        }
                    }
                    .frame(height: 2)
                }
                .foregroundStyle(ClipDesign.ink)
                .padding(.vertical, 5)
            }
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(ClipTypography.body())
            .foregroundStyle(ClipDesign.inkSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: ClipDesign.cardRadius)
                    .stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
            }
    }
}

import ClipCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var importer: BundleImporter

    private let columns = [GridItem(.adaptive(minimum: 138), spacing: 22)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !importer.iCloudAvailable {
                    statusLine("iCloud Drive is off. Sign in to iCloud to see books aligned on your Mac.")
                }
                if let error = importer.lastError {
                    statusLine(error)
                }
                if model.books.isEmpty && importer.downloads.isEmpty {
                    emptyState
                } else {
                    if !importer.downloads.isEmpty { downloadSection }
                    LazyVGrid(columns: columns, alignment: .center, spacing: 28) {
                        ForEach(model.books) { book in
                            Button { model.open(book) } label: {
                                StampCover(book: book)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete local copy", systemImage: "icloud.and.arrow.up") {
                                    importer.deleteLocalCopy(of: book)
                                }
                            }
                            .accessibilityIdentifier("library.book.\(book.id)")
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(ClipDesign.paper.ignoresSafeArea())
        .navigationTitle("Library")
        .refreshable {
            importer.refresh()
            model.reloadBooks()
        }
        .accessibilityIdentifier("library.screen")
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Text("❦")
                .font(ClipTypography.title(36))
                .foregroundStyle(ClipDesign.inkSecondary)
            Text("The shelf is empty")
                .font(ClipTypography.title(28))
                .foregroundStyle(ClipDesign.ink)
            Text("Align a book on your Mac and it will appear here.")
                .font(ClipTypography.body(18))
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

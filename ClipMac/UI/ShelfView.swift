import ClipCore
import SwiftUI

struct ShelfView: View {
    @ObservedObject var model: ClipMacModel
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 28)]

    var body: some View {
        Group {
            if model.shelf.isEmpty {
                emptyShelf
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(model.shelf) { book in
                        shelfBook(book)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await model.refreshShelf() }
        .accessibilityIdentifier("finished-books-shelf")
    }

    private var emptyShelf: some View {
        VStack(spacing: 14) {
            Fleuron()
            Text("The shelf is empty")
                .font(ClipFont.medium(25))
                .foregroundStyle(ClipDesign.ink)
            Text("Drop a book and its audiobook on the Align page. Finished books will gather here.")
                .font(ClipFont.regular(17))
                .foregroundStyle(ClipDesign.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            Button("Align a book") { model.section = .align }
                .buttonStyle(PaperButtonStyle(role: .secondary))
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func shelfBook(_ book: ShelfBook) -> some View {
        VStack(alignment: .center, spacing: 8) {
            StampCover(url: book.coverURL, caption: book.title, width: 132)
            Text(book.author)
                .font(ClipFont.regular(15))
                .foregroundStyle(ClipDesign.inkSecondary)
                .lineLimit(1)
            Text("\(ClipFormatting.coverage(book.coverage)) aligned")
                .font(ClipFont.italic(13))
                .foregroundStyle(ClipDesign.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Re-align…") { model.realign(book) }
            Button("Reveal in Finder") { model.reveal(book.bundleURL) }
            Divider()
            Button("Remove") { model.remove(book) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title) by \(book.author), \(ClipFormatting.coverage(book.coverage)) aligned")
        .accessibilityIdentifier("shelf-book-\(book.id)")
    }
}


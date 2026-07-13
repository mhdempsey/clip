import ClipCore
import Foundation

struct EPUBPreview {
    let title: String?
    let author: String?
    let coverData: Data?
}

enum EPUBPreviewService {
    static func read(_ url: URL) throws -> EPUBPreview {
        let book = try EPUBReader.read(from: url)
        return EPUBPreview(
            title: book.metadata.title,
            author: book.metadata.author,
            coverData: book.coverData
        )
    }
}

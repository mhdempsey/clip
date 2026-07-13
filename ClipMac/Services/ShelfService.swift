import AppKit
import Foundation

private struct ShelfSyncEnvelope: Decodable {
    struct Book: Decodable {
        struct Aligner: Decodable { let coverage: Double }
        let title: String
        let author: String
        let durationS: Double
        let aligner: Aligner

        enum CodingKeys: String, CodingKey {
            case title, author, aligner
            case durationS = "duration_s"
        }
    }

    let book: Book
}

actor ShelfService {
    func load() throws -> [ShelfBook] {
        let destination = try DestinationService.destination()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: destination.documentsURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { bundleURL in
            guard bundleURL.pathExtension.lowercased() == "clipbook" else { return nil }
            let syncURL = bundleURL.appendingPathComponent("sync.json")
            guard let data = try? Data(contentsOf: syncURL),
                  let envelope = try? JSONDecoder().decode(ShelfSyncEnvelope.self, from: data) else {
                return nil
            }
            let values = try? bundleURL.resourceValues(forKeys: keys)
            let cover = bundleURL.appendingPathComponent("cover.jpg")
            return ShelfBook(
                id: bundleURL.path,
                title: envelope.book.title,
                author: envelope.book.author,
                duration: envelope.book.durationS,
                coverage: envelope.book.aligner.coverage,
                bundleURL: bundleURL,
                coverURL: FileManager.default.fileExists(atPath: cover.path) ? cover : nil,
                modifiedAt: values?.contentModificationDate
            )
        }.sorted {
            ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
        }
    }

    func remove(_ book: ShelfBook) throws {
        var coordinatorError: NSError?
        var removalError: Error?
        NSFileCoordinator().coordinate(writingItemAt: book.bundleURL, options: .forDeleting, error: &coordinatorError) { url in
            do { try FileManager.default.removeItem(at: url) }
            catch { removalError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let removalError { throw removalError }
    }

    @MainActor
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}


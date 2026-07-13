import AVFoundation
import Foundation

struct AudioMetadata {
    let duration: TimeInterval
    let title: String?
    let author: String?
    let artwork: Data?
    let embeddedChapterCount: Int
}

enum AudioMetadataService {
    static func read(_ url: URL) async throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        let time = try await asset.load(.duration)
        let seconds = time.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw MacAppError.unreadableAudio(url.lastPathComponent)
        }

        let metadata = try await asset.load(.commonMetadata)
        var title: String?
        var author: String?
        var artwork: Data?

        for item in metadata {
            switch item.commonKey {
            case .commonKeyTitle:
                title = try? await item.load(.stringValue)
            case .commonKeyArtist, .commonKeyAuthor:
                if author == nil { author = try? await item.load(.stringValue) }
            case .commonKeyArtwork:
                artwork = try? await item.load(.dataValue)
            default:
                break
            }
        }

        // M4B chapter atoms are useful as a sanity signal, but EPUB chapters remain authoritative.
        let chapterGroups = try? await asset.loadChapterMetadataGroups(
            withTitleLocale: .current,
            containingItemsWithCommonKeys: [.commonKeyTitle]
        )

        return AudioMetadata(
            duration: seconds,
            title: title,
            author: author,
            artwork: artwork,
            embeddedChapterCount: chapterGroups?.count ?? 0
        )
    }
}

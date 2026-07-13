import MediaPlayer
import UIKit

@MainActor
final class NowPlaying {
    static let shared = NowPlaying()
    private var installed = false
    private var artworkBookID: String?
    private var artwork: MPMediaItemArtwork?

    func installCommands(for engine: PlayerEngine) {
        guard !installed else { return }
        installed = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak engine] _ in
            Task { @MainActor in engine?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak engine] _ in
            Task { @MainActor in engine?.pause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak engine] _ in
            Task { @MainActor in engine?.skip(by: 15) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak engine] _ in
            Task { @MainActor in engine?.skip(by: -15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak engine] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in engine?.seek(to: event.positionTime) }
            return .success
        }
    }

    func update(book: BookRecord?, elapsed: Double, isPlaying: Bool) {
        guard let book else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            artworkBookID = nil
            artwork = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: book.title,
            MPMediaItemPropertyArtist: book.author,
            MPMediaItemPropertyPlaybackDuration: book.durationS,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if artworkBookID != book.id {
            artworkBookID = book.id
            if let coverURL = book.coverURL, let image = UIImage(contentsOfFile: coverURL.path) {
                artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            } else {
                artwork = nil
            }
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

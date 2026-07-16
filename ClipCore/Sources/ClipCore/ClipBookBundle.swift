import Foundation

public enum ClipBookBundle {
    public static func audioFilesRequiringDownload(in sync: ClipBookSync, at bundleURL: URL) -> [URL] {
        audioFilesRequiringDownload(audioFileURLs(in: sync, at: bundleURL))
    }

    public static func audioFilesRequiringDownload(_ urls: [URL]) -> [URL] {
        urls.filter { !isAudioFileReady($0) }
    }

    public static func isAudioFileReady(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
                  .isRegularFileKey,
                  .isReadableKey,
                  .isUbiquitousItemKey,
                  .ubiquitousItemDownloadingStatusKey,
              ]),
              values.isRegularFile == true,
              values.isReadable == true
        else { return false }

        if values.isUbiquitousItem == true {
            return values.ubiquitousItemDownloadingStatus == .current
        }
        return true
    }

    private static func audioFileURLs(in sync: ClipBookSync, at bundleURL: URL) -> [URL] {
        sync.audio.map { bundleURL.appendingPathComponent($0.file).standardizedFileURL }
    }
}

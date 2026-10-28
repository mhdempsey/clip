import Foundation

public enum ClipBookBundle {
    public static func resourceURL(_ path: String, in bundleURL: URL) throws -> URL {
        guard bundleURL.isFileURL, !path.isEmpty, !(path as NSString).isAbsolutePath, !path.contains("\0") else {
            throw ClipBookResourceError.unsafePath
        }
        let root = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        var resource = root
        for component in path.split(separator: "/") {
            resource = resource.appendingPathComponent(String(component)).standardizedFileURL
            guard resource.path == root.path || resource.path.hasPrefix(root.path + "/"),
                  (try? FileManager.default.destinationOfSymbolicLink(atPath: resource.path)) == nil else {
                throw ClipBookResourceError.unsafePath
            }
        }
        guard resource.path.hasPrefix(root.path + "/") else { throw ClipBookResourceError.unsafePath }
        return resource
    }

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

public enum ClipBookResourceError: Error, LocalizedError {
    case unsafePath

    public var errorDescription: String? { "This Clip book contains a file outside its package." }
}

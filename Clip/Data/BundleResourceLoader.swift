import Foundation

enum BundleResourceLoaderError: LocalizedError {
    case downloadTimedOut(String)

    var errorDescription: String? {
        switch self {
        case let .downloadTimedOut(filename):
            "Clip couldn’t finish downloading \(filename) from iCloud. Keep Clip open and try again."
        }
    }
}

struct BundleResourceLoader {
    private let fileManager: FileManager
    private let pollInterval: Duration
    private let cloudRetryCount: Int

    init(
        fileManager: FileManager = .default,
        pollInterval: Duration = .milliseconds(250),
        cloudRetryCount: Int = 240
    ) {
        self.fileManager = fileManager
        self.pollInterval = pollInterval
        self.cloudRetryCount = cloudRetryCount
    }

    func data(
        at resourceURL: URL,
        in bundleURL: URL,
        onWaiting: (() -> Void)? = nil
    ) async throws -> Data {
        do {
            return try Data(contentsOf: resourceURL, options: .mappedIfSafe)
        } catch {
            let isUbiquitous = fileManager.isUbiquitousItem(at: bundleURL)
                || fileManager.isUbiquitousItem(at: resourceURL)
            guard isUbiquitous else { throw error }

            onWaiting?()
            do {
                try fileManager.startDownloadingUbiquitousItem(at: bundleURL)
            } catch {
                try fileManager.startDownloadingUbiquitousItem(at: resourceURL)
            }
            if resourceURL.standardizedFileURL != bundleURL.standardizedFileURL {
                try? fileManager.startDownloadingUbiquitousItem(at: resourceURL)
            }

            for _ in 0..<cloudRetryCount {
                try Task.checkCancellation()
                try await Task.sleep(for: pollInterval)
                if let data = try? Data(contentsOf: resourceURL, options: .mappedIfSafe) {
                    return data
                }
            }

            throw BundleResourceLoaderError.downloadTimedOut(resourceURL.lastPathComponent)
        }
    }
}

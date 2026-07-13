#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

public struct ClipActivityAttributes: ActivityAttributes, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var elapsedS: Double
        public var durationS: Double
        public var isPlaying: Bool
        public var windowSeconds: Int

        public init(elapsedS: Double, durationS: Double, isPlaying: Bool, windowSeconds: Int) {
            self.elapsedS = elapsedS
            self.durationS = durationS
            self.isPlaying = isPlaying
            self.windowSeconds = windowSeconds
        }
    }

    public var bookId: String
    public var title: String
    public var author: String

    public init(bookId: String, title: String, author: String) {
        self.bookId = bookId
        self.title = title
        self.author = author
    }
}
#endif

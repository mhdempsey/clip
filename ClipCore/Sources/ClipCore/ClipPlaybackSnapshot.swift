import Foundation

public struct ClipPlaybackSnapshot: Codable, Sendable {
    public let bookID: String
    public let position: Double
    public let duration: Double
    public let rate: Double
    public let isPlaying: Bool
    public let date: Date

    public init(bookID: String, position: Double, duration: Double, rate: Double, isPlaying: Bool, date: Date = Date()) {
        self.bookID = bookID
        self.position = position
        self.duration = duration
        self.rate = rate
        self.isPlaying = isPlaying
        self.date = date
    }

    public func anchor(at now: Date = Date()) -> Double? {
        guard position.isFinite, duration.isFinite, rate.isFinite, duration >= 0 else { return nil }
        let elapsed = max(0, now.timeIntervalSince(date))
        guard !isPlaying || elapsed <= 15 else { return nil }
        return min(duration, max(0, position + (isPlaying ? elapsed * rate : 0)))
    }

    public func store(defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: ClipShared.DefaultsKey.playbackSnapshot) }
    }

    public static func load(defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: ClipShared.DefaultsKey.playbackSnapshot) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

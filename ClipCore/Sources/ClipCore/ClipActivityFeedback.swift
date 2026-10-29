import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

public struct ClipActivityFeedback: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Sendable { case saved, unavailable, failed }
    public let outcome: Outcome
    public let date: Date
    public let clipID: String?

    public init(outcome: Outcome, date: Date = Date(), clipID: String? = nil) {
        self.outcome = outcome
        self.date = date
        self.clipID = clipID
    }

    public var message: String {
        switch outcome {
        case .saved: "Clip saved"
        case .unavailable: "No passage to clip"
        case .failed: "Couldn’t save clip"
        }
    }

    private struct Stored: Codable { let bookID: String; let feedback: ClipActivityFeedback }
    private static let key = "lastClipFeedback"

    public func store(for bookID: String, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(Stored(bookID: bookID, feedback: self)) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public static func stored(for bookID: String, defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(Stored.self, from: data), value.bookID == bookID else { return nil }
        return value.feedback
    }

#if canImport(ActivityKit) && os(iOS)
    @MainActor public func publish(for bookID: String) async {
        let defaults = UserDefaults(suiteName: ClipShared.appGroupIdentifier) ?? .standard
        store(for: bookID, defaults: defaults)
        defaults.synchronize()
        for activity in Activity<ClipActivityAttributes>.activities where activity.attributes.bookId == bookID {
            var state = activity.content.state
            state.clipFeedback = self
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(45)))
        }
    }
#endif
}

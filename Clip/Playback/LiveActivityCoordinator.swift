import ActivityKit
import ClipCore
import Foundation

@MainActor
final class LiveActivityCoordinator {
    private var activity: Activity<ClipActivityAttributes>?
    private var lastElapsedUpdate: Double = -.infinity

    func update(book: BookRecord, elapsed: Double, isPlaying: Bool, force: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity, activity.attributes.bookId != book.id {
            self.activity = nil
            Task { await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate) }
        }
        if let activity, activity.activityState != .active && activity.activityState != .stale {
            self.activity = nil
        }
        if activity == nil {
            for candidate in Activity<ClipActivityAttributes>.activities {
                if candidate.attributes.bookId == book.id,
                   candidate.activityState == .active || candidate.activityState == .stale,
                   activity == nil {
                    activity = candidate
                } else {
                    Task { await candidate.end(ActivityContent(state: candidate.content.state, staleDate: nil), dismissalPolicy: .immediate) }
                }
            }
            lastElapsedUpdate = -.infinity
        }
        let state = ClipActivityAttributes.ContentState(
            elapsedS: elapsed,
            durationS: book.durationS,
            isPlaying: isPlaying,
            windowSeconds: AppGroup.clipWindowSeconds,
            clipFeedback: ClipActivityFeedback.stored(for: book.id, defaults: AppGroup.defaults)
        )
        if let activity {
            guard force || abs(elapsed - lastElapsedUpdate) >= 30 else { return }
            lastElapsedUpdate = elapsed
            Task {
                var currentState = state
                currentState.clipFeedback = ClipActivityFeedback.stored(for: book.id, defaults: AppGroup.defaults)
                await activity.update(ActivityContent(state: currentState, staleDate: Date().addingTimeInterval(45)))
            }
        } else if isPlaying {
            do {
                let attributes = ClipActivityAttributes(bookId: book.id, title: book.title, author: book.author)
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(45)),
                    pushType: nil
                )
                lastElapsedUpdate = elapsed
            } catch {
                // Playback must remain unaffected when Live Activities are denied.
            }
        }
    }

    func end(elapsed: Double, duration: Double) {
        guard let activity else { return }
        self.activity = nil
        let finalState = ClipActivityAttributes.ContentState(
            elapsedS: elapsed,
            durationS: duration,
            isPlaying: false,
            windowSeconds: AppGroup.clipWindowSeconds,
            clipFeedback: ClipActivityFeedback.stored(for: activity.attributes.bookId, defaults: AppGroup.defaults)
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
        }
    }
}

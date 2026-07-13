import ActivityKit
import ClipCore
import Foundation

@MainActor
final class LiveActivityCoordinator {
    private var activity: Activity<ClipActivityAttributes>?
    private var lastElapsedUpdate: Double = -.infinity

    func update(book: BookRecord, elapsed: Double, isPlaying: Bool, force: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = ClipActivityAttributes.ContentState(
            elapsedS: elapsed,
            durationS: book.durationS,
            isPlaying: isPlaying,
            windowSeconds: AppGroup.clipWindowSeconds
        )
        if let activity {
            guard force || abs(elapsed - lastElapsedUpdate) >= 30 else { return }
            lastElapsedUpdate = elapsed
            Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(45))) }
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
            windowSeconds: AppGroup.clipWindowSeconds
        )
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
        }
    }
}

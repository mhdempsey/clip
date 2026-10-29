import Foundation
import XCTest
@testable import ClipCore

final class ClipFeedbackTests: XCTestCase {
    func testSavedFeedbackPersistsAndBelongsOnlyToItsBook() throws {
        let suite = "ClipFeedbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = ClipActivityFeedback(outcome: .saved, date: Date(timeIntervalSince1970: 100), clipID: "stored-clip")
        saved.store(for: "first", defaults: defaults)
        XCTAssertEqual(ClipActivityFeedback.stored(for: "first", defaults: defaults), saved)
        XCTAssertNil(ClipActivityFeedback.stored(for: "second", defaults: defaults))
        XCTAssertEqual(saved.message, "Clip saved")
        XCTAssertNotEqual(ClipActivityFeedback(outcome: .failed).message, saved.message)
        XCTAssertNotEqual(ClipActivityFeedback(outcome: .unavailable).message, saved.message)
    }

    func testSharedPlaybackSnapshotTracksRatePausingAndStalePlayback() {
        let date = Date(timeIntervalSince1970: 100)
        let playing = ClipPlaybackSnapshot(bookID: "book", position: 20, duration: 100, rate: 2, isPlaying: true, date: date)
        XCTAssertEqual(playing.anchor(at: date.addingTimeInterval(3)), 26)
        XCTAssertNil(playing.anchor(at: date.addingTimeInterval(20)), "A stopped app must not extrapolate a stale playing position")
        let paused = ClipPlaybackSnapshot(bookID: "book", position: 20, duration: 100, rate: 2, isPlaying: false, date: date)
        XCTAssertEqual(paused.anchor(at: date.addingTimeInterval(200)), 20)
        let nearEnd = ClipPlaybackSnapshot(bookID: "book", position: 99, duration: 100, rate: 2, isPlaying: true, date: date)
        XCTAssertEqual(nearEnd.anchor(at: date.addingTimeInterval(3)), 100)
    }
}

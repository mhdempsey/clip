import AVFoundation
import Foundation
import XCTest
@testable import Clip

@MainActor
final class PlayerEngineTests: XCTestCase {
    func testCompleteLocalBundleLoadsAndPlays() async throws {
        let fixture = try makeFixture(includeAudio: true)
        defer {
            try? fixture.database.writer.close()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let engine = PlayerEngine(database: fixture.database)

        await engine.load(fixture.book)

        XCTAssertEqual(engine.currentBook?.id, fixture.book.id)
        XCTAssertNil(engine.playbackError)

        engine.play()
        let deadline = Date().addingTimeInterval(3)
        while engine.globalTime == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        engine.pause()

        XCTAssertGreaterThan(engine.globalTime, 0)
        XCTAssertNil(engine.playbackError)
    }

    func testPlaybackRatePersistsAndStaysWithinOneToThree() throws {
        let fixture = try makeFixture(includeAudio: false)
        let suiteName = "PlayerEngineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? fixture.database.writer.close()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let queue = AVQueuePlayer()
        let engine = PlayerEngine(database: fixture.database, defaults: defaults, player: queue)

        XCTAssertEqual(engine.playbackRate, 1)
        XCTAssertEqual(queue.defaultRate, 1)

        engine.setPlaybackRate(2.4)

        XCTAssertEqual(engine.playbackRate, 2.4, accuracy: 0.001)
        XCTAssertEqual(queue.defaultRate, 2.4, accuracy: 0.001)
        XCTAssertEqual(queue.rate, 0, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: AppGroup.Key.playbackRate), 2.4, accuracy: 0.001)

        let restored = PlayerEngine(
            database: fixture.database,
            defaults: defaults,
            player: AVQueuePlayer()
        )
        XCTAssertEqual(restored.playbackRate, 2.4, accuracy: 0.001)

        restored.setPlaybackRate(10)
        XCTAssertEqual(restored.playbackRate, 3)
        restored.setPlaybackRate(0)
        XCTAssertEqual(restored.playbackRate, 1)
    }

    func testChangingPlaybackRateUpdatesAudioAlreadyPlaying() async throws {
        let fixture = try makeFixture(includeAudio: true)
        let suiteName = "PlayerEngineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? fixture.database.writer.close()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let queue = AVQueuePlayer()
        let engine = PlayerEngine(database: fixture.database, defaults: defaults, player: queue)
        await engine.load(fixture.book)
        engine.setPlaybackRate(2)

        engine.play()
        let deadline = Date().addingTimeInterval(3)
        while queue.timeControlStatus != .playing, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(queue.rate, 2, accuracy: 0.05)
        engine.setPlaybackRate(3)
        XCTAssertEqual(queue.rate, 3, accuracy: 0.05)
        engine.pause()
    }

    func testBundleWithMissingAudioIsNotLoadedAsPlayable() async throws {
        let fixture = try makeFixture(includeAudio: false)
        defer {
            try? fixture.database.writer.close()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let engine = PlayerEngine(database: fixture.database)

        await engine.load(fixture.book)

        XCTAssertNil(engine.currentBook)
        XCTAssertTrue(engine.playbackError?.contains("audio files are missing") == true)
    }

    func testChapterTitlesComeFromPlaybackManifest() async throws {
        let fixture = try makeFixture(includeAudio: true)
        defer {
            try? fixture.database.writer.close()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let engine = PlayerEngine(database: fixture.database)

        await engine.load(fixture.book)

        XCTAssertEqual(engine.currentChapterTitle, "Opening")
        XCTAssertEqual(engine.chapterTitle(at: 0), "Opening")
        XCTAssertEqual(engine.chapterTitle(at: 1), "Second Chapter")
        XCTAssertEqual(engine.chapterTitle(at: 2), "Chapter 3")

        engine.seek(to: 1.25)
        XCTAssertEqual(engine.currentChapterTitle, "Second Chapter")
    }

    private func makeFixture(includeAudio: Bool) throws -> (
        root: URL,
        database: ClipDatabase,
        book: BookRecord
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundle = root.appendingPathComponent("Test.clipbook", isDirectory: true)
        let audioDirectory = bundle.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        if includeAudio {
            try writeSilentAudio(to: audioDirectory.appendingPathComponent("part.caf"))
        }
        let manifest = #"{"audio":[{"file":"audio/part.caf","offset_s":0,"duration_s":2}],"chapters":[{"title":"Opening","start_s":0},{"title":"Second Chapter","start_s":1}]}"#
        try Data(manifest.utf8).write(to: bundle.appendingPathComponent("sync.json"))

        let database = try ClipDatabase(url: root.appendingPathComponent("clip.sqlite"))
        let book = BookRecord(
            id: UUID().uuidString,
            title: "Test Book",
            author: "Test Author",
            bundleURL: bundle.path,
            durationS: 2,
            coverPath: nil,
            positionS: 0,
            addedAt: Date(),
            lastPlayedAt: nil
        )
        return (root, database, book)
    }

    private func writeSilentAudio(to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frameCount = AVAudioFrameCount(format.sampleRate * 2)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        buffer.floatChannelData?[0].initialize(repeating: 0, count: Int(frameCount))

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

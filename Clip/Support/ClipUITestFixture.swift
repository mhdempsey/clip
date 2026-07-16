#if DEBUG
import AVFoundation
import Foundation

enum ClipUITestFixture {
    private static let launchArgument = "--ui-test-player-fixture"

    static func installIfRequested(database: ClipDatabase) throws -> BookRecord? {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return nil }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipUITestFixture.clipbook", isDirectory: true)
        let audioDirectory = root.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try writeSilentAudio(to: audioDirectory.appendingPathComponent("part.caf"))

        let manifest = #"{"audio":[{"file":"audio/part.caf","offset_s":0,"duration_s":2}],"chapters":[{"title":"Opening","start_s":0},{"title":"Second Chapter","start_s":1}]}"#
        try Data(manifest.utf8).write(to: root.appendingPathComponent("sync.json"))

        let book = BookRecord(
            id: "clip-ui-test-player",
            title: "A Long Book Title for Layout Testing",
            author: "Synthetic Fixture",
            bundleURL: root.path,
            durationS: 2,
            coverPath: nil,
            positionS: 0,
            addedAt: Date(),
            lastPlayedAt: nil
        )
        let sentences = [
            SentenceRecord(
                bookId: book.id,
                i: 0,
                startS: 0,
                endS: 0.9,
                text: "The first synthetic passage.",
                chapter: 0,
                p: 0,
                conf: 1
            ),
            SentenceRecord(
                bookId: book.id,
                i: 1,
                startS: 1,
                endS: 1.9,
                text: "The second synthetic passage.",
                chapter: 1,
                p: 1,
                conf: 1
            ),
        ]
        try database.save(book: book, sentences: sentences)
        return book
    }

    private static func writeSilentAudio(to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(format.sampleRate * 2)
              )
        else { throw FixtureError.audioCreationFailed }

        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData?[0].initialize(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private enum FixtureError: Error {
        case audioCreationFailed
    }
}
#endif

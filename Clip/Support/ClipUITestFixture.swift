#if DEBUG
import AVFoundation
import Foundation

enum ClipUITestFixture {
    private static let launchArgument = "--ui-test-player-fixture"

    static func installIfRequested(database: ClipDatabase) throws -> BookRecord? {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return nil }

        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset-reader") {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("Clip.Reader.") || key.hasPrefix("Clip.Library.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipUITestFixture.clipbook", isDirectory: true)
        let audioDirectory = root.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try writeSilentAudio(to: audioDirectory.appendingPathComponent("part.caf"))

        let manifest = #"{"audio":[{"file":"audio/part.caf","offset_s":0,"duration_s":240}],"chapters":[{"title":"Opening","start_s":0},{"title":"Second Chapter","start_s":120}]}"#
        try Data(manifest.utf8).write(to: root.appendingPathComponent("sync.json"))

        let book = BookRecord(
            id: "clip-ui-test-player",
            title: "The Sentence Worth Keeping",
            author: "Clip Review Fixture",
            bundleURL: root.path,
            durationS: 240,
            coverPath: nil,
            positionS: 0,
            addedAt: Date(),
            lastPlayedAt: nil
        )
        let paragraphs = [
            ["The morning light reached the books before it reached the window.", "She had left one open on the table, a sentence marked with a small fold of paper.", "There was no hurry to turn the page."],
            ["Outside, the city was beginning its familiar conversation.", "A bicycle crossed the square, and somewhere a shopkeeper lifted a shutter.", "She read the passage again, finding something in it she had missed the night before."],
            ["Some words ask very little of us at first.", "They sit quietly on the page until a day arrives when we are ready to hear them.", "Then the same sentence becomes a place we can return to."],
            ["She took the book with her when she left.", "The folded paper stayed between the pages, keeping its modest record of the morning.", "By the river she found a bench and began the next chapter."],
        ]
        let sentences = (0..<48).map { index in
            SentenceRecord(
                bookId: book.id, i: index,
                startS: Double(index * 5),
                endS: Double(index * 5) + 4.9,
                text: paragraphs[(index / 3) % paragraphs.count][index % 3],
                chapter: index < 24 ? 0 : 1, p: index / 3,
                conf: 1
            )
        }
        try database.save(book: book, sentences: sentences)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reset-reader") {
            for clip in try database.clips(bookID: book.id) { try database.deleteQueueItem(id: clip.id) }
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-saved-clips-fixture") {
            for id in ["fixture-saved-clip", "fixture-sent-clip"] { try database.deleteQueueItem(id: id) }
            try database.insert(queueItem: ClipQueueRecord(id: "fixture-saved-clip", bookId: book.id, text: sentences[0].text, note: "audio @ 0:00", location: 0, createdAt: Date().addingTimeInterval(-60), attempts: 0))
            try database.insert(queueItem: ClipQueueRecord(id: "fixture-sent-clip", bookId: book.id, text: sentences[3].text, note: "audio @ 0:15", location: 3, createdAt: Date().addingTimeInterval(-120), sentAt: Date().addingTimeInterval(-110), attempts: 0))
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-library-fixture") {
            for (index, title) in ["A Room of One’s Own", "Middlemarch", "The Waves", "To the Lighthouse", "Orlando"].enumerated() {
                var entry = book
                entry.id = "library-fixture-\(index)"
                entry.title = title
                entry.author = index == 1 ? "George Eliot" : "Virginia Woolf"
                entry.positionS = Double(index * 24)
                entry.addedAt = Date(timeIntervalSince1970: Double(index))
                try database.save(book: entry, sentences: [])
                try database.setRead(bookID: entry.id, isRead: index == 4)
            }
        }
        return book
    }

    private static func writeSilentAudio(to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(format.sampleRate)
              )
        else { throw FixtureError.audioCreationFailed }

        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData?[0].initialize(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        for _ in 0..<240 { try file.write(from: buffer) }
    }

    private enum FixtureError: Error {
        case audioCreationFailed
    }
}
#endif

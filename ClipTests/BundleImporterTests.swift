import AVFoundation
import ClipCore
import Foundation
import XCTest
@testable import Clip

@MainActor
final class BundleImporterTests: XCTestCase {
    func testLocalImportCopiesBundleIntoPersistentStorageAndIndexesIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceBundle = root.appendingPathComponent("AirDropped.clipbook", isDirectory: true)
        let localBooksDirectory = root.appendingPathComponent("Imported Books", isDirectory: true)
        let database = try ClipDatabase(url: root.appendingPathComponent("clip.sqlite"))
        defer {
            try? database.writer.close()
            try? FileManager.default.removeItem(at: root)
        }
        try makeBundle(at: sourceBundle)
        let importer = BundleImporter(
            database: database,
            localBooksDirectory: localBooksDirectory
        )

        let imported = try await importer.importLocalBundle(at: sourceBundle)

        let expectedURL = localBooksDirectory.appendingPathComponent("AirDropped.clipbook", isDirectory: true)
        XCTAssertEqual(imported.bundleFileURL.standardizedFileURL, expectedURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: expectedURL.appendingPathComponent("audio/part.caf").path
        ))
        let stored = try XCTUnwrap(database.books().first)
        XCTAssertEqual(stored.id, imported.id)
        XCTAssertEqual(stored.title, imported.title)
        XCTAssertEqual(stored.author, imported.author)
        XCTAssertEqual(stored.bundleURL, imported.bundleURL)
    }

    func testIncomingBundleOpensInPlayer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceBundle = root.appendingPathComponent("AirDropped.clipbook", isDirectory: true)
        let database = try ClipDatabase(url: root.appendingPathComponent("clip.sqlite"))
        defer {
            try? database.writer.close()
            try? FileManager.default.removeItem(at: root)
        }
        try makeBundle(at: sourceBundle)
        let player = PlayerEngine(database: database)
        let model = AppModel(
            database: database,
            player: player,
            localBooksDirectory: root.appendingPathComponent("Imported Books", isDirectory: true)
        )

        await model.importBook(from: sourceBundle)

        let deadline = Date().addingTimeInterval(3)
        while player.currentBook == nil, player.playbackError == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.selectedTab, .player)
        XCTAssertEqual(player.currentBook?.title, "AirDropped Book")
        XCTAssertNil(player.playbackError)
        XCTAssertNil(model.alertMessage)
    }

    func testIOSAppDeclaresItCanOpenClipbookDocuments() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("Config/Clip-Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let documentTypes = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let clipbook = try XCTUnwrap(documentTypes.first { declaration in
            (declaration["LSItemContentTypes"] as? [String])?.contains("com.michael.clip.clipbook") == true
        })

        XCTAssertEqual(clipbook["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(plist["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
    }

    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<2 { url.deleteLastPathComponent() }
        return url
    }

    private func makeBundle(at url: URL) throws {
        let audioDirectory = url.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try writeSilentAudio(to: audioDirectory.appendingPathComponent("part.caf"))
        let sync = ClipBookSync(
            book: SyncBook(
                title: "AirDropped Book",
                author: "Test Author",
                durationS: 60,
                aligner: AlignerInfo(engine: "test", model: "test", coverage: 1, created: "2026-07-15")
            ),
            audio: [SyncAudio(file: "audio/part.caf", offsetS: 0, durationS: 2)],
            chapters: [],
            sentences: []
        )
        try JSONEncoder.clipSync.encode(sync).write(to: url.appendingPathComponent("sync.json"))
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

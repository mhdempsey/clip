import Foundation
import XCTest
@testable import ClipCore

final class ClipBookBundleTests: XCTestCase {
    func testAudioFilesRequiringDownloadIncludesEveryMissingManifestFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let audioDirectory = root.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("ready".utf8).write(to: audioDirectory.appendingPathComponent("part01.m4a"))

        let unavailable = ClipBookBundle.audioFilesRequiringDownload(
            in: sync(audioFiles: ["audio/part01.m4a", "audio/part02.m4a"]),
            at: root
        )

        XCTAssertEqual(unavailable.map(\.lastPathComponent), ["part02.m4a"])
    }

    func testAudioFilesRequiringDownloadIsEmptyWhenEveryManifestFileIsLocal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let audioDirectory = root.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("one".utf8).write(to: audioDirectory.appendingPathComponent("part01.m4a"))
        try Data("two".utf8).write(to: audioDirectory.appendingPathComponent("part02.m4a"))

        let unavailable = ClipBookBundle.audioFilesRequiringDownload(
            in: sync(audioFiles: ["audio/part01.m4a", "audio/part02.m4a"]),
            at: root
        )

        XCTAssertTrue(unavailable.isEmpty)
    }

    func testBothAppsExportClipbookAsAnICloudFilePackage() throws {
        for path in ["Config/Clip-Info.plist", "Config/ClipMac-Info.plist"] {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            let declarations = try XCTUnwrap(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
            let clipbook = try XCTUnwrap(declarations.first { declaration in
                declaration["UTTypeIdentifier"] as? String == "com.michael.clip.clipbook"
            })
            let conformances = try XCTUnwrap(clipbook["UTTypeConformsTo"] as? [String])
            let tags = try XCTUnwrap(clipbook["UTTypeTagSpecification"] as? [String: Any])

            XCTAssertTrue(conformances.contains("com.apple.package"), path)
            XCTAssertEqual(tags["public.filename-extension"] as? [String], ["clipbook"], path)
        }
    }

    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }

    private func sync(audioFiles: [String]) -> ClipBookSync {
        ClipBookSync(
            book: SyncBook(
                title: "Test",
                author: "Author",
                durationS: 120,
                aligner: AlignerInfo(engine: "test", model: "test", coverage: 1, created: "2026-07-15")
            ),
            audio: audioFiles.enumerated().map { index, file in
                SyncAudio(file: file, offsetS: Double(index) * 60, durationS: 60)
            },
            chapters: [],
            sentences: []
        )
    }
}

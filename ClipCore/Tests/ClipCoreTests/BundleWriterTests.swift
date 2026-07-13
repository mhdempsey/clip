import Foundation
import XCTest
@testable import ClipCore

final class BundleWriterTests: XCTestCase {
    func testWritesCompleteBundleAndCoverageReport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let input = root.appendingPathComponent("input")
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let audio = input.appendingPathComponent("part01.m4a")
        let epub = input.appendingPathComponent("source.epub")
        try Data("audio".utf8).write(to: audio)
        try Data("epub".utf8).write(to: epub)

        let result = try await BundleWriter.write(
            sync: fixture(),
            audioFiles: [audio],
            sourceEPUB: epub,
            coverImage: Data("cover".utf8),
            to: output
        )

        XCTAssertEqual(result.bundleURL.lastPathComponent, "Test Book.clipbook")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("sync.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("audio/part01.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("source.epub").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundleURL.appendingPathComponent("cover.jpg").path))
        XCTAssertEqual(result.report.sentenceCoverage, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.report.chapters.first?.firstTimestamp, 0)
        XCTAssertEqual(result.report.chapters.first?.lastTimestamp, 10)
        let outputEntries = try FileManager.default.contentsOfDirectory(atPath: output.path)
        XCTAssertFalse(outputEntries.contains { $0.hasSuffix(".tmp") })
    }

    func testInvalidSyncNeverReplacesExistingBundle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("Test Book.clipbook")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let sentinel = existing.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        let source = root.appendingPathComponent("source.epub")
        try Data().write(to: source)
        var invalid = fixture()
        invalid.sentences[0].conf = 2

        await XCTAssertThrowsErrorAsync {
            try await BundleWriter.write(sync: invalid, audioFiles: [], sourceEPUB: source, coverImage: nil, to: root)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }

    private func fixture() -> ClipBookSync {
        ClipBookSync(
            version: 1,
            book: SyncBook(title: "Test Book", author: "Author", durationS: 120, aligner: AlignerInfo(engine: "whisperkit", model: "base", coverage: 0.5, created: "2026-07-12")),
            audio: [SyncAudio(file: "audio/part01.m4a", offsetS: 0, durationS: 120)],
            chapters: [SyncChapter(title: "One", startS: 0, epubHref: "one.xhtml")],
            sentences: [
                SyncSentence(i: 0, startS: 0, endS: 10, text: "Timed.", chapter: 0, p: 0, epub: EPUBPosition(href: "one.xhtml", charStart: 0, charEnd: 6), conf: 1, words: [TimedWord(w: "Timed.", s: 0, e: 10)]),
                SyncSentence(i: 1, startS: nil, endS: nil, text: "Untimed.", chapter: 0, p: 1, epub: EPUBPosition(href: "one.xhtml", charStart: 7, charEnd: 15), conf: 0, words: nil),
            ]
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}

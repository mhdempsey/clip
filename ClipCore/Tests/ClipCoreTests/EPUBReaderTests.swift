import Foundation
import XCTest
import ZIPFoundation
@testable import ClipCore

final class EPUBReaderTests: XCTestCase {
    func testReadsMetadataSpineChaptersCoverAndOffsetsEndToEnd() throws {
        let cover = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let second = #"<html><head><title>Fallback</title></head><body><h1>Second</h1><p>Whale &amp; <em>ship</em>.</p></body></html>"#
        let first = #"<html><body><h1>First</h1><p>Call me Ishmael.</p></body></html>"#
        var entries = baseEntries(package: packageDocument())
        entries["OPS/Text/second.xhtml"] = Data(second.utf8)
        entries["OPS/Text/first.xhtml"] = Data(first.utf8)
        entries["OPS/Images/cover.jpg"] = cover
        let epub = try makeArchive(entries: entries)
        defer { try? FileManager.default.removeItem(at: epub.deletingLastPathComponent()) }

        let book = try EPUBReader.read(from: epub)

        XCTAssertEqual(book.metadata, EPUBMetadata(title: "Test Voyage", author: "Reader One"))
        XCTAssertEqual(book.chapters.map(\.title), ["Second", "First"])
        XCTAssertEqual(book.chapters.map(\.href), ["Text/second.xhtml", "Text/first.xhtml"])
        XCTAssertEqual(book.sentences.map(\.text), ["Second", "Whale & ship.", "First", "Call me Ishmael."])
        XCTAssertEqual(book.coverData, cover)

        let sentence = try XCTUnwrap(book.sentences.first { $0.text == "Whale & ship." })
        let raw = substring(second, sentence.epub.charStart..<sentence.epub.charEnd)
        XCTAssertEqual(XHTMLTextScanner.scan("<p>\(raw)</p>").text, sentence.text)
    }

    func testReadsNCXLabelsAndFragmentChapterBoundaries() throws {
        let document = #"<html><head><title>Index</title></head><body><a id="opening"></a><p>The first passage.</p><a id="second"></a><p>The second passage.</p></body></html>"#
        let navigation = #"<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap><navPoint id="one" playOrder="1"><navLabel><text>Opening</text></navLabel><content src="Text/index.xhtml#opening"/></navPoint><navPoint id="two" playOrder="2"><navLabel><text>Second Chapter</text></navLabel><content src="Text/index.xhtml#second"/></navPoint></navMap></ncx>"#
        let manifest = #"<item id="content" href="Text/index.xhtml" media-type="application/xhtml+xml"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>"#
        var entries = baseEntries(package: packageDocument(
            manifest: manifest,
            spine: #"<itemref idref="content"/>"#
        ))
        entries["OPS/Text/index.xhtml"] = Data(document.utf8)
        entries["OPS/toc.ncx"] = Data(navigation.utf8)
        let epub = try makeArchive(entries: entries)
        defer { try? FileManager.default.removeItem(at: epub.deletingLastPathComponent()) }

        let book = try EPUBReader.read(from: epub)

        XCTAssertEqual(book.chapters.map(\.title), ["Opening", "Second Chapter"])
        XCTAssertEqual(book.chapters.map(\.sentenceRange), [0..<1, 1..<2])
        XCTAssertEqual(book.sentences.map(\.chapter), [0, 1])
    }

    func testReadsEPUB3NavigationLabelsAndNestedLinkText() throws {
        let document = #"<html><head><title>Index</title></head><body><section id="first" data-id="second"><p>The first passage.</p></section><section id="second"><p>The second passage.</p></section></body></html>"#
        let navigation = #"<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="Text/index.xhtml#first"><span>Part One</span></a></li><li><a href="Text/index.xhtml#second">Part <em>Two</em></a></li></ol></nav></body></html>"#
        let manifest = #"<item id="content" href="Text/index.xhtml" media-type="application/xhtml+xml"/><item id="navigation" href="nav.xhtml" media-type="application/xhtml+xml" properties="scripted&#9;nav"/>"#
        var entries = baseEntries(package: packageDocument(
            manifest: manifest,
            spine: #"<itemref idref="content"/>"#
        ))
        entries["OPS/Text/index.xhtml"] = Data(document.utf8)
        entries["OPS/nav.xhtml"] = Data(navigation.utf8)
        let epub = try makeArchive(entries: entries)
        defer { try? FileManager.default.removeItem(at: epub.deletingLastPathComponent()) }

        let book = try EPUBReader.read(from: epub)

        XCTAssertEqual(book.chapters.map(\.title), ["Part One", "Part Two"])
        XCTAssertEqual(book.chapters.map(\.sentenceRange), [0..<1, 1..<2])
        XCTAssertEqual(book.sentences.map(\.chapter), [0, 1])
    }

    func testRejectsMissingContainerAndMissingSpineManifestItem() throws {
        let missingContainer = try makeArchive(entries: ["mimetype": Data("application/epub+zip".utf8)])
        defer { try? FileManager.default.removeItem(at: missingContainer.deletingLastPathComponent()) }
        XCTAssertThrowsError(try EPUBReader.read(from: missingContainer)) { error in
            guard case EPUBReaderError.missingContainer = error else { return XCTFail("Unexpected error: \(error)") }
        }

        let package = packageDocument(spine: #"<itemref idref="missing"/>"#)
        let missingItem = try makeArchive(entries: baseEntries(package: package))
        defer { try? FileManager.default.removeItem(at: missingItem.deletingLastPathComponent()) }
        XCTAssertThrowsError(try EPUBReader.read(from: missingItem)) { error in
            guard case EPUBReaderError.missingSpineItem("missing") = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testRejectsTextContainingAnEmbeddedExecutablePayload() throws {
        let document = #"<html><body><p>This program cannot be run in DOS mode. KERNEL32.dll .rsrc .reloc</p><p>This program cannot be run in DOS mode. BATMETER.DLL RSDS helper.pdb</p></body></html>"#
        var entries = baseEntries(package: packageDocument(
            manifest: #"<item id="content" href="Text/index.xhtml" media-type="application/xhtml+xml"/>"#,
            spine: #"<itemref idref="content"/>"#
        ))
        entries["OPS/Text/index.xhtml"] = Data(document.utf8)
        let epub = try makeArchive(entries: entries)
        defer { try? FileManager.default.removeItem(at: epub.deletingLastPathComponent()) }

        XCTAssertThrowsError(try EPUBReader.read(from: epub)) { error in
            guard case EPUBReaderError.embeddedBinaryContent("Text/index.xhtml") = error else {
                return XCTFail("Expected embeddedBinaryContent, got \(error)")
            }
        }
    }

    func testRejectsManifestPathOutsideExtractionRoot() throws {
        let package = packageDocument(
            manifest: #"<item id="escape" href="../../../outside.xhtml" media-type="application/xhtml+xml"/>"#,
            spine: #"<itemref idref="escape"/>"#
        )
        let epub = try makeArchive(entries: baseEntries(package: package))
        defer { try? FileManager.default.removeItem(at: epub.deletingLastPathComponent()) }

        XCTAssertThrowsError(try EPUBReader.read(from: epub)) { error in
            guard case EPUBReaderError.unsafePath("../../../outside.xhtml") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testArchiveBudgetValidationRejectsEachLimit() {
        assertPreflightError(.archiveTooManyEntries) { total in
            try EPUBArchivePreflight.validate(path: "x", isSymbolicLink: false, compressedSize: 1, uncompressedSize: 1, entryCount: 10_001, totalUncompressedSize: &total)
        }
        assertPreflightError(.archiveEntryTooLarge("large")) { total in
            try EPUBArchivePreflight.validate(path: "large", isSymbolicLink: false, compressedSize: 2_000_000, uncompressedSize: 128 * 1024 * 1024 + 1, entryCount: 1, totalUncompressedSize: &total)
        }
        assertPreflightError(.archiveTooLarge, startingTotal: 512 * 1024 * 1024) { total in
            try EPUBArchivePreflight.validate(path: "extra", isSymbolicLink: false, compressedSize: 1, uncompressedSize: 1, entryCount: 1, totalUncompressedSize: &total)
        }
        assertPreflightError(.archiveEntryCompressionRatio("compressed")) { total in
            try EPUBArchivePreflight.validate(path: "compressed", isSymbolicLink: false, compressedSize: 10, uncompressedSize: 1_001, entryCount: 1, totalUncompressedSize: &total)
        }
        assertPreflightError(.archiveContainsSymbolicLink("link")) { total in
            try EPUBArchivePreflight.validate(path: "link", isSymbolicLink: true, compressedSize: 4, uncompressedSize: 4, entryCount: 1, totalUncompressedSize: &total)
        }
    }

    private func baseEntries(package: String) -> [String: Data] {
        [
            "mimetype": Data("application/epub+zip".utf8),
            "META-INF/container.xml": Data(containerDocument.utf8),
            "OPS/package.opf": Data(package.utf8),
        ]
    }

    private var containerDocument: String {
        #"<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
    }

    private func packageDocument(
        manifest: String = #"<item id="cover" href="Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/><item id="first" href="Text/first.xhtml" media-type="application/xhtml+xml"/><item id="second" href="Text/second.xhtml" media-type="application/xhtml+xml"/>"#,
        spine: String = #"<itemref idref="second"/><itemref idref="first"/>"#
    ) -> String {
        #"<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Test Voyage</dc:title><dc:creator>Reader One</dc:creator></metadata><manifest>"# + manifest + #"</manifest><spine>"# + spine + #"</spine></package>"#
    }

    private func makeArchive(entries: [String: Data]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("fixture.epub")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                let lower = Int(position)
                let upper = min(lower + size, data.count)
                return data.subdata(in: lower..<upper)
            }
        }
        return url
    }

    private func substring(_ string: String, _ range: Range<Int>) -> String {
        let lower = string.index(string.startIndex, offsetBy: range.lowerBound)
        let upper = string.index(string.startIndex, offsetBy: range.upperBound)
        return String(string[lower..<upper])
    }

    private func assertPreflightError(
        _ expected: ExpectedArchiveError,
        startingTotal: UInt64 = 0,
        operation: (inout UInt64) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var total = startingTotal
        XCTAssertThrowsError(try operation(&total), file: file, line: line) { error in
            XCTAssertTrue(expected.matches(error), "Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private enum ExpectedArchiveError {
    case archiveTooManyEntries
    case archiveTooLarge
    case archiveEntryTooLarge(String)
    case archiveEntryCompressionRatio(String)
    case archiveContainsSymbolicLink(String)

    func matches(_ error: Error) -> Bool {
        switch (self, error) {
        case (.archiveTooManyEntries, EPUBReaderError.archiveTooManyEntries),
             (.archiveTooLarge, EPUBReaderError.archiveTooLarge): true
        case let (.archiveEntryTooLarge(expected), EPUBReaderError.archiveEntryTooLarge(actual)),
             let (.archiveEntryCompressionRatio(expected), EPUBReaderError.archiveEntryCompressionRatio(actual)),
             let (.archiveContainsSymbolicLink(expected), EPUBReaderError.archiveContainsSymbolicLink(actual)):
            expected == actual
        default: false
        }
    }
}

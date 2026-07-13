import XCTest
@testable import ClipCore

final class XHTMLTextScannerTests: XCTestCase {
    func testDecodesEntitiesAndSkipsNonProseContent() {
        let xhtml = #"<html><body><!-- hidden --><style>.x{}</style><script>alert(1)</script><p>Fish &amp; Chips &lt;3 &#33; &#x1F40B; &nbsp; &ldquo;yes&rdquo;</p><![CDATA[skip me]]></body></html>"#
        let result = XHTMLTextScanner.scan(xhtml)

        XCTAssertEqual(result.text, "Fish & Chips <3 ! 🐋 \u{00A0} “yes”")
        XCTAssertFalse(result.text.contains("hidden"))
        XCTAssertFalse(result.text.contains("alert"))
        XCTAssertFalse(result.text.contains("skip me"))
    }

    func testParagraphsHeadingsAndOffsetsRoundTrip() throws {
        let xhtml = #"<html><head><title>A Voyage</title></head><body><h1>Chapter One</h1><p>Call <em>me</em> Ishmael.</p><p>Some years ago.</p></body></html>"#
        let result = XHTMLTextScanner.scan(xhtml)

        XCTAssertEqual(result.blocks.map(\.text), ["Chapter One", "Call me Ishmael.", "Some years ago."])
        XCTAssertEqual(result.headings.map(\.text), ["Chapter One"])
        XCTAssertEqual(result.headings.first?.level, 1)

        let sentence = try XCTUnwrap(result.blocks.first { $0.text == "Call me Ishmael." })
        let raw = substring(xhtml, sentence.sourceRange)
        XCTAssertEqual(stripTags(raw), "Call me Ishmael.")
    }

    func testOffsetsUseSwiftCharacterPositionsWithUnicodeBeforeText() throws {
        let xhtml = #"<p>🐋 Prelude.</p><p>Café society.</p>"#
        let result = XHTMLTextScanner.scan(xhtml)
        let block = try XCTUnwrap(result.blocks.last)

        XCTAssertEqual(substring(xhtml, block.sourceRange), "Café society.")
        XCTAssertEqual(block.text, "Café society.")
    }

    func testCharacterMapsSpanInlineTagsEntitiesUnicodeAndWhitespace() throws {
        let xhtml = "<p>  Café <em>&amp; 🐋</em>\n\t  sails&#33;  </p>"
        let block = try XCTUnwrap(XHTMLTextScanner.scan(xhtml).blocks.first)

        XCTAssertEqual(block.text, "Café & 🐋 sails!")
        XCTAssertEqual(block.sourceCharacterStarts.count, block.text.count)
        XCTAssertEqual(block.sourceCharacterEnds.count, block.text.count)

        let ampersand = try XCTUnwrap(block.text.firstIndex(of: "&"))
        let ampersandOffset = block.text.distance(from: block.text.startIndex, to: ampersand)
        XCTAssertEqual(substring(xhtml, block.sourceCharacterStarts[ampersandOffset]..<block.sourceCharacterEnds[ampersandOffset]), "&amp;")

        let whale = try XCTUnwrap(block.text.firstIndex(of: "🐋"))
        let whaleOffset = block.text.distance(from: block.text.startIndex, to: whale)
        XCTAssertEqual(substring(xhtml, block.sourceCharacterStarts[whaleOffset]..<block.sourceCharacterEnds[whaleOffset]), "🐋")

        for offset in block.text.indices {
            let characterOffset = block.text.distance(from: block.text.startIndex, to: offset)
            let raw = substring(xhtml, block.sourceCharacterStarts[characterOffset]..<block.sourceCharacterEnds[characterOffset])
            if block.text[offset].isWhitespace {
                XCTAssertTrue(raw.allSatisfy(\.isWhitespace))
            } else {
                XCTAssertEqual(XHTMLTextScanner.scan("<p>\(raw)</p>").text, String(block.text[offset]))
            }
        }

        let mappedRange = block.sourceCharacterStarts[0]..<block.sourceCharacterEnds[block.sourceCharacterEnds.count - 1]
        XCTAssertEqual(stripTags(substring(xhtml, mappedRange)), block.text)
    }

    func testDivOnlyCreatesBlockWhenItDirectlyContainsText() {
        let nested = XHTMLTextScanner.scan("<div><p>First.</p><p>Second.</p></div>")
        XCTAssertEqual(nested.blocks.map(\.text), ["First.", "Second."])

        let direct = XHTMLTextScanner.scan("<div>Direct <span>words</span>.</div>")
        XCTAssertEqual(direct.blocks.map(\.text), ["Direct words."])
    }

    private func substring(_ string: String, _ range: Range<Int>) -> String {
        let lower = string.index(string.startIndex, offsetBy: range.lowerBound)
        let upper = string.index(string.startIndex, offsetBy: range.upperBound)
        return String(string[lower..<upper])
    }

    private func stripTags(_ source: String) -> String {
        XHTMLTextScanner.scan("<p>\(source)</p>").text
    }
}

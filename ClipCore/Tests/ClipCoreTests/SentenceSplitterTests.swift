import XCTest
@testable import ClipCore

final class SentenceSplitterTests: XCTestCase {
    func testSplitsSentencesAndPreservesCharacterRanges() {
        let text = "Call me Ishmael. Some years ago—never mind how long precisely."
        let spans = SentenceSplitter.split(text)

        XCTAssertEqual(spans.map(\.text), [
            "Call me Ishmael.",
            "Some years ago—never mind how long precisely.",
        ])
        XCTAssertEqual(spans.map { substring(text, $0.range) }, spans.map(\.text))
    }

    func testDoesNotSplitAfterGuardedAbbreviations() {
        let text = "Mr. Jones met Dr. Smith on St. James St. They discussed examples, e.g. whales. Then they left."
        let spans = SentenceSplitter.split(text)

        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].text, "Mr. Jones met Dr. Smith on St. James St. They discussed examples, e.g. whales.")
        XCTAssertEqual(spans[1].text, "Then they left.")
    }

    func testHandlesBlankAndSingleSentenceInput() {
        XCTAssertEqual(SentenceSplitter.split(" \n\t "), [])
        XCTAssertEqual(SentenceSplitter.split("No terminal punctuation").map(\.text), ["No terminal punctuation"])
    }

    private func substring(_ string: String, _ range: Range<Int>) -> String {
        let lower = string.index(string.startIndex, offsetBy: range.lowerBound)
        let upper = string.index(string.startIndex, offsetBy: range.upperBound)
        return String(string[lower..<upper])
    }
}

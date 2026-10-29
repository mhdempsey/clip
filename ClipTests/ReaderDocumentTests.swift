import XCTest
@testable import Clip

final class ReaderDocumentTests: XCTestCase {
    func testParagraphsFlowAndChapterBoundariesRemainDistinct() {
        let document = ReaderDocument(sentences: [
            sentence(0, " First sentence. "), sentence(1, "Second sentence."),
            sentence(2, "A new paragraph.", paragraph: 1),
            sentence(3, "Another chapter.", chapter: 1)
        ], chapterTitle: { "Chapter \($0 + 1)" })

        XCTAssertEqual(document.text, "Chapter 1\nFirst sentence. Second sentence.\nA new paragraph.\nChapter 2\nAnother chapter.")
        XCTAssertEqual(document.chapters.count, 2)
        XCTAssertEqual(document.passages.count, 4)
        for passage in document.passages {
            XCTAssertEqual((document.text as NSString).substring(with: passage.range), passage.sentence.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func testUnicodeSelectionMapsToWholeSentencesWithoutIncludingHeadings() throws {
        let document = ReaderDocument(sentences: [sentence(4, "Café 👩🏽‍🚀."), sentence(9, "Café 👩🏽‍🚀.")], chapterTitle: { _ in "Opening" })
        let first = try XCTUnwrap(document.passages.first)
        let second = try XCTUnwrap(document.passages.last)
        XCTAssertEqual(document.sentenceIndices(in: NSRange(location: first.range.location + 2, length: second.range.location - first.range.location)), 4...9)
        XCTAssertNil(document.sentenceIndices(in: NSRange(location: 0, length: 7)))
        XCTAssertEqual(document.passage(at: second.range.location)?.sentence.i, 9)
        XCTAssertNil(document.passage(at: -1))
        XCTAssertNil(document.passage(at: (document.text as NSString).length))
    }

    func testUnorderedInputAndEmptyBookAreSafe() {
        let document = ReaderDocument(sentences: [sentence(8, "Later."), sentence(2, "Earlier.")], chapterTitle: { _ in "Opening" })
        XCTAssertEqual(document.passages.map(\.sentence.i), [2, 8])
        XCTAssertTrue(ReaderDocument(sentences: [], chapterTitle: { _ in "" }).text.isEmpty)
    }

    func testReaderNavigationUsesTheFirstTimedPassageOnTheVisiblePage() throws {
        var untimed = sentence(1, "An unaligned passage.")
        untimed.startS = nil
        untimed.endS = nil
        untimed.conf = 0
        let document = ReaderDocument(sentences: [sentence(0, "A sentence across a page boundary."), untimed, sentence(2, "The next spoken passage.")], chapterTitle: { _ in "Opening" })
        let first = document.passages[0].range
        XCTAssertEqual(document.playbackSentence(in: NSRange(location: first.location + 5, length: 8))?.i, 0)
        XCTAssertNil(document.playbackSentence(in: document.passages[1].range), "An untimed page must not jump to another part of the book")
        XCTAssertEqual(document.playbackSentence(in: NSRange(location: 0, length: document.utf16Length))?.i, 0)
    }

    func testAudioCursorStaysHighlightedBeforeSpeechDuringPausesAndAtTheEnd() {
        var first = sentence(0, "The opening sentence.")
        first.startS = 3
        first.endS = 5
        var last = sentence(1, "The final sentence.")
        last.startS = 8
        last.endS = 10
        let document = ReaderDocument(sentences: [first, last], chapterTitle: { _ in "Opening" })
        XCTAssertEqual(document.activeSentence(at: 0), 0)
        XCTAssertEqual(document.activeSentence(at: 6), 0)
        XCTAssertEqual(document.activeSentence(at: 8), 1)
        XCTAssertEqual(document.activeSentence(at: 12), 1)
        XCTAssertNil(ReaderDocument(sentences: [], chapterTitle: { _ in "" }).activeSentence(at: 0))
    }

    func testSearchFindsEveryCaseAndAccentInsensitiveMatchWithCorrectUnicodeOffsets() {
        let document = ReaderDocument(sentences: [sentence(0, "Café 👩🏽‍🚀 by the river."), sentence(1, "A second CAFE by the river.")], chapterTitle: { _ in "Opening" })
        let matches = document.search(" cafe ")
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.map { (document.text as NSString).substring(with: $0.range) }, ["Café", "CAFE"])
        XCTAssertEqual(document.search("river").count, 2)
        XCTAssertEqual(document.search("👩🏽‍🚀").count, 1)
        XCTAssertTrue(document.search("missing phrase").isEmpty)
        XCTAssertTrue(document.search("   ").isEmpty)
    }

    func testSearchCanFindAPhraseAcrossSentenceBoundaries() {
        let document = ReaderDocument(sentences: [sentence(0, "The first sentence ends here."), sentence(1, "The next begins nearby.")], chapterTitle: { _ in "Opening" })
        XCTAssertEqual(document.search("here. The next").count, 1)
    }

    private func sentence(_ index: Int, _ text: String, paragraph: Int = 0, chapter: Int = 0) -> SentenceRecord {
        SentenceRecord(bookId: "reader", i: index, startS: Double(index), endS: Double(index + 1), text: text, chapter: chapter, p: paragraph, conf: 1)
    }
}

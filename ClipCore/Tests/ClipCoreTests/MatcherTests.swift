import XCTest
@testable import ClipCore

final class MatcherTests: XCTestCase {
    func testNormalizationFoldsPunctuationDiacriticsAndNumbers() {
        XCTAssertEqual(Matcher.normalize("“CAFÉ—”"), ["cafe"])
        XCTAssertEqual(Matcher.normalize("1984"), ["nineteen", "eighty", "four"])
        XCTAssertEqual(Matcher.normalize("21st"), ["twenty", "first"])
        XCTAssertEqual(Matcher.normalize("!!!"), [])
    }

    func testSyntheticNoisyTranscriptTimesAtLeastNinetyFivePercent() {
        let deleted = 60..<64
        let sentences = makeSentences(count: 120)
        var transcript: [TranscriptWord] = []
        var clock = 0.0

        for i in 0..<40 {
            transcript.append(TranscriptWord(w: "introduction\(i)", s: clock, e: clock + 0.2))
            clock += 0.25
        }

        for sentence in sentences where !deleted.contains(sentence.i) {
            for (wordIndex, word) in words(sentence.text).enumerated() {
                let ordinal = sentence.i * 10 + wordIndex
                let emitted = ordinal.isMultiple(of: 20) ? "noise\(ordinal)" : word
                transcript.append(TranscriptWord(w: emitted, s: clock, e: clock + 0.2))
                clock += 0.25
            }
        }

        let result = Matcher.align(sentences: sentences, transcript: transcript)
        let timed = result.sentences.filter(\.isTimed)

        XCTAssertGreaterThanOrEqual(Double(timed.count) / Double(sentences.count), 0.95)
        XCTAssertGreaterThanOrEqual(result.sentences[0].startS ?? 0, 9.5, "Narrator intro must not be assigned to book text")
        XCTAssertTrue(result.sentences[60...63].allSatisfy { !$0.isTimed }, "Deleted paragraph should remain untimed")
        assertValidTimings(result.sentences)
    }

    func testInterpolatesShortUnmatchedSentenceBetweenTimedNeighbors() {
        let sentences = [
            epubSentence(0, "Alpha bravo charlie delta echo foxtrot.", paragraph: 0),
            epubSentence(1, "A tiny missing aside.", paragraph: 1),
            epubSentence(2, "Golf hotel india juliet kilo lima.", paragraph: 2),
        ]
        let transcript = timedWords("Alpha bravo charlie delta echo foxtrot Golf hotel india juliet kilo lima", step: 0.5)

        let result = Matcher.align(sentences: sentences, transcript: transcript)
        let middle = result.sentences[1]

        XCTAssertTrue(middle.isTimed)
        XCTAssertNotNil(middle.words)
        XCTAssertFalse(middle.words?.isEmpty ?? true)
        XCTAssertLessThanOrEqual(middle.conf, 0.5)
        assertValidTimings(result.sentences)
    }

    func testEmptyTranscriptLeavesEverySentenceUntimed() {
        let result = Matcher.align(
            sentences: [epubSentence(0, "Call me Ishmael.", paragraph: 0)],
            transcript: []
        )
        XCTAssertNil(result.sentences[0].startS)
        XCTAssertNil(result.sentences[0].endS)
        XCTAssertNil(result.sentences[0].words)
        XCTAssertEqual(result.sentences[0].conf, 0)
        XCTAssertEqual(result.coverage, 0)
    }

    private func makeSentences(count: Int) -> [EPUBSentence] {
        let vocabulary = ["albatross", "lantern", "harbor", "compass", "whaleboat", "horizon", "starboard", "weather", "current", "island", "captain", "sailor"]
        return (0..<count).map { i in
            let selected = (0..<8).map { vocabulary[($0 * 5 + i * 7) % vocabulary.count] + "\(i)" }
            return epubSentence(i, selected.joined(separator: " ") + ".", paragraph: i / 4)
        }
    }

    private func epubSentence(_ i: Int, _ text: String, paragraph: Int) -> EPUBSentence {
        EPUBSentence(
            i: i,
            text: text,
            chapter: 0,
            p: paragraph,
            epub: EPUBPosition(href: "chapter.xhtml", charStart: i * 100, charEnd: i * 100 + text.count)
        )
    }

    private func timedWords(_ text: String, step: Double) -> [TranscriptWord] {
        words(text).enumerated().map { index, word in
            TranscriptWord(w: word, s: Double(index) * step, e: Double(index + 1) * step)
        }
    }

    private func words(_ string: String) -> [String] {
        string.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private func assertValidTimings(_ sentences: [SyncSentence], file: StaticString = #filePath, line: UInt = #line) {
        var previousStart = -Double.infinity
        var previousEnd = -Double.infinity
        for sentence in sentences {
            XCTAssertTrue((0...1).contains(sentence.conf), file: file, line: line)
            guard let start = sentence.startS, let end = sentence.endS else { continue }
            XCTAssertGreaterThanOrEqual(start, previousStart, file: file, line: line)
            XCTAssertGreaterThanOrEqual(end, start, file: file, line: line)
            XCTAssertLessThanOrEqual(previousEnd - start, 0.25 + 1e-9, file: file, line: line)
            previousStart = start
            previousEnd = end
        }
    }
}

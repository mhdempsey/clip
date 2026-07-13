import Foundation
import XCTest
@testable import ClipCore

final class SyncModelsTests: XCTestCase {
    func testSchemaRoundTripsWithAuthoritativeKeys() throws {
        let sync = fixture()
        try sync.validate()

        let data = try JSONEncoder.clipSync.encode(sync)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let book = try XCTUnwrap(object["book"] as? [String: Any])
        let audio = try XCTUnwrap((object["audio"] as? [[String: Any]])?.first)
        let sentence = try XCTUnwrap((object["sentences"] as? [[String: Any]])?.first)
        let epub = try XCTUnwrap(sentence["epub"] as? [String: Any])

        XCTAssertNotNil(book["duration_s"])
        XCTAssertNotNil(audio["offset_s"])
        XCTAssertNotNil(sentence["start_s"])
        XCTAssertNotNil(epub["char_start"])
        XCTAssertEqual(try JSONDecoder.clipSync.decode(ClipBookSync.self, from: data), sync)
    }

    func testValidatorRejectsUnsortedSentenceIndices() {
        var sync = fixture()
        sync.sentences = [sync.sentences[1], sync.sentences[0]]
        XCTAssertThrowsError(try sync.validate()) { error in
            XCTAssertEqual(error as? SyncValidationError, .sentenceIndicesNotIncreasing)
        }
    }

    func testValidatorRejectsOverlapsBeyondTolerance() {
        var sync = fixture()
        sync.sentences[1].startS = 1.5
        XCTAssertThrowsError(try sync.validate()) { error in
            guard case .sentenceOverlap = error as? SyncValidationError else {
                return XCTFail("Expected sentenceOverlap, got \(error)")
            }
        }
    }

    func testValidatorAllowsTouchingAndSmallTimestampOverlap() throws {
        var sync = fixture()
        sync.sentences[1].startS = 1.8
        try sync.validate()
    }

    func testValidatorRejectsHalfTimedAndUntimedFields() {
        var sync = fixture()
        sync.sentences[0].endS = nil
        XCTAssertThrowsError(try sync.validate())

        sync = fixture()
        sync.sentences[0].startS = nil
        sync.sentences[0].endS = nil
        sync.sentences[0].words = nil
        sync.sentences[0].conf = 0.4
        XCTAssertThrowsError(try sync.validate()) { error in
            guard case .invalidUntimedSentence = error as? SyncValidationError else {
                return XCTFail("Expected invalidUntimedSentence, got \(error)")
            }
        }
    }

    func testValidatorRejectsBadConfidenceAndEPUBRange() {
        var sync = fixture()
        sync.sentences[0].conf = 1.01
        XCTAssertThrowsError(try sync.validate())

        sync = fixture()
        sync.sentences[0].epub.charEnd = sync.sentences[0].epub.charStart - 1
        XCTAssertThrowsError(try sync.validate())
    }

    func testMissingRequiredJSONFieldDoesNotDecode() throws {
        let json = #"{"version":1,"book":{"title":"Book"},"audio":[],"chapters":[],"sentences":[]}"#
        XCTAssertThrowsError(try JSONDecoder.clipSync.decode(ClipBookSync.self, from: Data(json.utf8)))
    }

    private func fixture() -> ClipBookSync {
        ClipBookSync(
            version: 1,
            book: SyncBook(
                title: "Moby-Dick",
                author: "Herman Melville",
                durationS: 20,
                aligner: AlignerInfo(
                    engine: "whisperkit",
                    model: "large-v3-turbo",
                    coverage: 1,
                    created: "2026-07-12"
                )
            ),
            audio: [SyncAudio(file: "audio/part01.m4a", offsetS: 0, durationS: 20)],
            chapters: [SyncChapter(title: "Chapter 1", startS: 0, epubHref: "ch01.xhtml")],
            sentences: [
                SyncSentence(
                    i: 0, startS: 0, endS: 2, text: "Call me Ishmael.", chapter: 0, p: 0,
                    epub: EPUBPosition(href: "ch01.xhtml", charStart: 10, charEnd: 26), conf: 1,
                    words: [TimedWord(w: "Call", s: 0, e: 0.5), TimedWord(w: "me", s: 0.5, e: 0.8), TimedWord(w: "Ishmael.", s: 0.8, e: 2)]
                ),
                SyncSentence(
                    i: 1, startS: 2, endS: 4, text: "Some years ago.", chapter: 0, p: 1,
                    epub: EPUBPosition(href: "ch01.xhtml", charStart: 30, charEnd: 45), conf: 1,
                    words: [TimedWord(w: "Some", s: 2, e: 2.5), TimedWord(w: "years", s: 2.5, e: 3), TimedWord(w: "ago.", s: 3, e: 4)]
                ),
            ]
        )
    }
}

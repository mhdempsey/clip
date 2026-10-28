import UIKit
import XCTest
@testable import Clip

@MainActor
final class ReaderLayoutTests: XCTestCase {
    func testSpokenHighlightRemainsVisibleWhenFollowingIsOff() throws {
        let sentence = SentenceRecord(bookId: "highlight", i: 0, startS: 0, endS: 10, text: "The spoken passage stays highlighted while browsing or paused.", chapter: 0, p: 0, conf: 1)
        let document = ReaderDocument(sentences: [sentence], chapterTitle: { _ in "Opening" })
        let controller = ReaderTextController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 550)
        var appearance = ReaderAppearance()
        appearance.mode = .scroll
        controller.configure(with: ReaderTextView(document: document, appearance: appearance, activeSentence: 0, following: false, navigation: nil,
            onToggleControls: {}, onManualMove: {}, onLocation: { _, _, _ in }, onHighlight: { _, _ in }, onPlay: { _ in }))
        let text = try XCTUnwrap(controller.view as? UITextView)
        let range = try XCTUnwrap(document.sentenceRanges[0])
        XCTAssertNotNil(text.textStorage.attribute(.backgroundColor, at: range.location, effectiveRange: nil))
    }

    func testUserScrollSeeksOnlyWhenItSettlesAndProgrammaticScrollingDoesNotSeek() throws {
        let document = ReaderDocument(sentences: (0..<80).map { index in
            SentenceRecord(bookId: "scroll", i: index, startS: Double(index * 10), endS: Double(index * 10 + 9), text: "Sentence \(index) follows the reader through the book.", chapter: 0, p: index, conf: 1)
        }, chapterTitle: { _ in "Opening" })
        let controller = ReaderTextController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 550)
        var appearance = ReaderAppearance()
        appearance.mode = .scroll
        var moves: [NSRange] = []
        controller.configure(with: ReaderTextView(document: document, appearance: appearance, activeSentence: 0, following: true, navigation: nil,
            onToggleControls: {}, onManualMove: {}, onLocation: { _, _, _ in }, onHighlight: { _, _ in }, onPlay: { _ in }, onReaderMove: { moves.append($0) }))
        let text = try XCTUnwrap(controller.view as? UITextView)
        text.layoutIfNeeded()
        text.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        controller.scrollViewDidScroll(text)
        XCTAssertTrue(moves.isEmpty)
        controller.scrollViewWillBeginDragging(text)
        text.setContentOffset(CGPoint(x: 0, y: 900), animated: false)
        controller.scrollViewDidScroll(text)
        XCTAssertTrue(moves.isEmpty, "Dragging must not repeatedly rebuild the audio queue")
        controller.scrollViewDidEndDragging(text, willDecelerate: true)
        XCTAssertTrue(moves.isEmpty)
        controller.scrollViewDidEndDecelerating(text)
        XCTAssertEqual(moves.count, 1)
        let move = try XCTUnwrap(moves.first)
        XCTAssertGreaterThan(move.location, 0)
        let sentence = try XCTUnwrap(document.playbackSentence(in: move))
        let settledOffset = text.contentOffset.y
        controller.configure(with: ReaderTextView(document: document, appearance: appearance, activeSentence: sentence.i, following: true, navigation: nil,
            onToggleControls: {}, onManualMove: {}, onLocation: { _, _, _ in }, onHighlight: { _, _ in }, onPlay: { _ in }))
        XCTAssertEqual(text.contentOffset.y, settledOffset, "Seeking audio to the visible text must not yank the reader back")
    }

    func testMarginsAlsoChangeTheCenteredIPadColumn() throws {
        let document = ReaderDocument(sentences: [SentenceRecord(bookId: "margins", i: 0, text: "The reader chooses the width of the page.", chapter: 0, p: 0, conf: 0)], chapterTitle: { _ in "Opening" })
        let controller = ReaderTextController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 834, height: 900)
        var appearance = ReaderAppearance()
        appearance.mode = .scroll
        func configure() {
            controller.configure(with: ReaderTextView(document: document, appearance: appearance, activeSentence: nil, following: false, navigation: nil,
                onToggleControls: {}, onManualMove: {}, onLocation: { _, _, _ in }, onHighlight: { _, _ in }, onPlay: { _ in }))
        }
        configure()
        let textView = try XCTUnwrap(controller.view as? UITextView)
        let originalMargin = textView.textContainerInset.left
        appearance.margin += 24
        configure()
        XCTAssertEqual(textView.textContainerInset.left - originalMargin, 24)
        XCTAssertEqual(textView.textContainerInset.right, textView.textContainerInset.left)
    }

    func testAudioFollowLeavesVisibleSentencesStill() throws {
        let sentences = (0..<60).map { index in
            SentenceRecord(bookId: "follow", i: index, text: "Sentence \(index) can stay still while it is being spoken.", chapter: 0, p: index / 3, conf: 1)
        }
        let document = ReaderDocument(sentences: sentences, chapterTitle: { _ in "Opening" })
        let controller = ReaderTextController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 550)
        var appearance = ReaderAppearance()
        appearance.mode = .scroll
        func configuration(active: Int) -> ReaderTextView {
            ReaderTextView(document: document, appearance: appearance, activeSentence: active, following: true, navigation: nil,
                onToggleControls: {}, onManualMove: {}, onLocation: { _, _, _ in }, onHighlight: { _, _ in }, onPlay: { _ in })
        }
        controller.configure(with: configuration(active: 0))
        controller.view.layoutIfNeeded()
        let textView = try XCTUnwrap(controller.view as? UITextView)
        let originalOffset = textView.contentOffset.y
        controller.configure(with: configuration(active: 2))
        XCTAssertEqual(textView.contentOffset.y, originalOffset)
        controller.configure(with: configuration(active: 40))
        XCTAssertGreaterThan(textView.contentOffset.y, originalOffset)
    }

    func testChangingTypeAndReadingModeKeepsTheVisiblePassage() async throws {
        let sentences = (0..<120).map { index in
            SentenceRecord(bookId: "layout", i: index, text: "Sentence \(index) keeps its place when the reader changes the type or turns a page.", chapter: 0, p: index / 3, conf: 0)
        }
        let document = ReaderDocument(sentences: sentences, chapterTitle: { _ in "Opening" })
        let controller = ReaderTextController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 550)
        let textView = try XCTUnwrap(controller.view as? UITextView)
        var location = 0
        var ready = expectation(description: "Initial page layout")
        let navigation = ReaderNavigation(character: document.passages[45].range.location)
        func configuration(_ appearance: ReaderAppearance) -> ReaderTextView {
            ReaderTextView(document: document, appearance: appearance, activeSentence: nil, following: false, navigation: navigation,
                onToggleControls: {}, onManualMove: {},
                onLocation: { character, _, count in
                    location = character
                    if appearance.mode == .scroll || count > 0 { ready.fulfill() }
                }, onHighlight: { _, _ in }, onPlay: { _ in })
        }

        var appearance = ReaderAppearance()
        controller.configure(with: configuration(appearance))
        controller.view.layoutIfNeeded()
        await fulfillment(of: [ready], timeout: 10)
        let firstLocation = location
        XCTAssertGreaterThan(firstLocation, 0)
        XCTAssertLessThanOrEqual(textView.contentSize.height, textView.bounds.height + 1)

        ready = expectation(description: "Reflowed page layout")
        appearance.textSize = 29
        controller.configure(with: configuration(appearance))
        await fulfillment(of: [ready], timeout: 10)
        XCTAssertLessThanOrEqual(location, firstLocation)
        XCTAssertGreaterThan(location + (textView.text as NSString).length, firstLocation)
        XCTAssertLessThanOrEqual(textView.contentSize.height, textView.bounds.height + 1)

        let pageLocation = location
        ready = expectation(description: "Continuous layout")
        appearance.mode = .scroll
        controller.configure(with: configuration(appearance))
        await fulfillment(of: [ready], timeout: 10)
        XCTAssertEqual(location, pageLocation)
        XCTAssertGreaterThan(textView.contentOffset.y, 0)
        XCTAssertTrue(textView.isScrollEnabled)
    }
}

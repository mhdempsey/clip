import UIKit
import XCTest
@testable import Clip

final class ReaderPaginationTests: XCTestCase {
    func testPagesCoverEveryCharacterExactlyOnceAtDifferentSizes() {
        let text = NSAttributedString(
            string: String(repeating: "A page holds a little of the story. Café 👩🏽‍🚀 stays intact.\n", count: 120),
            attributes: [.font: UIFont.systemFont(ofSize: 22)]
        )
        for size in [CGSize(width: 280, height: 480), CGSize(width: 550, height: 210)] {
            let pages = ReaderPaginator.ranges(in: text, size: size)
            XCTAssertGreaterThan(pages.count, 1)
            XCTAssertEqual(pages.first?.location, 0)
            XCTAssertEqual(pages.last.map(NSMaxRange), text.length)
            for index in pages.indices.dropFirst() {
                XCTAssertEqual(pages[index].location, NSMaxRange(pages[index - 1]))
            }
            let reconstructed = pages.map { text.attributedSubstring(from: $0).string }.joined()
            XCTAssertEqual(reconstructed, text.string)
        }
    }

    func testEmptyDocumentDoesNotCreateBlankPages() {
        XCTAssertTrue(ReaderPaginator.ranges(in: NSAttributedString(string: ""), size: CGSize(width: 300, height: 500)).isEmpty)
    }

    func testFullLengthBookPaginatesWithoutLosingTheEnding() {
        let text = NSAttributedString(string: String(repeating: "Every sentence stays readable as the book unfolds. ", count: 12_500), attributes: [.font: UIFont.systemFont(ofSize: 22)])
        let started = Date()
        let pages = ReaderPaginator.ranges(in: text, size: CGSize(width: 327, height: 550))
        XCTAssertGreaterThan(pages.count, 300)
        XCTAssertEqual(pages.last.map(NSMaxRange), text.length)
        print("Full-length reader layout: \(pages.count) pages in \(Date().timeIntervalSince(started)) seconds")
    }

    func testOversizedTextRequestsScrollingFallbackInsteadOfPartialPages() {
        let text = NSMutableAttributedString(string: "Heading\n", attributes: [.font: UIFont.systemFont(ofSize: 12)])
        text.append(NSAttributedString(string: "Large accessible text", attributes: [.font: UIFont.systemFont(ofSize: 150)]))
        XCTAssertTrue(ReaderPaginator.ranges(in: text, size: CGSize(width: 280, height: 60)).isEmpty)
    }
}

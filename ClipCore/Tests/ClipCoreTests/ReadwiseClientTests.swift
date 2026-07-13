import XCTest
@testable import ClipCore

final class ReadwiseClientTests: XCTestCase {
    func testStatusClassification() {
        XCTAssertEqual(ReadwiseClient.classify(statusCode: 200), .sent)
        XCTAssertEqual(ReadwiseClient.classify(statusCode: 204), .sent)
        XCTAssertEqual(ReadwiseClient.classify(statusCode: 401), .invalidToken)
        XCTAssertEqual(ReadwiseClient.classify(statusCode: 429), .retryable)
        XCTAssertEqual(ReadwiseClient.classify(statusCode: 500), .retryable)
        XCTAssertEqual(ReadwiseClient.classify(statusCode: 599), .retryable)
        XCTAssertEqual(ReadwiseClient.classify(statusCode: 400), .permanentFailure(statusCode: 400))
    }

    func testHighlightPayloadUsesReadwiseContract() throws {
        let highlight = ReadwiseHighlight(
            text: "Call me Ishmael.",
            title: "Moby-Dick",
            author: "Herman Melville",
            location: 12,
            note: "audio @ 4:32:18",
            highlightedAt: Date(timeIntervalSince1970: 0)
        )
        let data = try JSONEncoder.readwise.encode(ReadwiseHighlightRequest(highlights: [highlight]))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let item = try XCTUnwrap((root["highlights"] as? [[String: Any]])?.first)

        XCTAssertEqual(item["source_type"] as? String, "clip")
        XCTAssertEqual(item["category"] as? String, "books")
        XCTAssertEqual(item["location_type"] as? String, "order")
        XCTAssertEqual(item["location"] as? Int, 12)
        XCTAssertNotNil(item["highlighted_at"])
    }
}

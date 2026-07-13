import XCTest
@testable import ClipCore

final class SharedContractsTests: XCTestCase {
    func testClipWindowValidationUsesFixedProductValues() {
        for value in [10, 15, 20, 30] {
            XCTAssertEqual(ClipShared.validatedClipWindow(value), value)
        }
        XCTAssertEqual(ClipShared.validatedClipWindow(0), 15)
        XCTAssertEqual(ClipShared.validatedClipWindow(25), 15)
    }

    func testAudioTimeFormatting() {
        XCTAssertEqual(ClipShared.formattedAudioTime(-2), "0:00")
        XCTAssertEqual(ClipShared.formattedAudioTime(.nan), "0:00")
        XCTAssertEqual(ClipShared.formattedAudioTime(272.4), "4:32")
        XCTAssertEqual(ClipShared.formattedAudioTime(16_338), "4:32:18")
    }
}

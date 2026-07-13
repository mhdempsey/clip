import XCTest
@testable import ClipCore

final class NumberSpellerTests: XCTestCase {
    func testCardinalTable() {
        let cases: [(Int, String)] = [
            (0, "zero"), (9, "nine"), (10, "ten"), (19, "nineteen"),
            (20, "twenty"), (42, "forty-two"), (100, "one hundred"),
            (105, "one hundred five"), (999, "nine hundred ninety-nine"),
            (1_000, "one thousand"), (1_001, "one thousand one"),
            (42_019, "forty-two thousand nineteen"),
            (999_999, "nine hundred ninety-nine thousand nine hundred ninety-nine"),
        ]

        for (number, expected) in cases {
            XCTAssertEqual(NumberSpeller.spell(number), expected, "Failed for \(number)")
        }
    }

    func testOrdinals() {
        let cases = [
            "1st": "first", "2nd": "second", "3rd": "third", "4th": "fourth",
            "11th": "eleventh", "12th": "twelfth", "13th": "thirteenth",
            "21st": "twenty-first", "100th": "one hundredth", "1001st": "one thousand first",
        ]
        for (token, expected) in cases {
            XCTAssertEqual(NumberSpeller.spellToken(token), expected, "Failed for \(token)")
        }
    }

    func testFourDigitYearsAreSpokenAsPairs() {
        XCTAssertEqual(NumberSpeller.spellToken("1984"), "nineteen eighty-four")
        XCTAssertEqual(NumberSpeller.spellToken("1905"), "nineteen oh-five")
        XCTAssertEqual(NumberSpeller.spellToken("2001"), "twenty oh-one")
        XCTAssertEqual(NumberSpeller.spellToken("1000"), "one thousand")
    }

    func testOutOfRangeAndMalformedTokensAreIgnored() {
        XCTAssertNil(NumberSpeller.spell(-1))
        XCTAssertNil(NumberSpeller.spell(1_000_000))
        XCTAssertNil(NumberSpeller.spellToken("12rd"))
        XCTAssertNil(NumberSpeller.spellToken("1,000,000"))
    }
}

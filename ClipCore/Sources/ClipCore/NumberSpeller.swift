import Foundation

public enum NumberSpeller {
    private static let small = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    public static func spell(_ number: Int) -> String? {
        guard (0...999_999).contains(number) else { return nil }
        if number < 20 { return small[number] }
        if number < 100 {
            let remainder = number % 10
            return tens[number / 10] + (remainder == 0 ? "" : "-\(small[remainder])")
        }
        if number < 1_000 {
            let remainder = number % 100
            return "\(small[number / 100]) hundred" + (remainder == 0 ? "" : " \(spell(remainder)!)")
        }
        let remainder = number % 1_000
        return "\(spell(number / 1_000)!) thousand" + (remainder == 0 ? "" : " \(spell(remainder)!)")
    }

    public static func spellToken(_ token: String) -> String? {
        let lower = token.lowercased()
        if let ordinal = parseOrdinal(lower) { return spellOrdinal(ordinal) }
        guard lower.allSatisfy(\.isNumber), let number = Int(lower), (0...999_999).contains(number) else { return nil }
        if lower.count == 4, number != 1_000, (1_001...2_099).contains(number) {
            let first = number / 100
            let second = number % 100
            guard let firstWords = spell(first) else { return nil }
            if second == 0 { return "\(firstWords) hundred" }
            if second < 10 { return "\(firstWords) oh-\(small[second])" }
            return "\(firstWords) \(spell(second)!)"
        }
        return spell(number)
    }

    public static func spellOrdinal(_ number: Int) -> String? {
        guard (0...999_999).contains(number), let cardinal = spell(number) else { return nil }
        if number == 0 { return "zeroth" }
        if number.isMultiple(of: 1_000) {
            return String(cardinal.dropLast("thousand".count)) + "thousandth"
        }
        if number.isMultiple(of: 100) {
            return String(cardinal.dropLast("hundred".count)) + "hundredth"
        }

        let replacements = [
            "one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
            "nine": "ninth", "twelve": "twelfth", "twenty": "twentieth", "thirty": "thirtieth",
            "forty": "fortieth", "fifty": "fiftieth", "sixty": "sixtieth", "seventy": "seventieth",
            "eighty": "eightieth", "ninety": "ninetieth",
        ]
        for (word, ordinal) in replacements where cardinal.hasSuffix(word) {
            return String(cardinal.dropLast(word.count)) + ordinal
        }
        return cardinal + "th"
    }

    private static func parseOrdinal(_ token: String) -> Int? {
        let suffixes = ["st", "nd", "rd", "th"]
        guard let suffix = suffixes.first(where: token.hasSuffix) else { return nil }
        let digits = String(token.dropLast(2))
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Int(digits) else { return nil }
        let modulo100 = value % 100
        let expected: String
        if (11...13).contains(modulo100) {
            expected = "th"
        } else {
            expected = switch value % 10 { case 1: "st"; case 2: "nd"; case 3: "rd"; default: "th" }
        }
        return suffix == expected ? value : nil
    }
}

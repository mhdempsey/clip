import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public struct SentenceSpan: Equatable, Sendable {
    public var text: String
    public var range: Range<Int>

    public init(text: String, range: Range<Int>) {
        self.text = text
        self.range = range
    }
}

public enum SentenceSplitter {
    private static let guardedAbbreviations = ["mr.", "mrs.", "dr.", "st.", "vs.", "e.g.", "i.e.", "etc."]

    public static func split(_ text: String) -> [SentenceSpan] {
        guard text.contains(where: { !$0.isWhitespace }) else { return [] }
        let rawRanges: [Range<String.Index>]
        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var naturalRanges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            naturalRanges.append(range)
            return true
        }
        rawRanges = naturalRanges.isEmpty ? fallbackRanges(text) : naturalRanges
        #else
        rawRanges = fallbackRanges(text)
        #endif

        var merged: [Range<String.Index>] = []
        for range in rawRanges {
            if let last = merged.last, endsInGuardedAbbreviation(String(text[last])) {
                merged[merged.count - 1] = last.lowerBound..<range.upperBound
            } else {
                merged.append(range)
            }
        }

        return merged.compactMap { trimmedRange($0, in: text) }.map { range in
            SentenceSpan(
                text: String(text[range]),
                range: text.distance(from: text.startIndex, to: range.lowerBound)..<text.distance(from: text.startIndex, to: range.upperBound)
            )
        }
    }

    private static func endsInGuardedAbbreviation(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return guardedAbbreviations.contains(where: trimmed.hasSuffix)
    }

    private static func fallbackRanges(_ text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if ".!?".contains(character), next == text.endIndex || text[next].isWhitespace {
                let candidate = start..<next
                if !endsInGuardedAbbreviation(String(text[candidate])) {
                    result.append(candidate)
                    start = next
                }
            }
            index = next
        }
        if start < text.endIndex { result.append(start..<text.endIndex) }
        return result
    }

    private static func trimmedRange(_ range: Range<String.Index>, in text: String) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace { lower = text.index(after: lower) }
        while upper > lower {
            let before = text.index(before: upper)
            guard text[before].isWhitespace else { break }
            upper = before
        }
        return lower < upper ? lower..<upper : nil
    }
}

import Foundation

public struct MatchResult: Equatable, Sendable {
    public var sentences: [SyncSentence]
    public var coverage: Double

    public init(sentences: [SyncSentence], coverage: Double) {
        self.sentences = sentences
        self.coverage = coverage
    }
}

public enum Matcher {
    private struct BookToken {
        var value: String
        var sentenceOffset: Int
    }

    private struct TranscriptToken {
        var value: String
        var transcriptOffset: Int
    }

    private struct Anchor {
        var book: Int
        var transcript: Int
        var length: Int
    }

    public static func normalize(_ token: String) -> [String] {
        let folded = token
            .decomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let trimmed = folded.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
        if let number = NumberSpeller.spellToken(trimmed) {
            return number.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map(String.init)
        }
        let cleaned = String(trimmed.filter { $0.isLetter || $0.isNumber })
        return cleaned.isEmpty ? [] : [cleaned]
    }

    public static func align(sentences: [EPUBSentence], transcript: [TranscriptWord]) -> MatchResult {
        guard !sentences.isEmpty else { return MatchResult(sentences: [], coverage: 1) }
        guard !transcript.isEmpty else {
            return MatchResult(sentences: sentences.map(untimedSentence), coverage: 0)
        }

        var bookTokens: [BookToken] = []
        var sentenceTokenCounts = Array(repeating: 0, count: sentences.count)
        for (sentenceOffset, sentence) in sentences.enumerated() {
            for word in rawWords(sentence.text) {
                for normalized in normalize(word) {
                    bookTokens.append(BookToken(value: normalized, sentenceOffset: sentenceOffset))
                    sentenceTokenCounts[sentenceOffset] += 1
                }
            }
        }
        var transcriptTokens: [TranscriptToken] = []
        for (offset, word) in transcript.enumerated() {
            for normalized in normalize(word.w) {
                transcriptTokens.append(TranscriptToken(value: normalized, transcriptOffset: offset))
            }
        }
        guard !bookTokens.isEmpty, !transcriptTokens.isEmpty else {
            return MatchResult(sentences: sentences.map(untimedSentence), coverage: 0)
        }

        let bookValues = bookTokens.map(\.value)
        let transcriptValues = transcriptTokens.map(\.value)
        var mapping: [Int: Int] = [:]
        alignRange(
            book: bookValues,
            transcript: transcriptValues,
            bookRange: 0..<bookValues.count,
            transcriptRange: 0..<transcriptValues.count,
            gramLength: 6,
            into: &mapping
        )

        var matchedTokensBySentence = Array(repeating: 0, count: sentences.count)
        var transcriptOffsetsBySentence = Array(repeating: Set<Int>(), count: sentences.count)
        for (bookOffset, transcriptTokenOffset) in mapping {
            guard bookValues[bookOffset] == transcriptValues[transcriptTokenOffset] || similar(bookValues[bookOffset], transcriptValues[transcriptTokenOffset]) else { continue }
            let token = bookTokens[bookOffset]
            matchedTokensBySentence[token.sentenceOffset] += 1
            transcriptOffsetsBySentence[token.sentenceOffset].insert(transcriptTokens[transcriptTokenOffset].transcriptOffset)
        }

        var result: [SyncSentence] = []
        result.reserveCapacity(sentences.count)
        for offset in sentences.indices {
            let source = sentences[offset]
            let transcriptOffsets = transcriptOffsetsBySentence[offset].sorted()
            guard let first = transcriptOffsets.first, let last = transcriptOffsets.last else {
                result.append(untimedSentence(source))
                continue
            }
            let words = transcriptOffsets.map { TimedWord(w: transcript[$0].w, s: transcript[$0].s, e: transcript[$0].e) }
            let denominator = max(1, sentenceTokenCounts[offset])
            result.append(SyncSentence(
                i: source.i,
                startS: transcript[first].s,
                endS: transcript[last].e,
                text: source.text,
                chapter: source.chapter,
                p: source.p,
                epub: source.epub,
                conf: min(1, Double(matchedTokensBySentence[offset]) / Double(denominator)),
                words: words
            ))
        }

        interpolateIsolatedSentences(&result)
        enforceNonOverlap(&result)
        let timedCount = result.lazy.filter(\.isTimed).count
        return MatchResult(sentences: result, coverage: Double(timedCount) / Double(result.count))
    }

    private static func alignRange(
        book: [String],
        transcript: [String],
        bookRange: Range<Int>,
        transcriptRange: Range<Int>,
        gramLength: Int,
        into mapping: inout [Int: Int]
    ) {
        guard !bookRange.isEmpty, !transcriptRange.isEmpty else { return }
        let anchors = monotonicAnchors(book: book, transcript: transcript, bookRange: bookRange, transcriptRange: transcriptRange, length: gramLength)
        if !anchors.isEmpty {
            var bookCursor = bookRange.lowerBound
            var transcriptCursor = transcriptRange.lowerBound
            for anchor in anchors {
                alignRange(
                    book: book,
                    transcript: transcript,
                    bookRange: bookCursor..<anchor.book,
                    transcriptRange: transcriptCursor..<anchor.transcript,
                    gramLength: 4,
                    into: &mapping
                )
                for delta in 0..<anchor.length {
                    mapping[anchor.book + delta] = anchor.transcript + delta
                }
                bookCursor = anchor.book + anchor.length
                transcriptCursor = anchor.transcript + anchor.length
            }
            alignRange(book: book, transcript: transcript, bookRange: bookCursor..<bookRange.upperBound, transcriptRange: transcriptCursor..<transcriptRange.upperBound, gramLength: 4, into: &mapping)
            return
        }

        if bookRange.count <= 4_000, transcriptRange.count <= 4_000 {
            needlemanWunsch(book: book, transcript: transcript, bookRange: bookRange, transcriptRange: transcriptRange, into: &mapping)
            return
        }

        // A pathological window with no unique 4-gram is divided proportionally so memory stays bounded.
        let bookMiddle = bookRange.lowerBound + min(4_000, bookRange.count / 2)
        let ratio = Double(bookMiddle - bookRange.lowerBound) / Double(bookRange.count)
        let transcriptMiddle = min(
            transcriptRange.upperBound,
            transcriptRange.lowerBound + max(1, Int((Double(transcriptRange.count) * ratio).rounded()))
        )
        alignRange(book: book, transcript: transcript, bookRange: bookRange.lowerBound..<bookMiddle, transcriptRange: transcriptRange.lowerBound..<transcriptMiddle, gramLength: 4, into: &mapping)
        alignRange(book: book, transcript: transcript, bookRange: bookMiddle..<bookRange.upperBound, transcriptRange: transcriptMiddle..<transcriptRange.upperBound, gramLength: 4, into: &mapping)
    }

    private static func monotonicAnchors(
        book: [String],
        transcript: [String],
        bookRange: Range<Int>,
        transcriptRange: Range<Int>,
        length: Int
    ) -> [Anchor] {
        guard length > 0, bookRange.count >= length, transcriptRange.count >= length else { return [] }
        var bookWindows: [String: [Int]] = [:]
        var transcriptWindows: [String: [Int]] = [:]
        for offset in bookRange.lowerBound...(bookRange.upperBound - length) {
            bookWindows[gramKey(book, offset, length), default: []].append(offset)
        }
        for offset in transcriptRange.lowerBound...(transcriptRange.upperBound - length) {
            transcriptWindows[gramKey(transcript, offset, length), default: []].append(offset)
        }
        var candidates: [Anchor] = []
        for (key, positions) in bookWindows where positions.count == 1 {
            guard let transcriptPositions = transcriptWindows[key], transcriptPositions.count == 1 else { continue }
            candidates.append(Anchor(book: positions[0], transcript: transcriptPositions[0], length: length))
        }
        candidates.sort { $0.book == $1.book ? $0.transcript < $1.transcript : $0.book < $1.book }
        guard !candidates.isEmpty else { return [] }

        var tails: [Int] = []
        var tailIndices: [Int] = []
        var predecessors = Array(repeating: -1, count: candidates.count)
        for index in candidates.indices {
            let value = candidates[index].transcript
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if tails[middle] < value { low = middle + 1 } else { high = middle }
            }
            if low == tails.count {
                tails.append(value)
                tailIndices.append(index)
            } else {
                tails[low] = value
                tailIndices[low] = index
            }
            if low > 0 { predecessors[index] = tailIndices[low - 1] }
        }
        var lis: [Anchor] = []
        var cursor = tailIndices.last ?? -1
        while cursor >= 0 {
            lis.append(candidates[cursor])
            cursor = predecessors[cursor]
        }
        lis.reverse()

        var nonOverlapping: [Anchor] = []
        for anchor in lis {
            if let last = nonOverlapping.last,
               anchor.book < last.book + length || anchor.transcript < last.transcript + length {
                continue
            }
            nonOverlapping.append(anchor)
        }
        return nonOverlapping
    }

    private static func needlemanWunsch(
        book: [String],
        transcript: [String],
        bookRange: Range<Int>,
        transcriptRange: Range<Int>,
        into mapping: inout [Int: Int]
    ) {
        let rows = bookRange.count
        let columns = transcriptRange.count
        guard rows > 0, columns > 0 else { return }
        let width = columns + 1
        var directions = [UInt8](repeating: 0, count: (rows + 1) * width)
        var previous = [Int32](repeating: 0, count: width)
        var current = [Int32](repeating: 0, count: width)
        for column in 1...columns { previous[column] = -Int32(column); directions[column] = 3 }

        for row in 1...rows {
            current[0] = -Int32(row)
            directions[row * width] = 2
            let bookToken = book[bookRange.lowerBound + row - 1]
            for column in 1...columns {
                let transcriptToken = transcript[transcriptRange.lowerBound + column - 1]
                let tokenScore: Int32 = bookToken == transcriptToken ? 2 : (similar(bookToken, transcriptToken) ? 1 : -1)
                let diagonal = previous[column - 1] + tokenScore
                let up = previous[column] - 1
                let left = current[column - 1] - 1
                if diagonal >= up, diagonal >= left {
                    current[column] = diagonal
                    directions[row * width + column] = 1
                } else if up >= left {
                    current[column] = up
                    directions[row * width + column] = 2
                } else {
                    current[column] = left
                    directions[row * width + column] = 3
                }
            }
            swap(&previous, &current)
        }

        var row = rows
        var column = columns
        while row > 0 || column > 0 {
            let direction = directions[row * width + column]
            if direction == 1, row > 0, column > 0 {
                let bookOffset = bookRange.lowerBound + row - 1
                let transcriptOffset = transcriptRange.lowerBound + column - 1
                if book[bookOffset] == transcript[transcriptOffset] || similar(book[bookOffset], transcript[transcriptOffset]) {
                    mapping[bookOffset] = transcriptOffset
                }
                row -= 1
                column -= 1
            } else if direction == 2, row > 0 {
                row -= 1
            } else if column > 0 {
                column -= 1
            } else {
                break
            }
        }
    }

    private static func similar(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs != rhs, !lhs.isEmpty, !rhs.isEmpty else { return lhs == rhs }
        let left = Array(lhs)
        let right = Array(rhs)
        let maximum = max(left.count, right.count)
        // With a 0.85 threshold, no non-identical token shorter than seven
        // characters can survive even one edit.
        guard maximum >= 7 else { return false }
        if abs(left.count - right.count) > Int(Double(maximum) * 0.15) { return false }
        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[right.count]) / Double(maximum) >= 0.85
    }

    private static func interpolateIsolatedSentences(_ sentences: inout [SyncSentence]) {
        guard sentences.count >= 3 else { return }
        for index in 1..<(sentences.count - 1) where !sentences[index].isTimed {
            guard sentences[index - 1].isTimed, sentences[index + 1].isTimed,
                  sentences[index - 1].chapter == sentences[index].chapter,
                  sentences[index + 1].chapter == sentences[index].chapter,
                  let left = sentences[index - 1].endS,
                  let right = sentences[index + 1].startS,
                  right >= left, right - left <= 30
            else { continue }
            let raw = rawWords(sentences[index].text)
            guard !raw.isEmpty else { continue }
            let step = (right - left) / Double(raw.count)
            sentences[index].startS = left
            sentences[index].endS = right
            sentences[index].conf = min(sentences[index - 1].conf, sentences[index + 1].conf) * 0.5
            sentences[index].words = raw.enumerated().map { offset, word in
                TimedWord(w: word, s: left + Double(offset) * step, e: left + Double(offset + 1) * step)
            }
        }
    }

    private static func enforceNonOverlap(_ sentences: inout [SyncSentence]) {
        var previousIndex: Int?
        for index in sentences.indices where sentences[index].isTimed {
            if let previousIndex,
               let previousEnd = sentences[previousIndex].endS,
               let currentStart = sentences[index].startS,
               previousEnd > currentStart {
                let boundary = (previousEnd + currentStart) / 2
                sentences[previousIndex].endS = boundary
                if var words = sentences[previousIndex].words, !words.isEmpty {
                    words[words.count - 1].e = boundary
                    sentences[previousIndex].words = words
                }
                sentences[index].startS = boundary
                if var words = sentences[index].words, !words.isEmpty {
                    words[0].s = boundary
                    sentences[index].words = words
                }
            }
            previousIndex = index
        }
    }

    private static func untimedSentence(_ sentence: EPUBSentence) -> SyncSentence {
        SyncSentence(i: sentence.i, startS: nil, endS: nil, text: sentence.text, chapter: sentence.chapter, p: sentence.p, epub: sentence.epub, conf: 0, words: nil)
    }

    private static func rawWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func gramKey(_ tokens: [String], _ start: Int, _ length: Int) -> String {
        tokens[start..<(start + length)].joined(separator: "\u{1F}")
    }
}

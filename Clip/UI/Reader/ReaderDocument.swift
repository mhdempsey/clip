import Foundation

/// TextKit uses UTF-16 offsets. Keep sentence identity separate from display text,
/// including when the same passage occurs more than once in a book.
struct ReaderDocument: Sendable {
    let id = UUID()
    struct Passage: Sendable {
        let sentence: SentenceRecord
        let range: NSRange
    }
    struct Chapter: Identifiable, Sendable {
        let id: Int
        let title: String
        let range: NSRange
    }
    struct SearchMatch: Identifiable, Sendable {
        let range: NSRange
        let snippet: String
        let chapterTitle: String?
        var id: Int { range.location }
    }

    let text: String
    let utf16Length: Int
    let passages: [Passage]
    let chapters: [Chapter]
    let sentenceRanges: [Int: NSRange]
    private let timedSentences: [SentenceRecord]

    init(sentences: [SentenceRecord], chapterTitle: (Int) -> String) {
        let text = NSMutableString()
        var passages: [Passage] = []
        var chapters: [Chapter] = []
        var previous: SentenceRecord?
        var seen = Set<Int>()
        for sentence in sentences.sorted(by: { $0.i < $1.i }) where seen.insert(sentence.i).inserted {
            let content = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            if previous?.chapter != sentence.chapter {
                if text.length > 0 { text.append("\n") }
                let title = chapterTitle(sentence.chapter)
                chapters.append(Chapter(id: sentence.chapter, title: title, range: NSRange(location: text.length, length: (title as NSString).length)))
                text.append(title + "\n")
            } else {
                text.append(previous?.p == sentence.p ? " " : "\n")
            }
            let range = NSRange(location: text.length, length: (content as NSString).length)
            text.append(content)
            passages.append(Passage(sentence: sentence, range: range))
            previous = sentence
        }
        self.text = text as String
        self.utf16Length = text.length
        self.passages = passages
        self.chapters = chapters
        self.sentenceRanges = Dictionary(uniqueKeysWithValues: passages.map { ($0.sentence.i, $0.range) })
        self.timedSentences = passages.map(\.sentence).filter(\.isTimed).sorted { ($0.startS ?? 0) < ($1.startS ?? 0) }
    }

    func passage(at character: Int) -> Passage? {
        var low = 0
        var high = passages.count
        while low < high {
            let middle = (low + high) / 2
            if passages[middle].range.location <= character { low = middle + 1 }
            else { high = middle }
        }
        guard low > 0 else { return nil }
        let result = passages[low - 1]
        return NSLocationInRange(character, result.range) ? result : nil
    }

    func sentenceIndices(in range: NSRange) -> ClosedRange<Int>? {
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        let selected = passages.filter { NSIntersectionRange($0.range, range).length > 0 }
        guard let first = selected.first, let last = selected.last else { return nil }
        return first.sentence.i...last.sentence.i
    }

    func playbackSentence(in range: NSRange) -> SentenceRecord? {
        passages.first { $0.sentence.isTimed && NSIntersectionRange($0.range, range).length > 0 }?.sentence
    }

    func activeSentence(at time: Double) -> Int? {
        var low = 0
        var high = timedSentences.count
        while low < high {
            let middle = (low + high) / 2
            if (timedSentences[middle].startS ?? .infinity) <= time { low = middle + 1 }
            else { high = middle }
        }
        guard low > 0 else { return timedSentences.first?.i }
        return timedSentences[low - 1].i
    }

    func search(_ query: String) -> [SearchMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let source = text as NSString
        var offset = 0
        var matches: [SearchMatch] = []
        while offset < source.length {
            let range = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: offset, length: source.length - offset))
            guard range.location != NSNotFound, range.length > 0 else { break }
            let start = max(0, range.location - 45)
            let end = min(source.length, NSMaxRange(range) + 65)
            let preview = source.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
            let snippet = (preview.location > 0 ? "…" : "") + source.substring(with: preview).replacingOccurrences(of: "\n", with: " ") + (NSMaxRange(preview) < source.length ? "…" : "")
            matches.append(SearchMatch(range: range, snippet: snippet, chapterTitle: chapters.last(where: { $0.range.location <= range.location })?.title))
            offset = NSMaxRange(range)
        }
        return matches
    }

    func clipRange(location: Int, text: String) -> NSRange? {
        guard let range = sentenceRanges[location] else { return nil }
        let exact = (self.text as NSString).range(of: text, options: [.caseInsensitive, .diacriticInsensitive], range: range)
        return exact.location == NSNotFound ? range : exact
    }
}

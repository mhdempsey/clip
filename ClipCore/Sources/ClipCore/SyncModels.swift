import Foundation

public struct ClipBookSync: Codable, Equatable, Sendable {
    public var version: Int
    public var book: SyncBook
    public var audio: [SyncAudio]
    public var chapters: [SyncChapter]
    public var sentences: [SyncSentence]

    public init(version: Int = 1, book: SyncBook, audio: [SyncAudio], chapters: [SyncChapter], sentences: [SyncSentence]) {
        self.version = version
        self.book = book
        self.audio = audio
        self.chapters = chapters
        self.sentences = sentences
    }

    public func validate() throws {
        guard version == 1 else { throw SyncValidationError.unsupportedVersion(version) }
        guard !book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              book.durationS.isFinite, book.durationS >= 0,
              (0...1).contains(book.aligner.coverage)
        else { throw SyncValidationError.invalidBook }

        var previousAudioEnd = 0.0
        for (index, item) in audio.enumerated() {
            guard !item.file.isEmpty, !item.file.hasPrefix("/"),
                  item.offsetS.isFinite, item.durationS.isFinite,
                  item.offsetS >= 0, item.durationS >= 0
            else { throw SyncValidationError.invalidAudio(index: index) }
            guard index == 0 ? abs(item.offsetS) < 0.001 : item.offsetS + 0.001 >= previousAudioEnd else {
                throw SyncValidationError.invalidAudio(index: index)
            }
            previousAudioEnd = item.offsetS + item.durationS
        }

        for (index, chapter) in chapters.enumerated() {
            guard !chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !chapter.epubHref.isEmpty,
                  chapter.startS.isFinite, chapter.startS >= 0
            else { throw SyncValidationError.invalidChapter(index: index) }
        }

        var previousIndex: Int?
        var previousTimedStart = -Double.infinity
        var previousTimedEnd = -Double.infinity
        for sentence in sentences {
            if let previousIndex, sentence.i <= previousIndex {
                throw SyncValidationError.sentenceIndicesNotIncreasing
            }
            previousIndex = sentence.i
            guard sentence.i >= 0, sentence.p >= 0,
                  sentence.chapter >= 0, sentence.chapter < chapters.count,
                  !sentence.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !sentence.epub.href.isEmpty,
                  sentence.epub.charStart >= 0,
                  sentence.epub.charEnd >= sentence.epub.charStart,
                  sentence.conf.isFinite, (0...1).contains(sentence.conf)
            else { throw SyncValidationError.invalidSentence(index: sentence.i) }

            switch (sentence.startS, sentence.endS, sentence.words) {
            case (nil, nil, nil):
                guard sentence.conf == 0 else {
                    throw SyncValidationError.invalidUntimedSentence(index: sentence.i)
                }
            case let (.some(start), .some(end), .some(words)):
                guard start.isFinite, end.isFinite, start >= 0, end >= start,
                      !words.isEmpty, sentence.conf >= 0
                else { throw SyncValidationError.invalidTimedSentence(index: sentence.i) }
                guard start >= previousTimedStart else {
                    throw SyncValidationError.timedSentencesNotMonotonic(index: sentence.i)
                }
                if previousTimedEnd - start > 0.25 + 1e-9 {
                    throw SyncValidationError.sentenceOverlap(previousEnd: previousTimedEnd, start: start)
                }
                for word in words {
                    guard !word.w.isEmpty, word.s.isFinite, word.e.isFinite,
                          word.s >= 0, word.e >= word.s
                    else { throw SyncValidationError.invalidWord(sentence: sentence.i) }
                }
                previousTimedStart = start
                previousTimedEnd = end
            default:
                throw SyncValidationError.incompleteTiming(index: sentence.i)
            }
        }
    }
}

public struct SyncBook: Codable, Equatable, Sendable {
    public var title: String
    public var author: String
    public var durationS: Double
    public var aligner: AlignerInfo

    public init(title: String, author: String, durationS: Double, aligner: AlignerInfo) {
        self.title = title
        self.author = author
        self.durationS = durationS
        self.aligner = aligner
    }

    enum CodingKeys: String, CodingKey { case title, author, aligner; case durationS = "duration_s" }
}

public struct AlignerInfo: Codable, Equatable, Sendable {
    public var engine: String
    public var model: String
    public var coverage: Double
    public var created: String

    public init(engine: String, model: String, coverage: Double, created: String) {
        self.engine = engine
        self.model = model
        self.coverage = coverage
        self.created = created
    }
}

public struct SyncAudio: Codable, Equatable, Sendable {
    public var file: String
    public var offsetS: Double
    public var durationS: Double

    public init(file: String, offsetS: Double, durationS: Double) {
        self.file = file
        self.offsetS = offsetS
        self.durationS = durationS
    }

    enum CodingKeys: String, CodingKey { case file; case offsetS = "offset_s"; case durationS = "duration_s" }
}

public struct SyncChapter: Codable, Equatable, Sendable {
    public var title: String
    public var startS: Double
    public var epubHref: String

    public init(title: String, startS: Double, epubHref: String) {
        self.title = title
        self.startS = startS
        self.epubHref = epubHref
    }

    enum CodingKeys: String, CodingKey { case title; case startS = "start_s"; case epubHref = "epub_href" }
}

public struct SyncSentence: Codable, Equatable, Sendable, Identifiable {
    public var i: Int
    public var startS: Double?
    public var endS: Double?
    public var text: String
    public var chapter: Int
    public var p: Int
    public var epub: EPUBPosition
    public var conf: Double
    public var words: [TimedWord]?

    public var id: Int { i }
    public var isTimed: Bool { startS != nil && endS != nil }

    public init(i: Int, startS: Double?, endS: Double?, text: String, chapter: Int, p: Int, epub: EPUBPosition, conf: Double, words: [TimedWord]?) {
        self.i = i
        self.startS = startS
        self.endS = endS
        self.text = text
        self.chapter = chapter
        self.p = p
        self.epub = epub
        self.conf = conf
        self.words = words
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(i, forKey: .i)
        if let startS { try container.encode(startS, forKey: .startS) }
        else { try container.encodeNil(forKey: .startS) }
        if let endS { try container.encode(endS, forKey: .endS) }
        else { try container.encodeNil(forKey: .endS) }
        try container.encode(text, forKey: .text)
        try container.encode(chapter, forKey: .chapter)
        try container.encode(p, forKey: .p)
        try container.encode(epub, forKey: .epub)
        try container.encode(conf, forKey: .conf)
        if let words { try container.encode(words, forKey: .words) }
        else { try container.encodeNil(forKey: .words) }
    }

    enum CodingKeys: String, CodingKey {
        case i, text, chapter, p, epub, conf, words
        case startS = "start_s"
        case endS = "end_s"
    }
}

public struct EPUBPosition: Codable, Equatable, Sendable {
    public var href: String
    public var charStart: Int
    public var charEnd: Int

    public init(href: String, charStart: Int, charEnd: Int) {
        self.href = href
        self.charStart = charStart
        self.charEnd = charEnd
    }

    enum CodingKeys: String, CodingKey { case href; case charStart = "char_start"; case charEnd = "char_end" }
}

public struct TimedWord: Codable, Equatable, Sendable {
    public var w: String
    public var s: Double
    public var e: Double

    public init(w: String, s: Double, e: Double) {
        self.w = w
        self.s = s
        self.e = e
    }
}

public struct TranscriptWord: Codable, Equatable, Sendable {
    public var w: String
    public var s: Double
    public var e: Double

    public var text: String { w }
    public var startS: Double { s }
    public var endS: Double { e }

    public init(w: String, s: Double, e: Double) {
        self.w = w
        self.s = s
        self.e = e
    }

    public init(text: String, startS: Double, endS: Double) {
        self.init(w: text, s: startS, e: endS)
    }
}

public enum SyncValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case invalidBook
    case invalidAudio(index: Int)
    case invalidChapter(index: Int)
    case sentenceIndicesNotIncreasing
    case invalidSentence(index: Int)
    case incompleteTiming(index: Int)
    case invalidTimedSentence(index: Int)
    case invalidUntimedSentence(index: Int)
    case timedSentencesNotMonotonic(index: Int)
    case sentenceOverlap(previousEnd: Double, start: Double)
    case invalidWord(sentence: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version): "Unsupported sync version \(version)."
        case .invalidBook: "The book metadata is invalid."
        case let .invalidAudio(index): "Audio item \(index) is invalid."
        case let .invalidChapter(index): "Chapter \(index) is invalid."
        case .sentenceIndicesNotIncreasing: "Sentence indices must be strictly increasing."
        case let .invalidSentence(index): "Sentence \(index) is invalid."
        case let .incompleteTiming(index): "Sentence \(index) has incomplete timing fields."
        case let .invalidTimedSentence(index): "Timed sentence \(index) is invalid."
        case let .invalidUntimedSentence(index): "Untimed sentence \(index) must have nil timing and words, and zero confidence."
        case let .timedSentencesNotMonotonic(index): "Timed sentence \(index) is not monotonic."
        case .sentenceOverlap: "Sentence timings overlap by more than 0.25 seconds."
        case let .invalidWord(sentence): "Sentence \(sentence) contains invalid word timing."
        }
    }
}

public extension JSONEncoder {
    static var clipSync: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {
    static var clipSync: JSONDecoder { JSONDecoder() }
}

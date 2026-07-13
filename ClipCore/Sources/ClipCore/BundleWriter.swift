import Foundation

public struct BundleWriteResult: Equatable, Sendable {
    public var bundleURL: URL
    public var report: CoverageReport

    public init(bundleURL: URL, report: CoverageReport) {
        self.bundleURL = bundleURL
        self.report = report
    }
}

public struct CoverageReport: Codable, Equatable, Sendable {
    public var sentenceCoverage: Double
    public var untimedSpans: [UntimedSpan]
    public var chapters: [ChapterCoverage]

    public init(sentenceCoverage: Double, untimedSpans: [UntimedSpan], chapters: [ChapterCoverage]) {
        self.sentenceCoverage = sentenceCoverage
        self.untimedSpans = untimedSpans
        self.chapters = chapters
    }

    public static func compute(from sync: ClipBookSync) -> CoverageReport {
        let timed = sync.sentences.lazy.filter(\.isTimed).count
        let sentenceCoverage = sync.sentences.isEmpty ? 1 : Double(timed) / Double(sync.sentences.count)
        var untimedSpans: [UntimedSpan] = []
        var cursor = 0
        while cursor < sync.sentences.count {
            guard !sync.sentences[cursor].isTimed else { cursor += 1; continue }
            let lower = cursor
            while cursor + 1 < sync.sentences.count, !sync.sentences[cursor + 1].isTimed { cursor += 1 }
            let upper = cursor
            let previousEnd = lower > 0 ? sync.sentences[lower - 1].endS ?? 0 : 0
            let nextStart = upper + 1 < sync.sentences.count ? sync.sentences[upper + 1].startS : nil
            let end = nextStart ?? sync.book.durationS
            let duration = max(0, end - previousEnd)
            if duration > 60 {
                untimedSpans.append(UntimedSpan(
                    startSentenceI: sync.sentences[lower].i,
                    endSentenceI: sync.sentences[upper].i,
                    startS: previousEnd,
                    endS: end,
                    durationS: duration
                ))
            }
            cursor += 1
        }
        var chapterFirst = [Double?](repeating: nil, count: sync.chapters.count)
        var chapterLast = [Double?](repeating: nil, count: sync.chapters.count)
        for sentence in sync.sentences where sync.chapters.indices.contains(sentence.chapter) {
            if chapterFirst[sentence.chapter] == nil, let start = sentence.startS {
                chapterFirst[sentence.chapter] = start
            }
            if let end = sentence.endS { chapterLast[sentence.chapter] = end }
        }
        let chapterCoverage = sync.chapters.enumerated().map { chapter, info in
            return ChapterCoverage(
                chapter: chapter,
                title: info.title,
                firstTimestamp: chapterFirst[chapter],
                lastTimestamp: chapterLast[chapter]
            )
        }
        return CoverageReport(sentenceCoverage: sentenceCoverage, untimedSpans: untimedSpans, chapters: chapterCoverage)
    }
}

public struct UntimedSpan: Codable, Equatable, Sendable {
    public var startSentenceI: Int
    public var endSentenceI: Int
    public var startS: Double
    public var endS: Double
    public var durationS: Double

    public init(startSentenceI: Int, endSentenceI: Int, startS: Double, endS: Double, durationS: Double) {
        self.startSentenceI = startSentenceI
        self.endSentenceI = endSentenceI
        self.startS = startS
        self.endS = endS
        self.durationS = durationS
    }
}

public struct ChapterCoverage: Codable, Equatable, Sendable {
    public var chapter: Int
    public var title: String
    public var firstTimestamp: Double?
    public var lastTimestamp: Double?

    public init(chapter: Int, title: String, firstTimestamp: Double?, lastTimestamp: Double?) {
        self.chapter = chapter
        self.title = title
        self.firstTimestamp = firstTimestamp
        self.lastTimestamp = lastTimestamp
    }
}

public enum BundleWriterError: Error, LocalizedError, Sendable {
    case missingAudio
    case audioCountMismatch(expected: Int, actual: Int)
    case duplicateAudioFilename(String)

    public var errorDescription: String? {
        switch self {
        case .missingAudio: "No audiobook files were provided."
        case let .audioCountMismatch(expected, actual): "The sync metadata expects \(expected) audio files but received \(actual)."
        case let .duplicateAudioFilename(name): "More than one audio file is named \(name)."
        }
    }
}

public enum BundleWriter {
    @discardableResult
    public static func write(
        sync: ClipBookSync,
        audioFiles: [URL],
        sourceEPUB: URL,
        coverImage: Data?,
        to destination: URL
    ) async throws -> BundleWriteResult {
        try sync.validate()
        guard !audioFiles.isEmpty else { throw BundleWriterError.missingAudio }
        guard audioFiles.count == sync.audio.count else {
            throw BundleWriterError.audioCountMismatch(expected: sync.audio.count, actual: audioFiles.count)
        }

        let fileManager = FileManager.default
        let bundleURL: URL
        if destination.pathExtension.lowercased() == "clipbook" {
            bundleURL = destination
        } else {
            bundleURL = destination.appendingPathComponent("\(safeFilename(sync.book.title)).clipbook", isDirectory: true)
        }
        let parent = bundleURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let stagingURL = parent.appendingPathComponent(".\(bundleURL.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        var shouldCleanStaging = true
        defer { if shouldCleanStaging { try? fileManager.removeItem(at: stagingURL) } }

        let audioDirectory = stagingURL.appendingPathComponent("audio", isDirectory: true)
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let sortedAudio = audioFiles.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var usedNames: Set<String> = []
        for source in sortedAudio {
            let filename = source.lastPathComponent
            guard usedNames.insert(filename.lowercased()).inserted else { throw BundleWriterError.duplicateAudioFilename(filename) }
            try fileManager.copyItem(at: source, to: audioDirectory.appendingPathComponent(filename))
        }
        try fileManager.copyItem(at: sourceEPUB, to: stagingURL.appendingPathComponent("source.epub"))
        if let coverImage { try coverImage.write(to: stagingURL.appendingPathComponent("cover.jpg"), options: .atomic) }
        let syncData = try JSONEncoder.clipSync.encode(sync)
        try syncData.write(to: stagingURL.appendingPathComponent("sync.json"), options: .atomic)

        if fileManager.fileExists(atPath: bundleURL.path) {
            _ = try fileManager.replaceItemAt(bundleURL, withItemAt: stagingURL, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: stagingURL, to: bundleURL)
        }
        shouldCleanStaging = false
        return BundleWriteResult(bundleURL: bundleURL, report: CoverageReport.compute(from: sync))
    }

    private static func safeFilename(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = title.components(separatedBy: forbidden).filter { !$0.isEmpty }
        let safe = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "Untitled" : safe
    }
}

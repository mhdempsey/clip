import ClipCore
import Foundation

enum AlignmentPipelineUpdate {
    case stage(AlignmentStage, detail: String, fraction: Double)
    case modelDownload(fraction: Double)
    case listening(fraction: Double, cacheHit: Bool)
}

enum AlignmentPipeline {
    static func run(
        source: PairingSnapshot,
        quality: AlignmentQuality,
        transcriber: WhisperTranscriber,
        update: @escaping @Sendable (AlignmentPipelineUpdate) -> Void
    ) async throws -> CompletedAlignment {
        update(.stage(.preparing, detail: "Reading the book and checking the audio.", fraction: 0.02))
        let epub = try EPUBReader.read(from: source.epubURL)

        var durations: [TimeInterval] = []
        var totalDuration: TimeInterval = 0
        for (index, audio) in source.audio.enumerated() {
            let duration: TimeInterval
            if let knownDuration = audio.duration {
                duration = knownDuration
            } else {
                duration = try await AudioMetadataService.read(audio.url).duration
            }
            durations.append(duration)
            totalDuration += duration
            let fraction = 0.02 + 0.04 * (Double(index + 1) / Double(source.audio.count))
            update(.stage(.preparing, detail: "Checking \(audio.url.lastPathComponent).", fraction: fraction))
        }

        let preparedAudio = zip(source.audio, durations).map { audio, duration in
            AudioSource(id: audio.id, url: audio.url, duration: duration)
        }
        let heardWords = try await transcriber.transcribe(audio: preparedAudio, quality: quality) { transcriptionUpdate in
            switch transcriptionUpdate.phase {
            case .cacheLookup:
                update(.stage(.preparing, detail: "Looking for an earlier listening pass.", fraction: 0.07))
            case .modelDownload:
                update(.modelDownload(fraction: transcriptionUpdate.fraction))
            case .listening:
                update(.listening(fraction: transcriptionUpdate.fraction, cacheHit: transcriptionUpdate.cacheHit))
            }
        }

        update(.stage(.matching, detail: "Setting the printed words beside the spoken ones.", fraction: 0.96))
        let transcript = heardWords.map {
            TranscriptWord(w: $0.text, s: $0.start, e: $0.end)
        }
        let match = Matcher.align(sentences: epub.sentences, transcript: transcript)

        var offset: TimeInterval = 0
        let syncAudio = zip(source.audio, durations).map { audio, duration -> SyncAudio in
            defer { offset += duration }
            return SyncAudio(
                file: "audio/\(audio.url.lastPathComponent)",
                offsetS: offset,
                durationS: duration
            )
        }

        var priorChapterStart: TimeInterval = 0
        let syncChapters = epub.chapters.enumerated().map { index, chapter -> SyncChapter in
            let firstTimed = match.sentences.first { sentence in
                sentence.chapter == index && sentence.startS != nil
            }?.startS
            let start = firstTimed ?? priorChapterStart
            priorChapterStart = start
            return SyncChapter(title: chapter.title, startS: start, epubHref: chapter.href)
        }

        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let sync = ClipBookSync(
            version: 1,
            book: SyncBook(
                title: source.title,
                author: source.author,
                durationS: totalDuration,
                aligner: AlignerInfo(
                    engine: "whisperkit",
                    model: quality.modelName,
                    coverage: match.coverage,
                    created: String(date)
                )
            ),
            audio: syncAudio,
            chapters: syncChapters,
            sentences: match.sentences
        )
        try sync.validate()

        update(.stage(.writing, detail: "Placing the finished book on your shelf.", fraction: 0.985))
        let destination = try DestinationService.destination()
        let result = try await BundleWriter.write(
            sync: sync,
            audioFiles: source.audio.map(\.url),
            sourceEPUB: source.epubURL,
            coverImage: source.coverData ?? epub.coverData,
            to: destination.documentsURL
        )

        let unmatched = result.report.untimedSpans
            .sorted { $0.durationS > $1.durationS }
            .map { UnmatchedSpanSummary(start: $0.startS, end: $0.endS) }
        return CompletedAlignment(
            bundleURL: result.bundleURL,
            coverage: result.report.sentenceCoverage,
            unmatchedSpans: unmatched,
            usedICloud: destination.usesICloud
        )
    }
}

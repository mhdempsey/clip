import Foundation

enum AlignmentQuality: String, CaseIterable, Identifiable, Codable {
    case standard
    case maximum
    case fastTest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .maximum: "Maximum"
        case .fastTest: "Fast test"
        }
    }

    var explanation: String {
        switch self {
        case .standard: "The best balance for most books."
        case .maximum: "Takes longer and listens most carefully."
        case .fastTest: "A quick pass for checking a book pair."
        }
    }

    var modelName: String {
        switch self {
        case .standard: "large-v3-turbo"
        case .maximum: "large-v3"
        case .fastTest: "base"
        }
    }

    /// The expected processing fraction used only for a friendly estimate.
    var estimatedRealtimeFactor: Double {
        switch self {
        case .standard: 1 / 30
        case .maximum: 1 / 15
        case .fastTest: 1 / 60
        }
    }
}

struct AudioSource: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var duration: TimeInterval?

    init(id: UUID = UUID(), url: URL, duration: TimeInterval? = nil) {
        self.id = id
        self.url = url
        self.duration = duration
    }

}

struct PairingSnapshot {
    let epubURL: URL
    let audio: [AudioSource]
    let title: String
    let author: String
    let coverData: Data?
}

@MainActor
final class PairingDraft: ObservableObject {
    @Published var epubURL: URL?
    @Published var audio: [AudioSource] = []
    @Published var title = ""
    @Published var author = ""
    @Published var coverData: Data?
    @Published var inlineMessage: String?
    @Published var isReadingMetadata = false
    var metadataWasEdited = false

    var canAlign: Bool {
        epubURL != nil && !audio.isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pairStatus: String {
        switch (epubURL != nil, audio.isEmpty) {
        case (false, true): "Step 1 of 4 · Add both files"
        case (true, true): "Ebook added · Now add the audiobook"
        case (false, false): "Audiobook added · Now add the ebook"
        case (true, false): "Step 2 of 4 · Check the order, then click Align"
        }
    }

    func snapshot() -> PairingSnapshot? {
        guard let epubURL else { return nil }
        return PairingSnapshot(
            epubURL: epubURL,
            audio: audio,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            coverData: coverData
        )
    }

    func reset() {
        epubURL = nil
        audio = []
        title = ""
        author = ""
        coverData = nil
        inlineMessage = nil
        isReadingMetadata = false
        metadataWasEdited = false
    }
}

enum AlignmentStage: Equatable {
    case waiting
    case preparing
    case downloadingModel
    case listening
    case matching
    case writing
    case done
    case failed

    var label: String {
        switch self {
        case .waiting: "Waiting"
        case .preparing: "Preparing"
        case .downloadingModel: "Preparing"
        case .listening: "Listening…"
        case .matching: "Matching"
        case .writing: "Writing"
        case .done: "Done"
        case .failed: "Needs attention"
        }
    }

    var isActive: Bool {
        switch self {
        case .preparing, .downloadingModel, .listening, .matching, .writing: true
        default: false
        }
    }
}

struct UnmatchedSpanSummary: Identifiable, Codable, Hashable {
    var id: String { "\(start)-\(end)" }
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { max(0, end - start) }
}

struct CompletedAlignment {
    let bundleURL: URL
    let coverage: Double
    let unmatchedSpans: [UnmatchedSpanSummary]
    let usedICloud: Bool
}

@MainActor
final class AlignmentJob: ObservableObject, Identifiable {
    let id = UUID()
    let source: PairingSnapshot
    let quality: AlignmentQuality

    @Published var stage: AlignmentStage = .waiting
    @Published var progress: Double = 0
    @Published var detail = "Queued behind the current book."
    @Published var estimatedRemaining: TimeInterval?
    @Published var modelDownloadProgress: Double?
    @Published var completed: CompletedAlignment?
    @Published var errorMessage: String?
    @Published var detailsExpanded = false

    var estimatedTotal: TimeInterval?

    init(source: PairingSnapshot, quality: AlignmentQuality) {
        self.source = source
        self.quality = quality
    }

    var title: String { source.title }

    var progressLabel: String {
        switch stage {
        case .listening where progress > 0 && progress < 0.01: "Listening <1%"
        case .listening: "Listening \(Int(progress * 100))%"
        case .downloadingModel: "Preparing \(Int((modelDownloadProgress ?? 0) * 100))%"
        default: stage.label
        }
    }
}

struct ShelfBook: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let duration: TimeInterval
    let coverage: Double
    let bundleURL: URL
    let coverURL: URL?
    let modifiedAt: Date?
}

enum MacAppError: LocalizedError {
    case unsupportedFiles
    case missingPair
    case unreadableAudio(String)
    case noTranscript(String)
    case incompleteBookText(Double)
    case malformedBundle

    var errorDescription: String? {
        switch self {
        case .unsupportedFiles:
            "Clip can use an EPUB with MP3, M4A, or M4B audio."
        case .missingPair:
            "Add one EPUB and at least one audio file first."
        case let .unreadableAudio(name):
            "Clip couldn’t read the duration of \(name)."
        case let .noTranscript(name):
            "Clip couldn’t hear any spoken words in \(name)."
        case let .incompleteBookText(coverage):
            "Clip found reliable ebook text for only \(Int((coverage * 100).rounded()))% of the audio. The EPUB may be incomplete or damaged; try another copy."
        case .malformedBundle:
            "This Clip book is missing some of its information."
        }
    }
}

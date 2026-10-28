import AppKit
import ClipCore
import Foundation

enum MainSection {
    case align
    case shelf
}

@MainActor
final class ClipMacModel: ObservableObject {
    static let shared = ClipMacModel()

    @Published var section: MainSection = .align
    let draft = PairingDraft()
    @Published var jobs: [AlignmentJob] = []
    @Published var shelf: [ShelfBook] = []
    @Published var quality: AlignmentQuality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: Self.qualityKey) }
    }
    @Published var alignmentLocation: AlignmentLocation {
        didSet { UserDefaults.standard.set(alignmentLocation.rawValue, forKey: "Clip.AlignmentLocation") }
    }
    @Published var cloudSpendingLimitUSD: Double {
        didSet { UserDefaults.standard.set(cloudSpendingLimitUSD, forKey: "Clip.CloudSpendingLimitUSD") }
    }
    @Published var hasOpenRouterKey = false
    @Published var credentialMessage: String?
    @Published var cloudConfirmation: CloudAlignmentRequest?
    @Published var isPreparingCloud = false
    @Published var shelfMessage: String?

    private static let qualityKey = "Clip.AlignmentQuality"
    private let transcriber = WhisperTranscriber()
    private let cloudTranscriber = OpenRouterTranscriber()
    private let shelfService = ShelfService()
    private let activityKeeper = ActivityKeeper()
    private var processingTask: Task<Void, Never>?
    private var userReorderedAudio = false

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.qualityKey)
        quality = AlignmentQuality(rawValue: stored ?? "") ?? .standard
        alignmentLocation = AlignmentLocation(rawValue: UserDefaults.standard.string(forKey: "Clip.AlignmentLocation") ?? "") ?? .onMac
        cloudSpendingLimitUSD = UserDefaults.standard.object(forKey: "Clip.CloudSpendingLimitUSD") as? Double ?? 5
        do { hasOpenRouterKey = try OpenRouterCredentials.containsKey() }
        catch { credentialMessage = error.localizedDescription }
        ClipMacUITestFixture.installIfRequested(draft: draft)
        Task { await refreshShelf() }
    }

    var hasRunningJob: Bool { jobs.contains { $0.stage.isActive } }

    func saveOpenRouterKey(_ key: String) -> Bool {
        do {
            try OpenRouterCredentials.save(key)
            hasOpenRouterKey = true
            credentialMessage = "Key saved in this Mac’s Keychain."
            return true
        } catch {
            credentialMessage = error.localizedDescription
            return false
        }
    }

    func removeOpenRouterKey() {
        do {
            try OpenRouterCredentials.remove()
            hasOpenRouterKey = false
            credentialMessage = "OpenRouter key removed."
        } catch {
            credentialMessage = error.localizedDescription
        }
    }

    func chooseFiles() {
        addFiles(FileIngestionService.chooseFiles())
    }

    func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let urls = await FileIngestionService.fileURLs(from: providers)
            addFiles(urls)
        }
        return true
    }

    func addFiles(_ urls: [URL]) {
        addFiles(urls, preserveAudioOrder: false)
    }

    private func addFiles(_ urls: [URL], preserveAudioOrder: Bool) {
        let supported = urls.filter { $0.isSupportedEPUB || $0.isSupportedAudio }
        guard !supported.isEmpty else {
            draft.inlineMessage = MacAppError.unsupportedFiles.localizedDescription
            return
        }

        let epubs = supported.filter(\.isSupportedEPUB)
        if let epub = epubs.first {
            if epubs.count > 1 {
                draft.inlineMessage = "Clip needs one book at a time. Using \(epub.lastPathComponent); you can drop the other one next."
            } else if let current = draft.epubURL, current != epub {
                draft.inlineMessage = "Replaced \(current.lastPathComponent) with \(epub.lastPathComponent)."
            } else {
                draft.inlineMessage = nil
            }
            draft.epubURL = epub
            loadEPUBMetadata(epub)
        }

        let existing = Set(draft.audio.map { $0.url.standardizedFileURL })
        let newAudio = supported
            .filter(\.isSupportedAudio)
            .filter { !existing.contains($0.standardizedFileURL) }
            .map { AudioSource(url: $0) }
        if !newAudio.isEmpty {
            draft.audio.append(contentsOf: newAudio)
            if !userReorderedAudio, !preserveAudioOrder { draft.audio = draft.audio.naturallySorted() }
            if preserveAudioOrder { userReorderedAudio = true }
            loadAudioMetadata(for: newAudio)
        }
    }

    func removeAudio(_ source: AudioSource) {
        draft.audio.removeAll { $0.id == source.id }
    }

    func moveAudio(from sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = draft.audio.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = draft.audio.firstIndex(where: { $0.id == targetID }) else { return }
        let item = draft.audio.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        draft.audio.insert(item, at: adjustedTarget)
        userReorderedAudio = true
    }

    func enqueueAlignment() {
        guard draft.canAlign, let source = draft.snapshot() else {
            draft.inlineMessage = MacAppError.missingPair.localizedDescription
            return
        }
        if alignmentLocation == .openRouter {
            prepareCloudAlignment(source: source, quality: quality)
        } else {
            enqueue(source: source, quality: quality, location: .onMac, spendingLimitUSD: 0)
        }
    }

    func confirmCloudAlignment() {
        guard let request = cloudConfirmation else { return }
        cloudConfirmation = nil
        if let id = request.retryingJobID { jobs.removeAll { $0.id == id } }
        enqueue(source: request.source, quality: request.quality, location: .openRouter, spendingLimitUSD: request.spendingLimitUSD)
    }

    func retry(_ job: AlignmentJob) {
        if job.location == .openRouter {
            prepareCloudAlignment(source: job.source, quality: job.quality, retryingJobID: job.id)
        } else {
            jobs.removeAll { $0.id == job.id }
            enqueue(source: job.source, quality: job.quality, location: .onMac, spendingLimitUSD: 0)
        }
    }

    private func prepareCloudAlignment(source: PairingSnapshot, quality: AlignmentQuality, retryingJobID: UUID? = nil) {
        guard !isPreparingCloud else { return }
        guard hasOpenRouterKey else {
            draft.inlineMessage = "Add your OpenRouter API key in Clip Settings before using cloud alignment."
            return
        }
        let limit = cloudSpendingLimitUSD
        guard limit.isFinite, limit > 0 else {
            draft.inlineMessage = "Set a spending limit greater than $0 in Clip Settings."
            return
        }
        isPreparingCloud = true
        Task {
            defer { isPreparingCloud = false }
            let scoped = source.audio.map(\.url).filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            do {
                var audio: [AudioSource] = []
                for item in source.audio {
                    let duration: TimeInterval
                    if let known = item.duration { duration = known }
                    else { duration = try await AudioMetadataService.read(item.url).duration }
                    guard duration.isFinite, duration > 0 else { throw MacAppError.unreadableAudio(item.url.lastPathComponent) }
                    audio.append(AudioSource(id: item.id, url: item.url, duration: duration))
                }
                cloudConfirmation = CloudAlignmentRequest(
                    source: PairingSnapshot(epubURL: source.epubURL, audio: audio, title: source.title, author: source.author, coverData: source.coverData),
                    quality: quality, spendingLimitUSD: limit, retryingJobID: retryingJobID
                )
            } catch {
                draft.inlineMessage = error.localizedDescription
            }
        }
    }

    private func enqueue(source: PairingSnapshot, quality: AlignmentQuality, location: AlignmentLocation, spendingLimitUSD: Double) {
        let job = AlignmentJob(source: source, quality: quality, location: location, spendingLimitUSD: spendingLimitUSD)
        jobs.insert(job, at: 0)
        if let current = draft.snapshot(), current.epubURL == source.epubURL,
           current.audio.map(\.url) == source.audio.map(\.url),
           current.title == source.title, current.author == source.author {
            draft.reset()
            userReorderedAudio = false
        }
        startQueueIfNeeded()
    }

    func dismiss(_ job: AlignmentJob) {
        guard !job.stage.isActive else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func reveal(_ url: URL) {
        shelfService.reveal(url)
    }

    func refreshShelf() async {
        do {
            shelf = try await shelfService.load()
            shelfMessage = nil
        } catch {
            shelfMessage = error.localizedDescription
        }
    }

    func remove(_ book: ShelfBook) {
        Task {
            do {
                try await shelfService.remove(book)
                await refreshShelf()
            } catch {
                shelfMessage = "Clip couldn’t remove that book: \(error.localizedDescription)"
            }
        }
    }

    func realign(_ book: ShelfBook) {
        Task {
            let bundleURL = book.bundleURL
            let orderedAudio = await Task.detached(priority: .userInitiated) {
                let syncURL = bundleURL.appendingPathComponent("sync.json")
                guard let data = try? Data(contentsOf: syncURL, options: .mappedIfSafe),
                      let sync = try? JSONDecoder.clipSync.decode(ClipBookSync.self, from: data)
                else { return [URL]() }
                return sync.audio
                    .map { bundleURL.appendingPathComponent($0.file) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
            }.value
            let audioDirectory = bundleURL.appendingPathComponent("audio", isDirectory: true)
            let fallbackAudio = (try? FileManager.default.contentsOfDirectory(
                at: audioDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.filter(\.isSupportedAudio) ?? []
            let audio = orderedAudio.isEmpty ? fallbackAudio : orderedAudio

            section = .align
            draft.reset()
            addFiles(
                [bundleURL.appendingPathComponent("source.epub")] + audio,
                preserveAudioOrder: !orderedAudio.isEmpty
            )
            draft.title = book.title
            draft.author = book.author
            draft.metadataWasEdited = true
            if let coverURL = book.coverURL { draft.coverData = try? Data(contentsOf: coverURL) }
        }
    }

    private func loadEPUBMetadata(_ url: URL) {
        draft.isReadingMetadata = true
        Task {
            defer { draft.isReadingMetadata = false }
            do {
                let preview = try await Task.detached { try EPUBReader.read(from: url) }.value
                guard draft.epubURL == url else { return }
                if !draft.metadataWasEdited {
                    if !preview.metadata.title.isEmpty { draft.title = preview.metadata.title }
                    if !preview.metadata.author.isEmpty { draft.author = preview.metadata.author }
                }
                if let cover = preview.coverData { draft.coverData = cover }
            } catch {
                draft.inlineMessage = "Got the book, but couldn’t read its details yet. You can fill them in below."
            }
        }
    }

    private func loadAudioMetadata(for sources: [AudioSource]) {
        Task {
            for source in sources {
                guard let metadata = try? await AudioMetadataService.read(source.url),
                      let index = draft.audio.firstIndex(where: { $0.id == source.id }) else { continue }
                draft.audio[index].duration = metadata.duration
                if !draft.metadataWasEdited {
                    if draft.title.isEmpty, let title = metadata.title { draft.title = title }
                    if draft.author.isEmpty, let author = metadata.author { draft.author = author }
                }
                if draft.coverData == nil, let artwork = metadata.artwork { draft.coverData = artwork }
            }
        }
    }

    private func startQueueIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            guard let self else { return }
            while let next = jobs.last(where: { $0.stage == .waiting }) {
                await process(next)
            }
            processingTask = nil
        }
    }

    private func process(_ job: AlignmentJob) async {
        let urls = [job.source.epubURL] + job.source.audio.map(\.url)
        let securityScoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { securityScoped.forEach { $0.stopAccessingSecurityScopedResource() } }

        activityKeeper.begin(for: job.title)
        defer { activityKeeper.end() }
        job.stage = .preparing
        job.detail = "Reading the book and checking the audio."
        job.progress = 0.02

        do {
            let totalDuration = job.source.audio.compactMap(\.duration).reduce(0, +)
            job.estimatedTotal = job.location == .onMac ? totalDuration * job.quality.estimatedRealtimeFactor : nil
            job.estimatedRemaining = job.estimatedTotal
            let apiKey = job.location == .openRouter ? try OpenRouterCredentials.load() : nil
            let result = try await AlignmentPipeline.run(
                source: job.source,
                quality: job.quality,
                transcriber: transcriber,
                cloudTranscriber: cloudTranscriber,
                location: job.location,
                apiKey: apiKey,
                spendingLimitUSD: job.spendingLimitUSD
            ) { update in
                Task { @MainActor in
                    if case let .cloudSpending(cost) = update {
                        job.cloudCostUSD = max(job.cloudCostUSD, cost)
                        return
                    }
                    guard job.stage != .done, job.stage != .failed else { return }
                    switch update {
                    case let .stage(stage, detail, fraction):
                        job.stage = stage
                        job.detail = detail
                        job.progress = fraction
                        if stage != .downloadingModel {
                            job.modelDownloadProgress = nil
                        }
                    case let .modelDownload(fraction):
                        job.stage = .downloadingModel
                        job.modelDownloadProgress = fraction
                        job.progress = min(0.08, fraction * 0.08)
                        job.detail = "Clip downloads its listening tools once. Everything stays private on your Mac."
                    case let .listening(fraction, cacheHit):
                        let priorListeningProgress = job.stage == .listening ? job.progress : 0
                        job.stage = .listening
                        job.progress = max(priorListeningProgress, fraction)
                        job.modelDownloadProgress = nil
                        if job.location == .openRouter {
                            job.detail = cacheHit ? "Using saved OpenRouter transcript chunks on this Mac." : "Transcribing audio with OpenRouter. Completed chunks are saved on this Mac."
                        } else {
                            job.detail = cacheHit ? "Using the private listening pass already on this Mac." : "Listening privately on this Mac."
                        }
                        if let estimate = job.estimatedTotal {
                            job.estimatedRemaining = max(0, estimate * (1 - fraction))
                        }
                    case .cloudSpending:
                        break
                    }
                }
            }
            job.completed = result
            job.stage = .done
            job.progress = 1
            job.detail = "In your \(result.usedICloud ? "iCloud" : "Documents") — ready for Clip on your iPhone."
            await refreshShelf()
        } catch {
            job.stage = .failed
            job.errorMessage = error.localizedDescription
            job.detail = job.location == .openRouter
                ? "Source files are unchanged. Retry to reuse saved chunks; OpenRouter may have charged for completed uploads."
                : "Nothing was changed. Check the files and try again."
        }
    }
}

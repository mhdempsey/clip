import AVFoundation
import ClipCore
import Combine
import Foundation

@MainActor
final class PlayerEngine: ObservableObject {
    static let shared = PlayerEngine()

    @Published private(set) var currentBook: BookRecord?
    @Published private(set) var globalTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: Double
    @Published private(set) var playbackError: String?

    var currentChapterTitle: String {
        manifest?.chapters.last(where: { $0.startS <= globalTime })?.title ?? ""
    }

    func chapterTitle(at index: Int) -> String {
        guard let chapters = manifest?.chapters, chapters.indices.contains(index) else {
            return "Chapter \(index + 1)"
        }
        let title = chapters[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Chapter \(index + 1)" : title
    }

    private let database: ClipDatabase
    private let defaults: UserDefaults
    private let player: AVQueuePlayer
    private let resourceLoader: BundleResourceLoader
    private let liveActivity = LiveActivityCoordinator()
    private var manifest: PlaybackManifest?
    private var itemOffsets: [ObjectIdentifier: Double] = [:]
    private var timeObserver: Any?
    private var playerObservation: NSKeyValueObservation?
    private var itemObservations: [NSKeyValueObservation] = []
    private var interruptionObserver: NSObjectProtocol?
    private var finishObserver: NSObjectProtocol?
    private var clipWindowObserver: NSObjectProtocol?
    private var externalPlaybackObserver: DarwinNotificationObservation?
    private var lastPersistedAt = Date.distantPast
    private var pendingSeekID: UUID?
    private var playbackRequested = false

    init(
        database: ClipDatabase = .shared,
        defaults: UserDefaults = AppGroup.defaults,
        player: AVQueuePlayer = AVQueuePlayer(),
        resourceLoader: BundleResourceLoader = BundleResourceLoader()
    ) {
        self.database = database
        self.defaults = defaults
        self.player = player
        self.resourceLoader = resourceLoader
        playbackRate = ClipShared.validatedPlaybackRate(
            defaults.double(forKey: AppGroup.Key.playbackRate)
        )
        player.defaultRate = Float(playbackRate)
        configureAudioSession()
        installObservers()
        NowPlaying.shared.installCommands(for: self)
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) }
        if let clipWindowObserver { NotificationCenter.default.removeObserver(clipWindowObserver) }
    }

    func load(_ book: BookRecord, autoplay: Bool = false) async {
        do {
            playbackError = nil
            let isCurrentBook = currentBook?.id == book.id
            let resumeTime = isCurrentBook ? globalTime : book.positionS
            let resumePlayback = isCurrentBook && playbackRequested
            if !isCurrentBook {
                pause()
            }
            let data = try await resourceLoader.data(
                at: try ClipBookBundle.resourceURL("sync.json", in: book.bundleFileURL),
                in: book.bundleFileURL
            ) { [weak self] in
                self?.playbackError = "Getting this audiobook ready…"
            }
            let loadedManifest = try JSONDecoder().decode(PlaybackManifest.self, from: data)
            try await prepareAudioFiles(in: loadedManifest, for: book)
            try Task.checkCancellation()
            manifest = loadedManifest
            currentBook = book
            globalTime = min(max(0, resumeTime), book.durationS)
            defaults.set(book.id, forKey: AppGroup.Key.currentBookID)
            defaults.set(globalTime, forKey: AppGroup.Key.currentPosition)
            positionQueue(at: globalTime, rebuilding: true)
            publishState(forceActivityUpdate: true)
            if autoplay || resumePlayback { play() }
        } catch {
            guard !Task.isCancelled else { return }
            playbackError = "This audiobook isn’t available yet. \(error.localizedDescription)"
        }
    }

    func play() {
        guard currentBook != nil, player.currentItem != nil else {
            playbackError = "This audiobook’s audio isn’t available yet."
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            playbackRequested = true
            player.play()
            updatePlayingState(true)
            Task { await ClipService.shared.flushPending() }
        } catch {
            playbackError = error.localizedDescription
        }
    }

    func pause() {
        playbackRequested = false
        player.pause()
        updatePlayingState(false)
        persistPosition()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func setPlaybackRate(_ rate: Double) {
        let validated = ClipShared.validatedPlaybackRate(rate)
        guard playbackRate != validated else { return }

        playbackRate = validated
        defaults.set(validated, forKey: AppGroup.Key.playbackRate)
        player.defaultRate = Float(validated)
        if player.timeControlStatus != .paused {
            player.rate = Float(validated)
        }
        publishState(forceActivityUpdate: false)
    }

    func skip(by seconds: Double) {
        seek(to: globalTime + seconds)
    }

    func seek(to time: Double) {
        guard time.isFinite, let book = currentBook else { return }
        let target = min(max(0, time), book.durationS)
        globalTime = target
        positionQueue(at: target)
        if playbackRequested { player.play() }
        persistPosition()
        publishState(forceActivityUpdate: true)
    }

    func sceneDidEnterBackground() {
        persistPosition()
    }

    /// Uses the interruption stamp when Siri has just ducked playback, preserving
    /// the point where the listener spoke rather than the later intent runtime.
    func clipAnchorTime() -> Double? {
        let stampedAt = defaults.double(forKey: AppGroup.Key.interruptionDate)
        let stampedPosition = defaults.double(forKey: AppGroup.Key.interruptionPosition)
        if stampedAt > 0, Date().timeIntervalSince1970 - stampedAt < 10 {
            return max(0, stampedPosition)
        }
        if currentBook != nil { return max(0, globalTime) }
        guard defaults.string(forKey: AppGroup.Key.currentBookID) != nil else { return nil }
        return max(0, defaults.double(forKey: AppGroup.Key.currentPosition))
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        playerObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.pendingSeekID == nil else { return }
                self.playbackRequested = player.timeControlStatus != .paused
                self.updatePlayingState(self.playbackRequested)
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        }
        finishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleItemFinished(notification.object as? AVPlayerItem) }
        }
        clipWindowObserver = NotificationCenter.default.addObserver(
            forName: .clipWindowDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.publishState(forceActivityUpdate: true) }
        }
        externalPlaybackObserver = DarwinNotificationObservation(
            name: ClipShared.DarwinNotification.playbackCommand
        ) { [weak self] in
            Task { @MainActor in self?.processExternalPlaybackCommand() }
        }
    }

    private func positionQueue(at global: Double, rebuilding: Bool = false) {
        guard let book = currentBook, let manifest, !manifest.audio.isEmpty else {
            pendingSeekID = nil
            player.removeAllItems()
            itemOffsets.removeAll()
            itemObservations.removeAll()
            return
        }
        let seekID = UUID()
        pendingSeekID = seekID
        let segmentIndex = manifest.audio.lastIndex(where: { $0.offsetS <= global }) ?? 0
        let segment = manifest.audio[segmentIndex]
        let currentOffset = player.currentItem.flatMap { itemOffsets[ObjectIdentifier($0)] }
        if rebuilding || currentOffset != segment.offsetS {
            player.removeAllItems()
            itemOffsets.removeAll()
            itemObservations.removeAll()
            for segment in manifest.audio[segmentIndex...] {
                guard let url = try? ClipBookBundle.resourceURL(segment.file, in: book.bundleFileURL) else {
                    pendingSeekID = nil
                    player.removeAllItems()
                    playbackError = ClipBookResourceError.unsafePath.localizedDescription
                    return
                }
                let item = AVPlayerItem(url: url)
                itemOffsets[ObjectIdentifier(item)] = segment.offsetS
                itemObservations.append(item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
                    guard let item else { return }
                    Task { @MainActor in self?.handleItemStatus(item) }
                })
                player.insert(item, after: nil)
            }
        }
        let local = min(max(0, global - segment.offsetS), segment.durationS)
        player.seek(to: CMTime(seconds: local, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.pendingSeekID == seekID else { return }
                self.pendingSeekID = nil
                if !finished { self.playbackError = "The audiobook couldn’t move to that position. Try again." }
            }
        }
    }

    private func prepareAudioFiles(in manifest: PlaybackManifest, for book: BookRecord) async throws {
        let urls = try manifest.audio.map { try ClipBookBundle.resourceURL($0.file, in: book.bundleFileURL) }
        guard !urls.isEmpty else { throw PlaybackPreparationError.missingAudio }

        let fileManager = FileManager.default
        var unavailable = ClipBookBundle.audioFilesRequiringDownload(urls)
        if !unavailable.isEmpty {
            guard fileManager.isUbiquitousItem(at: book.bundleFileURL) else {
                throw PlaybackPreparationError.missingAudio
            }
            playbackError = "Downloading audiobook audio from iCloud…"
            try fileManager.startDownloadingUbiquitousItem(at: book.bundleFileURL)
            for url in unavailable {
                try? fileManager.startDownloadingUbiquitousItem(at: url)
            }

            let deadline = Date().addingTimeInterval(300)
            while !unavailable.isEmpty {
                try Task.checkCancellation()
                guard Date() < deadline else { throw PlaybackPreparationError.downloadTimedOut }
                try await Task.sleep(for: .milliseconds(500))
                unavailable = ClipBookBundle.audioFilesRequiringDownload(unavailable)
            }
        }

        for url in urls {
            guard try await AVURLAsset(url: url).load(.isPlayable) else {
                throw PlaybackPreparationError.unplayableAudio(url.lastPathComponent)
            }
            try Task.checkCancellation()
        }
        playbackError = nil
    }

    private func handleItemStatus(_ item: AVPlayerItem) {
        guard itemOffsets[ObjectIdentifier(item)] != nil, item.status == .failed else { return }
        pendingSeekID = nil
        pause()
        let detail = item.error?.localizedDescription ?? "The audio file couldn’t be opened."
        playbackError = "This audiobook couldn’t play. \(detail)"
    }

    private func tick() {
        // AVPlayer can report the previous time (or zero for a new item) until
        // a seek completes. Keep accumulating skips from the requested target.
        if pendingSeekID == nil, let item = player.currentItem, let offset = itemOffsets[ObjectIdentifier(item)] {
            let local = item.currentTime().seconds
            if local.isFinite { globalTime = max(0, offset + local) }
        }
        processExternalPlaybackCommand()
        if Date().timeIntervalSince(lastPersistedAt) >= 5 { persistPosition() }
        publishState(forceActivityUpdate: false)
    }

    private func updatePlayingState(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        defaults.set(playing, forKey: AppGroup.Key.isPlaying)
        if !playing { persistPosition() }
        publishState(forceActivityUpdate: true)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            defaults.set(globalTime, forKey: AppGroup.Key.interruptionPosition)
            defaults.set(Date().timeIntervalSince1970, forKey: AppGroup.Key.interruptionDate)
            pause()
        case .ended:
            guard let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) else { return }
            play()
        @unknown default:
            break
        }
    }

    private func handleItemFinished(_ item: AVPlayerItem?) {
        guard pendingSeekID == nil, let item, let offset = itemOffsets[ObjectIdentifier(item)],
              player.items().isEmpty || offset == manifest?.audio.last?.offsetS,
              let book = currentBook else { return }
        globalTime = book.durationS
        playbackRequested = false
        updatePlayingState(false)
        liveActivity.end(elapsed: globalTime, duration: book.durationS)
    }

    private func processExternalPlaybackCommand() {
        guard let command = defaults.string(forKey: AppGroup.Key.playbackCommand) else { return }
        defaults.removeObject(forKey: AppGroup.Key.playbackCommand)
        switch command {
        case "play": play()
        case "pause": pause()
        default: togglePlayback()
        }
    }

    private func persistPosition() {
        guard let book = currentBook else { return }
        lastPersistedAt = Date()
        defaults.set(book.id, forKey: AppGroup.Key.currentBookID)
        defaults.set(globalTime, forKey: AppGroup.Key.currentPosition)
        do { try database.updatePosition(bookID: book.id, position: globalTime) }
        catch { playbackError = error.localizedDescription }
    }

    private func publishState(forceActivityUpdate: Bool) {
        NowPlaying.shared.update(
            book: currentBook,
            elapsed: globalTime,
            isPlaying: isPlaying,
            playbackRate: playbackRate
        )
        if let book = currentBook {
            ClipPlaybackSnapshot(bookID: book.id, position: globalTime, duration: book.durationS, rate: playbackRate, isPlaying: isPlaying).store(defaults: defaults)
            liveActivity.update(book: book, elapsed: globalTime, isPlaying: isPlaying, force: forceActivityUpdate)
        }
    }
}

private enum PlaybackPreparationError: LocalizedError {
    case missingAudio
    case downloadTimedOut
    case unplayableAudio(String)

    var errorDescription: String? {
        switch self {
        case .missingAudio:
            "One or more audio files are missing from this Clip book."
        case .downloadTimedOut:
            "The audio download is taking too long. Check your connection and try again."
        case let .unplayableAudio(filename):
            "\(filename) isn’t a playable audio file."
        }
    }
}

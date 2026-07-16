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

    init(
        database: ClipDatabase = .shared,
        defaults: UserDefaults = AppGroup.defaults,
        player: AVQueuePlayer = AVQueuePlayer()
    ) {
        self.database = database
        self.defaults = defaults
        self.player = player
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
            if !isCurrentBook {
                persistPosition()
                player.pause()
            }
            let data = try Data(
                contentsOf: book.bundleFileURL.appendingPathComponent("sync.json"),
                options: .mappedIfSafe
            )
            let loadedManifest = try JSONDecoder().decode(PlaybackManifest.self, from: data)
            try await prepareAudioFiles(in: loadedManifest, for: book)
            try Task.checkCancellation()
            manifest = loadedManifest
            currentBook = book
            globalTime = min(max(0, resumeTime), book.durationS)
            defaults.set(book.id, forKey: AppGroup.Key.currentBookID)
            defaults.set(globalTime, forKey: AppGroup.Key.currentPosition)
            rebuildQueue(at: globalTime)
            publishState(forceActivityUpdate: true)
            if autoplay { play() }
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
            player.play()
            Task { await ClipService.shared.flushPending() }
        } catch {
            playbackError = error.localizedDescription
        }
    }

    func pause() {
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
        guard let book = currentBook else { return }
        let target = min(max(0, time), book.durationS)
        let resume = isPlaying
        rebuildQueue(at: target)
        globalTime = target
        if resume { player.play() }
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
            Task { @MainActor in self?.updatePlayingState(player.timeControlStatus == .playing) }
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

    private func rebuildQueue(at global: Double) {
        guard let book = currentBook, let manifest, !manifest.audio.isEmpty else {
            player.removeAllItems()
            itemObservations.removeAll()
            return
        }
        let segmentIndex = manifest.audio.lastIndex(where: { $0.offsetS <= global }) ?? 0
        player.removeAllItems()
        itemOffsets.removeAll()
        itemObservations.removeAll()
        for segment in manifest.audio[segmentIndex...] {
            let url = book.bundleFileURL.appendingPathComponent(segment.file)
            let item = AVPlayerItem(url: url)
            itemOffsets[ObjectIdentifier(item)] = segment.offsetS
            itemObservations.append(item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
                guard let item else { return }
                Task { @MainActor in self?.handleItemStatus(item) }
            })
            player.insert(item, after: nil)
        }
        let segment = manifest.audio[segmentIndex]
        let local = min(max(0, global - segment.offsetS), segment.durationS)
        player.seek(to: CMTime(seconds: local, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func prepareAudioFiles(in manifest: PlaybackManifest, for book: BookRecord) async throws {
        let urls = manifest.audio.map { book.bundleFileURL.appendingPathComponent($0.file) }
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
        guard item.status == .failed else { return }
        player.pause()
        updatePlayingState(false)
        let detail = item.error?.localizedDescription ?? "The audio file couldn’t be opened."
        playbackError = "This audiobook couldn’t play. \(detail)"
    }

    private func tick() {
        if let item = player.currentItem, let offset = itemOffsets[ObjectIdentifier(item)] {
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
            persistPosition()
        case .ended:
            guard let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) else { return }
            play()
        @unknown default:
            break
        }
    }

    private func handleItemFinished(_ item: AVPlayerItem?) {
        guard let item, player.items().isEmpty || itemOffsets[ObjectIdentifier(item)] == manifest?.audio.last?.offsetS,
              let book = currentBook else { return }
        globalTime = book.durationS
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

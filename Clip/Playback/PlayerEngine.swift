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
    @Published private(set) var playbackError: String?

    var currentChapterTitle: String {
        manifest?.chapters.last(where: { $0.startS <= globalTime })?.title ?? ""
    }

    private let database: ClipDatabase
    private let player = AVQueuePlayer()
    private let liveActivity = LiveActivityCoordinator()
    private var manifest: PlaybackManifest?
    private var itemOffsets: [ObjectIdentifier: Double] = [:]
    private var timeObserver: Any?
    private var playerObservation: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var finishObserver: NSObjectProtocol?
    private var clipWindowObserver: NSObjectProtocol?
    private var externalPlaybackObserver: DarwinNotificationObservation?
    private var lastPersistedAt = Date.distantPast

    init(database: ClipDatabase = .shared) {
        self.database = database
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
            if currentBook?.id != book.id {
                persistPosition()
                let data = try Data(contentsOf: book.bundleFileURL.appendingPathComponent("sync.json"), options: .mappedIfSafe)
                manifest = try JSONDecoder().decode(PlaybackManifest.self, from: data)
                currentBook = book
                globalTime = min(max(0, book.positionS), book.durationS)
                AppGroup.defaults.set(book.id, forKey: AppGroup.Key.currentBookID)
                AppGroup.defaults.set(globalTime, forKey: AppGroup.Key.currentPosition)
                rebuildQueue(at: globalTime)
                publishState(forceActivityUpdate: true)
            }
            if autoplay { play() }
        } catch {
            playbackError = "This audiobook isn’t available yet. \(error.localizedDescription)"
        }
    }

    func play() {
        guard currentBook != nil else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            player.play()
            updatePlayingState(true)
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
        let defaults = AppGroup.defaults
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
            return
        }
        let segmentIndex = manifest.audio.lastIndex(where: { $0.offsetS <= global }) ?? 0
        player.removeAllItems()
        itemOffsets.removeAll()
        for segment in manifest.audio[segmentIndex...] {
            let url = book.bundleFileURL.appendingPathComponent(segment.file)
            let item = AVPlayerItem(url: url)
            itemOffsets[ObjectIdentifier(item)] = segment.offsetS
            player.insert(item, after: nil)
        }
        let segment = manifest.audio[segmentIndex]
        let local = min(max(0, global - segment.offsetS), segment.durationS)
        player.seek(to: CMTime(seconds: local, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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
        AppGroup.defaults.set(playing, forKey: AppGroup.Key.isPlaying)
        if !playing { persistPosition() }
        publishState(forceActivityUpdate: true)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            AppGroup.defaults.set(globalTime, forKey: AppGroup.Key.interruptionPosition)
            AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: AppGroup.Key.interruptionDate)
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
        let defaults = AppGroup.defaults
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
        AppGroup.defaults.set(book.id, forKey: AppGroup.Key.currentBookID)
        AppGroup.defaults.set(globalTime, forKey: AppGroup.Key.currentPosition)
        do { try database.updatePosition(bookID: book.id, position: globalTime) }
        catch { playbackError = error.localizedDescription }
    }

    private func publishState(forceActivityUpdate: Bool) {
        NowPlaying.shared.update(book: currentBook, elapsed: globalTime, isPlaying: isPlaying)
        if let book = currentBook {
            liveActivity.update(book: book, elapsed: globalTime, isPlaying: isPlaying, force: forceActivityUpdate)
        }
    }
}

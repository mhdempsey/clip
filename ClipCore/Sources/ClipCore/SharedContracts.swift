import Foundation

public enum ClipShared {
    public static let appGroupIdentifier = "group.com.michael.clip"
    public static let iCloudContainerIdentifier = "iCloud.com.michael.clip"
    public static let supportURL = URL(string: "https://mhdempsey.github.io/clip/support/")!
    public static let privacyPolicyURL = URL(string: "https://mhdempsey.github.io/clip/privacy/")!
    public static let supportedClipWindowSeconds = [10, 15, 20, 30]
    public static let defaultClipWindowSeconds = 15
    public static let playbackRateRange = 1.0...3.0
    public static let defaultPlaybackRate = 1.0

    public enum DefaultsKey {
        public static let currentBookID = "currentBookId"
        public static let currentPosition = "currentPositionS"
        public static let playbackRate = "playbackRate"
        public static let clipWindow = "clipWindowSeconds"
        public static let interruptionPosition = "lastInterruptionPositionS"
        public static let interruptionDate = "lastInterruptionWallTime"
        public static let isPlaying = "isPlaying"
        public static let playbackCommand = "playbackCommand"
        public static let clipCommandSequence = "clipCommandSequence"
        public static let handledClipCommandSequence = "handledClipCommandSequence"
        public static let importDates = "clipbookImportDates"
    }

    public enum DarwinNotification {
        public static let playbackCommand = "com.michael.clip.playback-command"
        public static let clipCommand = "com.michael.clip.clip-command"
    }

    public static func validatedClipWindow(_ value: Int) -> Int {
        supportedClipWindowSeconds.contains(value) ? value : defaultClipWindowSeconds
    }

    public static func validatedPlaybackRate(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPlaybackRate }
        return min(max(value, playbackRateRange.lowerBound), playbackRateRange.upperBound)
    }

    public static func formattedAudioTime(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = max(0, Int(value.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    public static func whisperKitRepositoryVariant(for modelName: String) -> String {
        let repositoryName = modelName.hasSuffix("-turbo")
            ? String(modelName.dropLast("-turbo".count)) + "_turbo"
            : modelName
        return repositoryName.hasPrefix("openai_whisper-")
            ? repositoryName
            : "openai_whisper-\(repositoryName)"
    }

    /// Chooses an optimized repository variant without asking WhisperKit to run
    /// a model that it marks unsupported on the current device.
    public static func whisperKitRepositoryVariant(
        for modelName: String,
        supportedModels: [String]
    ) -> String {
        let requested = whisperKitRepositoryVariant(for: modelName)
        guard !supportedModels.isEmpty else { return requested }

        let candidates: [String]
        switch modelName {
        case "large-v3-turbo":
            candidates = [
                "openai_whisper-large-v3-v20240930_turbo_632MB",
                "openai_whisper-large-v3_turbo_954MB",
                requested,
                "openai_whisper-large-v3-v20240930_626MB",
                "openai_whisper-large-v3_947MB",
                "openai_whisper-large-v3-v20240930",
                "openai_whisper-large-v3",
                "openai_whisper-base",
                "openai_whisper-tiny",
            ]
        case "large-v3":
            candidates = [
                requested,
                "openai_whisper-large-v3-v20240930",
                "openai_whisper-large-v3_947MB",
                "openai_whisper-large-v3-v20240930_626MB",
                "openai_whisper-base",
                "openai_whisper-tiny",
            ]
        default:
            candidates = [requested]
        }

        let supported = Set(supportedModels)
        return candidates.first(where: supported.contains) ?? requested
    }

    public static func transcriptionFraction(
        fileOffset: TimeInterval,
        fileDuration: TimeInterval,
        totalDuration: TimeInterval,
        activeWindowIndex: Double
    ) -> Double {
        guard totalDuration.isFinite, totalDuration > 0 else { return 0 }
        let safeOffset = fileOffset.isFinite ? max(0, fileOffset) : 0
        let safeFileDuration = fileDuration.isFinite ? max(0, fileDuration) : 0
        let safeWindowIndex = activeWindowIndex.isFinite ? max(0, activeWindowIndex) : 0
        let activeWindowSeconds = (safeWindowIndex + 1) * 30
        let heardSeconds = min(safeFileDuration, activeWindowSeconds)
        return min(0.995, max(0, (safeOffset + heardSeconds) / totalDuration))
    }
}

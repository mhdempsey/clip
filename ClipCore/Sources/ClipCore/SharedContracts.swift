import Foundation

public enum ClipShared {
    public static let appGroupIdentifier = "group.com.michael.clip"
    public static let iCloudContainerIdentifier = "iCloud.com.michael.clip"
    public static let supportedClipWindowSeconds = [10, 15, 20, 30]
    public static let defaultClipWindowSeconds = 15

    public enum DefaultsKey {
        public static let currentBookID = "currentBookId"
        public static let currentPosition = "currentPositionS"
        public static let clipWindow = "clipWindowSeconds"
        public static let interruptionPosition = "lastInterruptionPositionS"
        public static let interruptionDate = "lastInterruptionWallTime"
        public static let isPlaying = "isPlaying"
        public static let playbackCommand = "playbackCommand"
        public static let importDates = "clipbookImportDates"
    }

    public static func validatedClipWindow(_ value: Int) -> Int {
        supportedClipWindowSeconds.contains(value) ? value : defaultClipWindowSeconds
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
}

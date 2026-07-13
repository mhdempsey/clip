import ClipCore
import Foundation

enum ClipFormatters {
    static func time(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        return ClipShared.formattedAudioTime(value)
    }
}

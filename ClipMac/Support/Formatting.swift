import Foundation

enum ClipFormatting {
    static let duration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    static let timestamp: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    static func remaining(_ seconds: TimeInterval) -> String {
        let rounded = max(60, seconds)
        return "About \(duration.string(from: rounded) ?? "a few minutes") left"
    }

    static func coverage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

extension Array where Element == AudioSource {
    func naturallySorted() -> [AudioSource] {
        sorted {
            $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }
}

extension URL {
    var isSupportedEPUB: Bool { pathExtension.caseInsensitiveCompare("epub") == .orderedSame }

    var isSupportedAudio: Bool {
        ["mp3", "m4a", "m4b"].contains(pathExtension.lowercased())
    }
}


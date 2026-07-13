import Foundation

struct PlaybackManifest: Decodable, Sendable {
    struct Audio: Decodable, Sendable {
        let file: String
        let offsetS: Double
        let durationS: Double

        enum CodingKeys: String, CodingKey {
            case file
            case offsetS = "offset_s"
            case durationS = "duration_s"
        }
    }

    struct Chapter: Decodable, Sendable {
        let title: String
        let startS: Double

        enum CodingKeys: String, CodingKey {
            case title
            case startS = "start_s"
        }
    }

    let audio: [Audio]
    let chapters: [Chapter]
}

import Foundation

struct ClipDestination {
    let documentsURL: URL
    let usesICloud: Bool
}

enum DestinationService {
    private static let containerIdentifier = "iCloud.com.michael.clip"

    static func destination(create: Bool = true) throws -> ClipDestination {
        let fileManager = FileManager.default
        if let container = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) {
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            if create { try fileManager.createDirectory(at: documents, withIntermediateDirectories: true) }
            return ClipDestination(documentsURL: documents, usesICloud: true)
        }

        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        ).appendingPathComponent("Clip", isDirectory: true)
        if create { try fileManager.createDirectory(at: documents, withIntermediateDirectories: true) }
        return ClipDestination(documentsURL: documents, usesICloud: false)
    }
}


import ClipCore
import Foundation

struct ClipDestination {
    let documentsURL: URL
    let usesICloud: Bool
}

enum DestinationService {
    static func destination() throws -> ClipDestination {
        let fileManager = FileManager.default
        if let container = fileManager.url(forUbiquityContainerIdentifier: ClipShared.iCloudContainerIdentifier) {
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
            return ClipDestination(documentsURL: documents, usesICloud: true)
        }

        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Clip", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        return ClipDestination(documentsURL: documents, usesICloud: false)
    }
}

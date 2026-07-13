import AppKit
import UniformTypeIdentifiers

@MainActor
enum FileIngestionService {
    static func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose a book and audiobook"
        panel.message = "Choose one EPUB and one or more MP3, M4A, or M4B files."
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = supportedTypes
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            if let data = item as? Data,
                               let url = URL(dataRepresentation: data, relativeTo: nil) {
                                continuation.resume(returning: url)
                            } else if let url = item as? URL {
                                continuation.resume(returning: url)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                    }
                }
            }

            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }
    }

    private static var supportedTypes: [UTType] {
        ["epub", "mp3", "m4a", "m4b"].compactMap { UTType(filenameExtension: $0) }
    }
}


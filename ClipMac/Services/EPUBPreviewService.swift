import ClipCore
import Foundation

struct EPUBPreview {
    let title: String?
    let author: String?
    let coverData: Data?
}

enum EPUBPreviewService {
    static func read(_ url: URL) throws -> EPUBPreview {
        let book = try EPUBReader.read(from: url)
        return EPUBPreview(
            title: reflectedValue(named: "title", in: book),
            author: reflectedValue(named: "author", in: book),
            coverData: reflectedValue(named: "coverData", in: book)
        )
    }

    private static func reflectedValue<T>(named name: String, in value: Any, depth: Int = 0) -> T? {
        guard depth < 5 else { return nil }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else { return nil }
            return reflectedValue(named: name, in: child.value, depth: depth + 1)
        }
        for child in mirror.children {
            if child.label == name, let result = child.value as? T { return result }
        }
        for child in mirror.children {
            if let result: T = reflectedValue(named: name, in: child.value, depth: depth + 1) {
                return result
            }
        }
        return nil
    }
}


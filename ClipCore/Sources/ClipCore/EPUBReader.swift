import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ZIPFoundation

public struct EPUBMetadata: Equatable, Sendable {
    public var title: String
    public var author: String

    public init(title: String, author: String) {
        self.title = title
        self.author = author
    }
}

public struct EPUBChapter: Equatable, Sendable {
    public var title: String
    public var href: String
    public var sentenceRange: Range<Int>

    public init(title: String, href: String, sentenceRange: Range<Int>) {
        self.title = title
        self.href = href
        self.sentenceRange = sentenceRange
    }
}

public struct EPUBSentence: Equatable, Sendable, Identifiable {
    public var i: Int
    public var text: String
    public var chapter: Int
    public var p: Int
    public var epub: EPUBPosition

    public var id: Int { i }

    public init(i: Int, text: String, chapter: Int, p: Int, epub: EPUBPosition) {
        self.i = i
        self.text = text
        self.chapter = chapter
        self.p = p
        self.epub = epub
    }
}

public struct EPUBBook: Equatable, Sendable {
    public var metadata: EPUBMetadata
    public var chapters: [EPUBChapter]
    public var sentences: [EPUBSentence]
    public var coverData: Data?

    public init(metadata: EPUBMetadata, chapters: [EPUBChapter], sentences: [EPUBSentence], coverData: Data?) {
        self.metadata = metadata
        self.chapters = chapters
        self.sentences = sentences
        self.coverData = coverData
    }
}

public enum EPUBReaderError: Error, LocalizedError, Sendable {
    case missingContainer
    case invalidContainer
    case missingPackage
    case invalidPackage
    case missingSpineItem(String)
    case unreadableDocument(String)
    case unsafePath(String)
    case archiveTooManyEntries
    case archiveTooLarge
    case archiveEntryTooLarge(String)
    case archiveEntryCompressionRatio(String)
    case archiveContainsSymbolicLink(String)

    public var errorDescription: String? {
        switch self {
        case .missingContainer: "The EPUB has no META-INF/container.xml."
        case .invalidContainer: "The EPUB container is invalid."
        case .missingPackage: "The EPUB package document is missing."
        case .invalidPackage: "The EPUB package document is invalid."
        case let .missingSpineItem(id): "The EPUB spine references missing item \(id)."
        case let .unreadableDocument(href): "The EPUB document \(href) could not be read."
        case let .unsafePath(path): "The EPUB contains an unsafe path: \(path)."
        case .archiveTooManyEntries: "The EPUB contains too many files."
        case .archiveTooLarge: "The EPUB expands beyond the supported size."
        case let .archiveEntryTooLarge(path): "The EPUB file \(path) is too large."
        case let .archiveEntryCompressionRatio(path): "The EPUB file \(path) has an unsafe compression ratio."
        case let .archiveContainsSymbolicLink(path): "The EPUB contains a symbolic link: \(path)."
        }
    }
}

public enum EPUBReader {
    public static func read(from epubURL: URL) throws -> EPUBBook {
        let fileManager = FileManager.default
        try preflightArchive(at: epubURL)
        let extractionURL = fileManager.temporaryDirectory.appendingPathComponent("Clip-EPUB-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractionURL) }
        try fileManager.unzipItem(at: epubURL, to: extractionURL)

        let containerURL = extractionURL.appendingPathComponent("META-INF/container.xml")
        guard fileManager.fileExists(atPath: containerURL.path) else { throw EPUBReaderError.missingContainer }
        let containerDelegate = ContainerDelegate()
        try parseXML(at: containerURL, delegate: containerDelegate)
        guard let packagePath = containerDelegate.packagePath, !packagePath.isEmpty else { throw EPUBReaderError.invalidContainer }

        let packageURL = try resolvedURL(for: packagePath, relativeTo: extractionURL, extractionRoot: extractionURL)
        guard fileManager.fileExists(atPath: packageURL.path) else { throw EPUBReaderError.missingPackage }
        let packageDelegate = PackageDelegate()
        try parseXML(at: packageURL, delegate: packageDelegate)
        guard !packageDelegate.spine.isEmpty else { throw EPUBReaderError.invalidPackage }

        let baseURL = packageURL.deletingLastPathComponent()
        var sentences: [EPUBSentence] = []
        var chapters: [EPUBChapter] = []
        var paragraphOrdinal = 0

        for idref in packageDelegate.spine {
            guard let item = packageDelegate.manifest[idref] else { throw EPUBReaderError.missingSpineItem(idref) }
            guard !shouldSkip(item) else { continue }
            let href = item.href.removingPercentEncoding ?? item.href
            let documentURL = try resolvedURL(for: href, relativeTo: baseURL, extractionRoot: extractionURL)
            guard let data = try? Data(contentsOf: documentURL), let xhtml = decodeText(data) else {
                throw EPUBReaderError.unreadableDocument(item.href)
            }
            let scan = XHTMLTextScanner.scan(xhtml)
            guard !scan.blocks.isEmpty else { continue }

            let majorHeadings = scan.blocks.enumerated().compactMap { index, block -> (Int, String)? in
                guard case let .heading(level) = block.kind, level <= 2 else { return nil }
                return (index, block.text)
            }
            let defaultTitle = majorHeadings.first?.1 ?? scan.documentTitle ?? documentURL.deletingPathExtension().lastPathComponent
            var boundaries: [(block: Int, title: String)]
            if majorHeadings.count > 1 {
                boundaries = majorHeadings
                if let first = boundaries.first, first.block > 0 { boundaries[0].block = 0 }
            } else {
                boundaries = [(0, defaultTitle)]
            }

            for boundaryIndex in boundaries.indices {
                let startBlock = boundaries[boundaryIndex].block
                let endBlock = boundaryIndex + 1 < boundaries.count ? boundaries[boundaryIndex + 1].block : scan.blocks.count
                let sentenceStart = sentences.count
                let chapterIndex = chapters.count
                for blockIndex in startBlock..<endBlock {
                    let block = scan.blocks[blockIndex]
                    for span in SentenceSplitter.split(block.text) {
                        guard span.range.lowerBound < block.sourceCharacterStarts.count,
                              span.range.upperBound > 0,
                              span.range.upperBound - 1 < block.sourceCharacterEnds.count
                        else { continue }
                        let position = EPUBPosition(
                            href: item.href,
                            charStart: block.sourceCharacterStarts[span.range.lowerBound],
                            charEnd: block.sourceCharacterEnds[span.range.upperBound - 1]
                        )
                        sentences.append(EPUBSentence(
                            i: sentences.count,
                            text: span.text,
                            chapter: chapterIndex,
                            p: paragraphOrdinal,
                            epub: position
                        ))
                    }
                    paragraphOrdinal += 1
                }
                chapters.append(EPUBChapter(
                    title: boundaries[boundaryIndex].title,
                    href: item.href,
                    sentenceRange: sentenceStart..<sentences.count
                ))
            }
        }

        let coverData: Data?
        if let coverItem = packageDelegate.coverItem {
            let coverURL = try resolvedURL(for: coverItem.href, relativeTo: baseURL, extractionRoot: extractionURL)
            coverData = try? Data(contentsOf: coverURL)
        } else {
            coverData = nil
        }
        return EPUBBook(
            metadata: EPUBMetadata(
                title: packageDelegate.title?.nonempty ?? epubURL.deletingPathExtension().lastPathComponent,
                author: packageDelegate.author?.nonempty ?? "Unknown Author"
            ),
            chapters: chapters,
            sentences: sentences,
            coverData: coverData
        )
    }

    private static func shouldSkip(_ item: PackageItem) -> Bool {
        let properties = item.properties.lowercased()
        let name = URL(fileURLWithPath: item.href).deletingPathExtension().lastPathComponent.lowercased()
        return properties.contains("nav") || properties.contains("cover-image") ||
            name == "nav" || name == "toc" || name == "cover" || name.hasPrefix("toc_")
    }

    private static func preflightArchive(at url: URL) throws {
        let archive = try Archive(url: url, accessMode: .read)
        var entryCount = 0
        var totalUncompressedSize: UInt64 = 0
        for entry in archive {
            entryCount += 1
            try EPUBArchivePreflight.validate(
                path: entry.path,
                isSymbolicLink: entry.type == .symlink,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize,
                entryCount: entryCount,
                totalUncompressedSize: &totalUncompressedSize
            )
        }
    }

    private static func resolvedURL(for rawPath: String, relativeTo baseURL: URL, extractionRoot: URL) throws -> URL {
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        let path = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? decoded
        guard !path.isEmpty, !(path as NSString).isAbsolutePath else { throw EPUBReaderError.unsafePath(rawPath) }
        let root = extractionRoot.standardizedFileURL
        let candidate = baseURL.appendingPathComponent(path).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            throw EPUBReaderError.unsafePath(rawPath)
        }
        return candidate
    }

    private static func decodeText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func parseXML(at url: URL, delegate: XMLParserDelegate) throws {
        guard let parser = XMLParser(contentsOf: url) else { throw EPUBReaderError.invalidPackage }
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? EPUBReaderError.invalidPackage }
    }
}

enum EPUBArchivePreflight {
    static let maximumEntryCount = 10_000
    static let maximumTotalUncompressedSize: UInt64 = 512 * 1024 * 1024
    static let maximumEntryUncompressedSize: UInt64 = 128 * 1024 * 1024
    static let maximumCompressionRatio: UInt64 = 100

    static func validate(
        path: String,
        isSymbolicLink: Bool,
        compressedSize: UInt64,
        uncompressedSize: UInt64,
        entryCount: Int,
        totalUncompressedSize: inout UInt64
    ) throws {
        guard entryCount <= maximumEntryCount else { throw EPUBReaderError.archiveTooManyEntries }
        guard !isSymbolicLink else { throw EPUBReaderError.archiveContainsSymbolicLink(path) }
        guard uncompressedSize <= maximumEntryUncompressedSize else { throw EPUBReaderError.archiveEntryTooLarge(path) }

        let (newTotal, overflow) = totalUncompressedSize.addingReportingOverflow(uncompressedSize)
        guard !overflow, newTotal <= maximumTotalUncompressedSize else { throw EPUBReaderError.archiveTooLarge }
        totalUncompressedSize = newTotal

        if uncompressedSize > 0 {
            guard compressedSize > 0 else { throw EPUBReaderError.archiveEntryCompressionRatio(path) }
            let (ratioLimit, ratioOverflow) = compressedSize.multipliedReportingOverflow(by: maximumCompressionRatio)
            if !ratioOverflow, uncompressedSize > ratioLimit {
                throw EPUBReaderError.archiveEntryCompressionRatio(path)
            }
        }
    }
}

private struct PackageItem: Sendable {
    var href: String
    var properties: String
}

private final class ContainerDelegate: NSObject, XMLParserDelegate {
    var packagePath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if localName(elementName) == "rootfile" { packagePath = attributeDict["full-path"] }
    }
}

private final class PackageDelegate: NSObject, XMLParserDelegate {
    var manifest: [String: PackageItem] = [:]
    var spine: [String] = []
    var title: String?
    var author: String?
    var coverID: String?
    private var capturing: String?
    private var buffer = ""

    var coverItem: PackageItem? {
        manifest.values.first(where: { $0.properties.lowercased().contains("cover-image") }) ?? coverID.flatMap { manifest[$0] }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = localName(elementName)
        switch name {
        case "title", "creator": capturing = name; buffer = ""
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = PackageItem(href: href, properties: attributeDict["properties"] ?? "")
            }
        case "itemref": if let idref = attributeDict["idref"] { spine.append(idref) }
        case "meta": if attributeDict["name"]?.lowercased() == "cover" { coverID = attributeDict["content"] }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing != nil { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        guard capturing == name else { return }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "title", title == nil { title = value }
        if name == "creator", author == nil { author = value }
        capturing = nil
    }
}

private func localName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}

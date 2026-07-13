import Foundation

public struct XHTMLScanResult: Equatable, Sendable {
    public var text: String
    public var blocks: [XHTMLBlock]
    public var headings: [XHTMLHeading]
    public var documentTitle: String?

    public init(text: String, blocks: [XHTMLBlock], headings: [XHTMLHeading], documentTitle: String?) {
        self.text = text
        self.blocks = blocks
        self.headings = headings
        self.documentTitle = documentTitle
    }
}

public struct XHTMLBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case paragraph, heading(level: Int), listItem, blockquote, division }

    public var text: String
    public var textRange: Range<Int>
    public var sourceRange: Range<Int>
    public var kind: Kind
    public var sourceCharacterStarts: [Int]
    public var sourceCharacterEnds: [Int]

    public init(text: String, textRange: Range<Int>, sourceRange: Range<Int>, kind: Kind, sourceCharacterStarts: [Int] = [], sourceCharacterEnds: [Int] = []) {
        self.text = text
        self.textRange = textRange
        self.sourceRange = sourceRange
        self.kind = kind
        self.sourceCharacterStarts = sourceCharacterStarts
        self.sourceCharacterEnds = sourceCharacterEnds
    }
}

public struct XHTMLHeading: Equatable, Sendable {
    public var text: String
    public var level: Int
    public var textRange: Range<Int>
    public var sourceRange: Range<Int>

    public init(text: String, level: Int, textRange: Range<Int>, sourceRange: Range<Int>) {
        self.text = text
        self.level = level
        self.textRange = textRange
        self.sourceRange = sourceRange
    }
}

public enum XHTMLTextScanner {
    private struct Fragment {
        var character: Character
        var sourceStart: Int
        var sourceEnd: Int
    }

    private struct BlockBuilder {
        var tag: String
        var kind: XHTMLBlock.Kind
        var fragments: [Fragment] = []
        var hasNestedBlock = false
    }

    private static let blockTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "div"]
    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "mdash": "—", "ndash": "–",
        "hellip": "…", "copy": "©", "reg": "®", "trade": "™",
    ]

    public static func scan(_ source: String) -> XHTMLScanResult {
        var blocks: [(text: String, sourceRange: Range<Int>, kind: XHTMLBlock.Kind, starts: [Int], ends: [Int])] = []
        var stack: [BlockBuilder] = []
        var titleFragments: [Fragment] = []
        var inTitle = false
        var implicitFragments: [Fragment] = []
        var index = source.startIndex
        var sourceOffset = 0

        func append(_ fragment: Fragment) {
            if inTitle { titleFragments.append(fragment); return }
            if !stack.isEmpty {
                stack[stack.count - 1].fragments.append(fragment)
            } else {
                implicitFragments.append(fragment)
            }
        }

        func flushImplicit() {
            guard let finalized = finalizedFragments(implicitFragments) else { implicitFragments.removeAll(); return }
            blocks.append((finalized.text, finalized.range, .paragraph, finalized.starts, finalized.ends))
            implicitFragments.removeAll()
        }

        func closeBlock(named name: String) {
            guard let matching = stack.lastIndex(where: { $0.tag == name }) else { return }
            while stack.count > matching {
                let builder = stack.removeLast()
                if let finalized = finalizedFragments(builder.fragments), !(builder.kind == .division && builder.hasNestedBlock && builder.fragments.isEmpty) {
                    blocks.append((finalized.text, finalized.range, builder.kind, finalized.starts, finalized.ends))
                }
            }
        }

        while index < source.endIndex {
            if source[index] == "<" {
                if source[index...].hasPrefix("<!--"), let end = source.range(of: "-->", range: index..<source.endIndex)?.upperBound {
                    sourceOffset += source.distance(from: index, to: end)
                    index = end
                    continue
                }
                if source[index...].hasPrefix("<![CDATA["), let end = source.range(of: "]]>", range: index..<source.endIndex)?.upperBound {
                    sourceOffset += source.distance(from: index, to: end)
                    index = end
                    continue
                }
                guard let tagEnd = endOfTag(in: source, from: index) else { break }
                let afterTag = source.index(after: tagEnd)
                let raw = String(source[source.index(after: index)..<tagEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                let closing = raw.hasPrefix("/")
                let selfClosing = raw.hasSuffix("/")
                let body = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                let name = body.split(whereSeparator: { $0.isWhitespace }).first.map { $0.lowercased() } ?? ""
                let consumed = source.distance(from: index, to: afterTag)

                if !closing, name == "script" || name == "style" {
                    let closeNeedle = "</\(name)"
                    if let closeStart = source.range(of: closeNeedle, options: .caseInsensitive, range: afterTag..<source.endIndex)?.lowerBound,
                       let closeEndTag = endOfTag(in: source, from: closeStart) {
                        let end = source.index(after: closeEndTag)
                        sourceOffset += source.distance(from: index, to: end)
                        index = end
                        continue
                    }
                }

                if name == "title" { inTitle = !closing }
                if blockTags.contains(name) {
                    if closing {
                        closeBlock(named: name)
                    } else {
                        flushImplicit()
                        if !stack.isEmpty { stack[stack.count - 1].hasNestedBlock = true }
                        stack.append(BlockBuilder(tag: name, kind: kind(for: name)))
                        if selfClosing { closeBlock(named: name) }
                    }
                } else if name == "br", !closing {
                    append(Fragment(character: " ", sourceStart: sourceOffset, sourceEnd: sourceOffset + consumed))
                }
                sourceOffset += consumed
                index = afterTag
                continue
            }

            if source[index] == "&", let semicolon = source[index...].firstIndex(of: ";") {
                let after = source.index(after: semicolon)
                let rawEntity = String(source[source.index(after: index)..<semicolon])
                if let decoded = decodeEntity(rawEntity) {
                    let length = source.distance(from: index, to: after)
                    for character in decoded {
                        append(Fragment(character: character, sourceStart: sourceOffset, sourceEnd: sourceOffset + length))
                    }
                    sourceOffset += length
                    index = after
                    continue
                }
            }

            let next = source.index(after: index)
            append(Fragment(character: source[index], sourceStart: sourceOffset, sourceEnd: sourceOffset + 1))
            sourceOffset += 1
            index = next
        }

        while let builder = stack.popLast() {
            if let finalized = finalizedFragments(builder.fragments) {
                blocks.append((finalized.text, finalized.range, builder.kind, finalized.starts, finalized.ends))
            }
        }
        flushImplicit()

        var fullText = ""
        var publicBlocks: [XHTMLBlock] = []
        var headings: [XHTMLHeading] = []
        for block in blocks {
            if !fullText.isEmpty { fullText += "\n\n" }
            let lower = fullText.count
            fullText += block.text
            let range = lower..<fullText.count
            let publicBlock = XHTMLBlock(
                text: block.text,
                textRange: range,
                sourceRange: block.sourceRange,
                kind: block.kind,
                sourceCharacterStarts: block.starts,
                sourceCharacterEnds: block.ends
            )
            publicBlocks.append(publicBlock)
            if case let .heading(level) = block.kind {
                headings.append(XHTMLHeading(text: block.text, level: level, textRange: range, sourceRange: block.sourceRange))
            }
        }

        let title = finalizedFragments(titleFragments)?.text
        return XHTMLScanResult(text: fullText, blocks: publicBlocks, headings: headings, documentTitle: title)
    }

    private static func kind(for tag: String) -> XHTMLBlock.Kind {
        if tag.hasPrefix("h"), let level = Int(tag.dropFirst()) { return .heading(level: level) }
        return switch tag {
        case "li": .listItem
        case "blockquote": .blockquote
        case "div": .division
        default: .paragraph
        }
    }

    private static func finalizedFragments(_ fragments: [Fragment]) -> (text: String, range: Range<Int>, starts: [Int], ends: [Int])? {
        var normalized: [Fragment] = []
        var pendingSpace: Fragment?
        for fragment in fragments {
            if fragment.character == "\u{00A0}" {
                if let pendingSpace, !normalized.isEmpty { normalized.append(pendingSpace) }
                pendingSpace = nil
                normalized.append(fragment)
            } else if fragment.character.isWhitespace {
                if !normalized.isEmpty { pendingSpace = Fragment(character: " ", sourceStart: fragment.sourceStart, sourceEnd: fragment.sourceEnd) }
            } else {
                if let pendingSpace { normalized.append(pendingSpace) }
                pendingSpace = nil
                normalized.append(fragment)
            }
        }
        guard let first = normalized.first, let last = normalized.last else { return nil }
        return (
            String(normalized.map(\.character)),
            first.sourceStart..<last.sourceEnd,
            normalized.map(\.sourceStart),
            normalized.map(\.sourceEnd)
        )
    }

    private static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X"), let value = UInt32(entity.dropFirst(2), radix: 16), let scalar = UnicodeScalar(value) {
            return String(Character(scalar))
        }
        if entity.hasPrefix("#"), let value = UInt32(entity.dropFirst()), let scalar = UnicodeScalar(value) {
            return String(Character(scalar))
        }
        return entities[entity.lowercased()]
    }

    private static func endOfTag(in source: String, from start: String.Index) -> String.Index? {
        var cursor = source.index(after: start)
        var quote: Character?
        while cursor < source.endIndex {
            let character = source[cursor]
            if let active = quote {
                if character == active { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return cursor
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }
}

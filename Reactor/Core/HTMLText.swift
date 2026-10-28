import SwiftUI

/// Piece of post/comment content: rich text or an inline attribute (picture, video, embed).
enum ContentBlock: Identifiable {
    case text(AttributedString, id: Int)
    case attribute(Attribute)

    var id: String {
        switch self {
        case .text(_, let id): return "text-\(id)"
        case .attribute(let attribute): return attribute.id
        }
    }
}

enum ContentBuilder {
    /// Splits joyreactor HTML on `&attribute_insert_N&` markers. Attributes that are not
    /// referenced from the text are appended after it, as the site does.
    static func blocks(html: String, attributes: [Attribute]) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var used = Set<String>()
        var textIndex = 0
        let byInsert = Dictionary(attributes.compactMap { a in a.insertId.map { ($0, a) } }, uniquingKeysWith: { a, _ in a })

        func appendText(_ fragment: Substring) {
            let attributed = HTMLText.attributed(String(fragment))
            if !attributed.characters.isEmpty {
                blocks.append(.text(attributed, id: textIndex))
                textIndex += 1
            }
        }

        var rest = html[...]
        while let start = rest.range(of: "&attribute_insert_") {
            appendText(rest[..<start.lowerBound])
            let afterPrefix = rest[start.upperBound...]
            guard let end = afterPrefix.firstIndex(of: "&") else {
                rest = afterPrefix
                break
            }
            if let number = Int(afterPrefix[..<end]), let attribute = byInsert[number], !used.contains(attribute.id) {
                blocks.append(.attribute(attribute))
                used.insert(attribute.id)
            }
            rest = afterPrefix[afterPrefix.index(after: end)...]
        }
        appendText(rest)

        for attribute in attributes where !used.contains(attribute.id) {
            blocks.append(.attribute(attribute))
        }
        return blocks
    }

    static func plainText(html: String) -> String {
        let cleaned = html.replacingOccurrences(of: "&attribute_insert_\\d+&", with: " ", options: .regularExpression)
        return String(HTMLText.attributed(cleaned).characters)
    }
}

/// Small, forgiving HTML → AttributedString converter for the subset joyreactor uses.
enum HTMLText {
    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var heading = false
        var quote = false
        var code = false
        var link: URL?
    }

    private static let blockTags: Set<String> = ["p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol", "blockquote", "hr", "pre", "table", "tr"]

    static func attributed(_ html: String) -> AttributedString {
        let lower = html.lowercased()
        let hasBlocks = blockTags.contains { lower.contains("<\($0)") }
        var output = AttributedString()
        var stack: [(tag: String, style: Style)] = []
        var style = Style()
        var pendingNewlines = 0
        var atStart = true
        var listCounters: [Int?] = []

        func requestBreak(_ count: Int) {
            if !atStart { pendingNewlines = max(pendingNewlines, count) }
        }

        func emit(_ raw: String) {
            var text = decodeEntities(raw)
            if hasBlocks {
                text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            } else {
                text = text.replacingOccurrences(of: "\r\n", with: "\n")
            }
            if atStart || pendingNewlines > 0 {
                text = String(text.drop(while: { $0 == " " }))
            }
            guard !text.isEmpty else { return }
            if pendingNewlines > 0 {
                output.append(AttributedString(String(repeating: "\n", count: pendingNewlines)))
                pendingNewlines = 0
            }
            var piece = AttributedString(text)
            var font: Font = style.heading ? .title3 : (style.code ? .body.monospaced() : .body)
            if style.bold || style.heading { font = font.bold() }
            if style.italic || style.quote { font = font.italic() }
            piece[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = font
            if style.underline { piece[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = Text.LineStyle.single }
            if style.strike { piece[AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self] = Text.LineStyle.single }
            if style.quote { piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.secondary }
            if let link = style.link {
                piece.link = link
                piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.accentColor
            }
            output.append(piece)
            atStart = false
        }

        var index = html.startIndex
        var textStart = index
        while index < html.endIndex {
            guard html[index] == "<", let close = html[index...].firstIndex(of: ">") else {
                index = html.index(after: index)
                continue
            }
            if textStart < index { emit(String(html[textStart..<index])) }
            let inner = html[html.index(after: index)..<close]
            index = html.index(after: close)
            textStart = index

            var body = inner.trimmingCharacters(in: .whitespaces)
            let closing = body.hasPrefix("/")
            if closing { body.removeFirst() }
            let selfClosing = body.hasSuffix("/")
            let name = String(body.prefix(while: { $0.isLetter || $0.isNumber })).lowercased()
            guard !name.isEmpty else { continue }

            if closing {
                switch name {
                case "p", "div", "blockquote", "pre", "table": requestBreak(2)
                case "h1", "h2", "h3", "h4", "h5", "h6": requestBreak(2)
                case "li", "tr": requestBreak(1)
                case "ul", "ol":
                    if !listCounters.isEmpty { listCounters.removeLast() }
                    requestBreak(2)
                default: break
                }
                if let position = stack.lastIndex(where: { $0.tag == name }) {
                    style = stack[position].style
                    stack.removeSubrange(position...)
                }
                continue
            }

            switch name {
            case "br":
                if !atStart {
                    output.append(AttributedString("\n"))
                    pendingNewlines = 0
                }
                continue
            case "hr":
                requestBreak(2)
                continue
            case "img":
                continue
            default:
                break
            }
            if selfClosing { continue }

            stack.append((name, style))
            switch name {
            case "b", "strong": style.bold = true
            case "i", "em": style.italic = true
            case "u", "ins": style.underline = true
            case "s", "strike", "del": style.strike = true
            case "code", "pre": style.code = true
            case "h1", "h2", "h3", "h4", "h5", "h6":
                requestBreak(2)
                style.heading = true
            case "p", "div", "table": requestBreak(2)
            case "blockquote":
                requestBreak(2)
                style.quote = true
            case "ul": listCounters.append(nil); requestBreak(1)
            case "ol": listCounters.append(0); requestBreak(1)
            case "li":
                requestBreak(1)
                var marker = "•  "
                if let last = listCounters.last, let counter = last {
                    listCounters[listCounters.count - 1] = counter + 1
                    marker = "\(counter + 1).  "
                }
                emit(marker)
            case "a":
                if let href = attribute("href", in: String(inner)) {
                    style.link = resolveLink(decodeEntities(href))
                }
            default: break
            }
        }
        if textStart < html.endIndex { emit(String(html[textStart...])) }

        // Trim trailing whitespace/newlines.
        while let last = output.characters.last, last.isWhitespace {
            output.characters.removeLast()
        }
        return output
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 2...4 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }

    static func resolveLink(_ href: String) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") { return URL(string: "https:" + trimmed) }
        if trimmed.hasPrefix("/") { return URL(string: "https://joyreactor.cc" + trimmed) ?? URL(string: "https://joyreactor.cc" + (trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")) }
        return URL(string: trimmed) ?? trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "laquo": "«", "raquo": "»", "mdash": "—", "ndash": "–", "hellip": "…", "copy": "©",
        "reg": "®", "trade": "™", "bull": "•", "middot": "·", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "bdquo": "„", "times": "×", "deg": "°", "euro": "€", "shy": "",
    ]

    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        var index = string.startIndex
        while index < string.endIndex {
            let char = string[index]
            if char == "&", let semi = string[index...].prefix(12).firstIndex(of: ";") {
                let entity = string[string.index(after: index)..<semi]
                var replacement: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    if let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                        replacement = String(Character(scalar))
                    }
                } else if entity.hasPrefix("#") {
                    if let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                        replacement = String(Character(scalar))
                    }
                } else {
                    replacement = namedEntities[String(entity)]
                }
                if let replacement {
                    result += replacement
                    index = string.index(after: semi)
                    continue
                }
            }
            result.append(char)
            index = string.index(after: index)
        }
        return result
    }
}

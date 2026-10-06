import Foundation

/// 事项描述支持的 Markdown 块：小标题、正文、列表、引用、代码与图片。
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case ordered(number: Int, text: String)
    case quote(String)
    case code(String)
    case image(alt: String, source: String)
}

/// 轻量 Markdown 块解析器：只覆盖事项描述需要的语法，行内样式交给 `AttributedString`。
enum MarkdownDocument {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            quote = []
        }

        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if var lines = code {
                if line.hasPrefix("```") {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    lines.append(rawLine)
                    code = lines
                }
                continue
            }
            if line.hasPrefix("```") {
                flushParagraph(); flushQuote()
                code = []
                continue
            }
            if line.isEmpty {
                flushParagraph(); flushQuote()
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()

            if let heading = heading(in: line) {
                flushParagraph()
                blocks.append(heading)
            } else if let image = image(in: line) {
                flushParagraph()
                blocks.append(image)
            } else if let text = bulletText(in: line) {
                flushParagraph()
                blocks.append(.bullet(text))
            } else if let ordered = ordered(in: line) {
                flushParagraph()
                blocks.append(ordered)
            } else {
                paragraph.append(line)
            }
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flushParagraph(); flushQuote()
        return blocks
    }

    /// 去掉 Markdown 标记后的纯文本，用于悬停提示等摘要场景。
    static func plainText(_ markdown: String) -> String {
        parse(markdown).compactMap { block -> String? in
            switch block {
            case .heading(_, let text), .paragraph(let text), .bullet(let text), .quote(let text), .code(let text):
                return text
            case .ordered(let number, let text):
                return "\(number). \(text)"
            case .image:
                return nil
            }
        }.joined(separator: "\n")
    }

    static func imageSources(in markdown: String) -> [String] {
        parse(markdown).compactMap { block in
            if case .image(_, let source) = block { return source }
            return nil
        }
    }

    private static func heading(in line: String) -> MarkdownBlock? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return .heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletText(in line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func ordered(in line: String) -> MarkdownBlock? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return .ordered(number: number, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }

    /// 整行 `![说明](路径)` 视为图片块。
    private static func image(in line: String) -> MarkdownBlock? {
        guard line.hasPrefix("!["), line.hasSuffix(")"),
              let altEnd = line.range(of: "](") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd.lowerBound])
        let source = String(line[altEnd.upperBound..<line.index(before: line.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        guard !source.isEmpty, !alt.contains("]") else { return nil }
        return .image(alt: alt, source: source)
    }
}

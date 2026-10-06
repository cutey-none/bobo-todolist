import Foundation

/// 旧版结构化描述块，仅用于把历史数据迁移为 Markdown。
enum DescriptionBlockKind: String, Codable {
    case paragraph
    case heading
    case bullet
    case image
}

struct DescriptionBlock: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: DescriptionBlockKind
    var text: String
    var image: Data?

    init(id: UUID = UUID(), kind: DescriptionBlockKind, text: String = "", image: Data? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.image = image
    }
}

/// 事项描述以 Markdown 文本保存在 `TaskItem.note`；旧版 JSON 块与纯文本备注都能兼容读取。
enum TaskDescription {
    private struct Envelope: Codable {
        let version: Int
        let blocks: [DescriptionBlock]
    }

    /// 旧版 JSON 块描述；Markdown 或纯文本返回 nil。
    static func legacyBlocks(from note: String?) -> [DescriptionBlock]? {
        guard let note, note.first == "{" || note.first == "[",
              let data = note.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) { return envelope.blocks }
        return try? decoder.decode([DescriptionBlock].self, from: data)
    }

    /// 读取任意版本的存储内容并给出 Markdown；旧版图片通过 `saveImage` 落盘为附件。
    static func markdown(fromStored note: String?, saveImage: (Data) -> String?) -> String {
        if let blocks = legacyBlocks(from: note) { return markdown(from: blocks, saveImage: saveImage) }
        return note ?? ""
    }

    static func markdown(from blocks: [DescriptionBlock], saveImage: (Data) -> String?) -> String {
        var output = ""
        var previous: DescriptionBlockKind?
        for block in blocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let line: String
            switch block.kind {
            case .heading:
                guard !text.isEmpty else { continue }
                line = "### " + text.replacingOccurrences(of: "\n", with: " ")
            case .bullet:
                guard !text.isEmpty else { continue }
                line = "- " + text.replacingOccurrences(of: "\n", with: " ")
            case .paragraph:
                guard !text.isEmpty else { continue }
                line = text
            case .image:
                guard let data = block.image, !data.isEmpty, let source = saveImage(data) else { continue }
                line = "![图片](\(source))"
            }
            // 连续列表项保持紧凑，其余块之间空一行，保证 Markdown 分段正确。
            if let previous { output += previous == .bullet && block.kind == .bullet ? "\n" : "\n\n" }
            output += line
            previous = block.kind
        }
        return output
    }

    /// 写入前规范化：空白描述保存为 nil。
    static func normalized(_ markdown: String) -> String? {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

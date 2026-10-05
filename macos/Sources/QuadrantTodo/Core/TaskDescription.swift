import Foundation

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

enum TaskDescription {
    private struct Envelope: Codable {
        let version: Int
        let blocks: [DescriptionBlock]
    }

    static func decode(_ note: String?) -> [DescriptionBlock] {
        guard let note, !note.isEmpty else { return [] }
        guard let data = note.data(using: .utf8) else {
            return [DescriptionBlock(kind: .paragraph, text: note)]
        }
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return envelope.blocks
        }
        if let blocks = try? decoder.decode([DescriptionBlock].self, from: data) {
            return blocks
        }
        return [DescriptionBlock(kind: .paragraph, text: note)]
    }

    static func encode(_ blocks: [DescriptionBlock]) -> String? {
        let valid = blocks.filter { block in
            !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || block.image != nil
        }
        guard !valid.isEmpty else { return nil }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(Envelope(version: 1, blocks: valid)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func plainText(_ blocks: [DescriptionBlock]) -> String {
        blocks.compactMap { block in
            guard block.kind != .image else { return nil }
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.joined(separator: "\n")
    }

    static func isEmpty(_ blocks: [DescriptionBlock]) -> Bool {
        blocks.allSatisfy {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.image == nil
        }
    }
}

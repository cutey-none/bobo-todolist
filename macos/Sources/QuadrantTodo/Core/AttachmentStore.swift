import AppKit
import Foundation

/// Markdown 描述里的图片文件：存放在数据目录的 `Attachments/` 下，正文用相对路径 `attachments/<名称>` 引用。
struct AttachmentStore {
    static let prefix = "attachments/"
    static let shared = AttachmentStore(
        directory: PersistenceController.storeURL().deletingLastPathComponent()
            .appendingPathComponent("Attachments", isDirectory: true)
    )

    let directory: URL

    /// 保存图片数据，返回可写入 Markdown 的相对路径。
    func save(_ data: Data) -> String? {
        let ext = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
        let name = "\(UUID().uuidString.lowercased()).\(ext)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return Self.prefix + name
        } catch {
            NSLog("QuadrantTodo: 保存图片失败 \(error.localizedDescription)")
            return nil
        }
    }

    /// 解析图片来源：相对附件路径、`file://` URL 或绝对路径。
    func url(for source: String) -> URL? {
        if source.hasPrefix(Self.prefix) {
            let name = String(source.dropFirst(Self.prefix.count))
            guard !name.isEmpty, !name.contains("/") else { return nil }
            return directory.appendingPathComponent(name)
        }
        if let url = URL(string: source), url.isFileURL { return url }
        if source.hasPrefix("/") { return URL(fileURLWithPath: source) }
        return nil
    }

    func data(for source: String) -> Data? {
        url(for: source).flatMap { try? Data(contentsOf: $0) }
    }

    func image(for source: String) -> NSImage? {
        guard let url = url(for: source) else { return nil }
        if let cached = Self.cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        Self.cache.setObject(image, forKey: url as NSURL)
        return image
    }

    private static let cache = NSCache<NSURL, NSImage>()
}

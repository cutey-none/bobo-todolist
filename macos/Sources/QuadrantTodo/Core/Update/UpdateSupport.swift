import CryptoKit
import Foundation

enum UpdateError: Error, Equatable {
    case network(String)
    case rateLimited
    case badResponse
    case unrecognizedVersion
    case invalidChecksumFile
    case checksumMismatch
    case command(String, String)
    case invalidBundle(String)
    case backupFailed(String)
    case cancelled

    var message: String {
        switch self {
        case .network(let detail): return "无法连接 GitHub：\(detail)"
        case .rateLimited: return "请求过于频繁，请稍后再试。"
        case .badResponse: return "无法解析发布信息。"
        case .unrecognizedVersion: return "无法识别版本号。"
        case .invalidChecksumFile: return "校验文件格式不正确，未进行升级。"
        case .checksumMismatch: return "下载的安装包校验失败，已丢弃，请稍后重试。"
        case .command(let name, let output): return "\(name) 执行失败：\(output)"
        case .invalidBundle(let reason): return "安装包无效：\(reason)"
        case .backupFailed(let reason): return "备份数据失败，未进行升级：\(reason)"
        case .cancelled: return "已取消。"
        }
    }
}

/// 更新流程用到的固定位置。数据目录沿用持久化层的定义，自动遵循 `QT_DATA_DIR`。
enum UpdatePaths {
    static let bundleIdentifier = "com.cutey.quadranttodo"
    static let defaultFeedURL = URL(string: "https://api.github.com/repos/cutey-none/bobo-todolist/releases/latest")!

    /// 开发时可用 `QT_UPDATE_FEED_URL` 指向本地的假 Release（支持 file://）。
    static var feedURL: URL {
        ProcessInfo.processInfo.environment["QT_UPDATE_FEED_URL"].flatMap(URL.init(string:)) ?? defaultFeedURL
    }

    static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("QuadrantTodo/Updates", isDirectory: true)
    }

    static var downloadsDirectory: URL { cacheDirectory.appendingPathComponent("Downloads", isDirectory: true) }
    static var resultFile: URL { cacheDirectory.appendingPathComponent("last-result.json") }

    /// 与 macos/upgrade.sh 相同的备份位置，`QT_BACKUP_DIR` 可覆盖。
    static var backupRoot: URL {
        if let custom = ProcessInfo.processInfo.environment["QT_BACKUP_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("QuadrantTodoBackups", isDirectory: true)
    }

    static var dataDirectory: URL { PersistenceController.storeURL().deletingLastPathComponent() }
}

protocol CommandRunning: Sendable {
    @discardableResult
    func run(_ executable: String, _ arguments: [String]) throws -> String
}

/// 同步执行系统命令；非零退出码抛出带输出的错误。
struct ProcessCommandRunner: CommandRunning {
    @discardableResult
    func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw UpdateError.command(
                URL(fileURLWithPath: executable).lastPathComponent,
                output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }
}

enum UpdateChecksum {
    /// 解析 `shasum -a 256` 的输出：`<hash>  <文件名>`；文件名可省略，存在时必须一致。
    static func expectedHash(in text: String, fileName: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline).first else { return nil }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let hash = fields.first?.lowercased(), hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        if fields.count > 1 {
            var name = String(fields[1])
            if name.hasPrefix("*") { name.removeFirst() }
            guard name == fileName else { return nil }
        }
        return hash
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// 助手脚本写下的升级结果，新版启动时读取一次后删除。
struct UpdateResult: Codable, Equatable {
    let status: String
    let version: String
    let backup: String

    var succeeded: Bool { status == "success" }

    var title: String {
        switch status {
        case "success": return "已升级到 \(version)"
        case "timeout": return "升级未完成"
        default: return "升级失败，已保留旧版本"
        }
    }

    var detail: String {
        switch status {
        case "success": return "待办数据没有被替换。升级前的数据与旧版本备份在：\n\(backup)"
        case "timeout": return "旧版本未能及时退出，应用没有被替换，数据未改动。可以重新检查更新再试。"
        default: return "应用没有被替换，数据未改动。数据备份在：\n\(backup)"
        }
    }

    static func consume(at url: URL) -> UpdateResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return try? JSONDecoder().decode(UpdateResult.self, from: data)
    }
}

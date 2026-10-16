import Darwin
import Foundation

/// 已复制到目标应用同目录下、通过校验、等待替换的新版应用。
struct StagedApp: Equatable {
    let appURL: URL
    let stagingDirectory: URL
}

/// 更新流程中有副作用的各步。替换之前的任何步骤都不触碰现有应用和数据目录。
struct UpdateInstaller: Sendable {
    var runner: CommandRunning
    var session: URLSession

    init(runner: CommandRunning = ProcessCommandRunner(), session: URLSession = .shared) {
        self.runner = runner
        self.session = session
    }

    func fetchRelease(from url: URL) async throws -> ReleaseInfo {
        let data: Data
        if url.isFileURL {
            do { data = try Data(contentsOf: url) } catch { throw UpdateError.network(error.localizedDescription) }
        } else {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let body: Data
            let response: URLResponse
            do {
                (body, response) = try await session.data(for: request)
            } catch {
                throw UpdateError.network(error.localizedDescription)
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 403 || http.statusCode == 429 { throw UpdateError.rateLimited }
                guard (200..<300).contains(http.statusCode) else { throw UpdateError.network("HTTP \(http.statusCode)") }
            }
            data = body
        }
        do { return try ReleaseInfo.decode(data) } catch { throw UpdateError.badResponse }
    }

    /// 下载到指定位置，按已接收字节报告 0...1 的进度；取消时抛出 `.cancelled` 并删除半成品。
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)

        if url.isFileURL {
            try fm.copyItem(at: url, to: destination)
            progress(1)
            return
        }

        do {
            let (bytes, response) = try await session.bytes(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw UpdateError.network("HTTP \(http.statusCode)")
            }
            fm.createFile(atPath: destination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            let expected = response.expectedContentLength
            var buffer = Data()
            buffer.reserveCapacity(1 << 16)
            var received: Int64 = 0
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 16 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expected > 0 { progress(min(1, Double(received) / Double(expected))) }
                }
            }
            try handle.write(contentsOf: buffer)
            progress(1)
        } catch {
            try? fm.removeItem(at: destination)
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw UpdateError.cancelled }
            if let updateError = error as? UpdateError { throw updateError }
            throw UpdateError.network(error.localizedDescription)
        }
    }

    func verifyChecksum(file: URL, checksumFile: URL, fileName: String) throws {
        guard let text = try? String(contentsOf: checksumFile, encoding: .utf8),
              let expected = UpdateChecksum.expectedHash(in: text, fileName: fileName) else {
            throw UpdateError.invalidChecksumFile
        }
        guard try UpdateChecksum.sha256Hex(of: file) == expected else {
            try? FileManager.default.removeItem(at: file)
            throw UpdateError.checksumMismatch
        }
    }

    /// 挂载 DMG，把其中的应用复制到目标应用同目录下的隐藏暂存目录（同卷，保证替换时 mv 原子），并验证签名与版本。
    func stage(dmg: URL, nextTo target: URL, expectedVersion: AppVersion) throws -> StagedApp {
        let fm = FileManager.default
        let mountPoint = fm.temporaryDirectory.appendingPathComponent("quadrant-update-mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        // rmdir 只删除空目录，卸载失败时不会误删镜像内容。
        defer { rmdir(mountPoint.path) }
        try runner.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path, dmg.path])
        defer { _ = try? runner.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let source = mountPoint.appendingPathComponent("QuadrantTodo.app")
        guard fm.fileExists(atPath: source.path) else { throw UpdateError.invalidBundle("安装包内没有 QuadrantTodo.app") }

        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".quadrant-update.\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        let staged = staging.appendingPathComponent("QuadrantTodo.app")
        do {
            try runner.run("/usr/bin/ditto", [source.path, staged.path])
            try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
            try Self.validateBundle(at: staged, expectedVersion: expectedVersion)
            // 只对已通过校验和与签名验证的暂存应用移除隔离属性，避免替换后被 Gatekeeper 拦截。
            if (try? runner.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", staged.path])) != nil {
                try runner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        return StagedApp(appURL: staged, stagingDirectory: staging)
    }

    static func validateBundle(at app: URL, expectedVersion: AppVersion) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            throw UpdateError.invalidBundle("无法读取安装包信息")
        }
        guard plist["CFBundleIdentifier"] as? String == UpdatePaths.bundleIdentifier else {
            throw UpdateError.invalidBundle("应用标识不匹配")
        }
        guard let version = (plist["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              version == expectedVersion else {
            throw UpdateError.invalidBundle("安装包版本与发布版本不一致")
        }
    }

    /// 与 upgrade.sh 相同的布局：`update-<时间>/Data` 与 `Settings.plist`。只读取，不改动原数据。
    func backup(dataDirectory: URL, backupRoot: URL, defaultsDomain: String, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = backupRoot.appendingPathComponent(
            "update-\(formatter.string(from: now))-\(UUID().uuidString.prefix(6))", isDirectory: true
        )
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dataDirectory.path) {
                try runner.run("/usr/bin/ditto", [dataDirectory.path, directory.appendingPathComponent("Data").path])
            }
            if (try? runner.run("/usr/bin/defaults", ["read", defaultsDomain])) != nil {
                try runner.run("/usr/bin/defaults", ["export", defaultsDomain, directory.appendingPathComponent("Settings.plist").path])
            }
        } catch {
            throw UpdateError.backupFailed((error as? UpdateError)?.message ?? error.localizedDescription)
        }
        return directory
    }

    /// 启动独立运行的助手脚本；调用方随后退出应用，由助手完成替换并重新打开。
    func launchHelper(
        staged: StagedApp,
        target: URL,
        backup: URL,
        version: AppVersion,
        resultFile: URL = UpdatePaths.resultFile,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        let script = try UpdateHelperScript.write(to: FileManager.default.temporaryDirectory)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            script.path, String(pid), staged.appURL.path, target.path, backup.path, resultFile.path, version.description
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

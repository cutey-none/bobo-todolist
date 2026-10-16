import Foundation
@testable import QuadrantTodo

/// 真实执行 hdiutil / ditto，仅替换 codesign 的结果（测试用的假应用包没有可执行文件，无法真实签名）。
struct CodesignStubRunner: CommandRunning {
    var codesignFails = false

    func run(_ executable: String, _ arguments: [String]) throws -> String {
        if executable.hasSuffix("/codesign") {
            if codesignFails { throw UpdateError.command("codesign", "invalid signature") }
            return ""
        }
        return try ProcessCommandRunner().run(executable, arguments)
    }
}

enum UpdateTestSupport {
    /// 生成与 package-dmg.sh 结构相同的 DMG：根目录下一个 QuadrantTodo.app。
    static func makeDMG(in root: URL, version: String, bundleID: String = "com.cutey.quadranttodo") throws -> URL {
        let source = root.appendingPathComponent("image-\(UUID().uuidString)")
        let contents = source.appendingPathComponent("QuadrantTodo.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let dmg = root.appendingPathComponent("QuadrantTodo_\(version)_test.dmg")
        try ProcessCommandRunner().run("/usr/bin/hdiutil", [
            "create", "-volname", "QuadrantTodo", "-srcfolder", source.path, "-format", "UDZO", "-fs", "HFS+", dmg.path
        ])
        return dmg
    }
}

/// 供 @Sendable 进度回调写入的线程安全盒子。
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

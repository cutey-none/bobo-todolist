import XCTest
@testable import QuadrantTodo

/// 真实执行 hdiutil / ditto，仅替换 codesign 的结果（测试用的假应用包没有可执行文件，无法真实签名）。
private struct CodesignStubRunner: CommandRunning {
    var codesignFails = false

    func run(_ executable: String, _ arguments: [String]) throws -> String {
        if executable.hasSuffix("/codesign") {
            if codesignFails { throw UpdateError.command("codesign", "invalid signature") }
            return ""
        }
        return try ProcessCommandRunner().run(executable, arguments)
    }
}

final class UpdateInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 生成与 package-dmg.sh 结构相同的 DMG：根目录下一个 QuadrantTodo.app。
    private func makeDMG(version: String, bundleID: String = "com.cutey.quadranttodo") throws -> URL {
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

    private func stagingLeftovers(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".quadrant-update.") }
    }

    func testFetchReleaseReadsFileFeed() async throws {
        let feed = root.appendingPathComponent("latest.json")
        try Data(#"{"tag_name":"v0.0.2","body":"","assets":[]}"#.utf8).write(to: feed)
        let info = try await UpdateInstaller().fetchRelease(from: feed)
        XCTAssertEqual(info.tagName, "v0.0.2")
    }

    func testFetchReleaseRejectsGarbage() async throws {
        let feed = root.appendingPathComponent("latest.json")
        try Data("<html>".utf8).write(to: feed)
        do {
            _ = try await UpdateInstaller().fetchRelease(from: feed)
            XCTFail("应抛出错误")
        } catch {
            XCTAssertEqual(error as? UpdateError, .badResponse)
        }
    }

    func testDownloadCopiesFileURLAndReportsCompletion() async throws {
        let source = root.appendingPathComponent("src.bin")
        try Data("payload".utf8).write(to: source)
        let destination = root.appendingPathComponent("Downloads/out.bin")
        let reported = LockedBox<Double>(0)

        try await UpdateInstaller().download(source, to: destination) { reported.value = $0 }

        XCTAssertEqual(try Data(contentsOf: destination), Data("payload".utf8))
        XCTAssertEqual(reported.value, 1)
    }

    func testVerifyChecksumAcceptsMatchAndRejectsMismatch() throws {
        let file = root.appendingPathComponent("a.dmg")
        try Data("abc".utf8).write(to: file)
        let good = root.appendingPathComponent("good.sha256")
        try Data("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  a.dmg\n".utf8).write(to: good)
        let bad = root.appendingPathComponent("bad.sha256")
        try Data("\(String(repeating: "0", count: 64))  a.dmg\n".utf8).write(to: bad)
        let installer = UpdateInstaller()

        XCTAssertNoThrow(try installer.verifyChecksum(file: file, checksumFile: good, fileName: "a.dmg"))
        XCTAssertThrowsError(try installer.verifyChecksum(file: file, checksumFile: bad, fileName: "a.dmg")) {
            XCTAssertEqual($0 as? UpdateError, .checksumMismatch)
        }
    }

    func testStageCopiesAppNextToTarget() throws {
        let dmg = try makeDMG(version: "0.0.2")
        let apps = root.appendingPathComponent("Apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let target = apps.appendingPathComponent("QuadrantTodo.app")

        let staged = try UpdateInstaller(runner: CodesignStubRunner())
            .stage(dmg: dmg, nextTo: target, expectedVersion: AppVersion("0.0.2")!)

        XCTAssertEqual(staged.stagingDirectory.deletingLastPathComponent().standardizedFileURL, apps.standardizedFileURL)
        XCTAssertTrue(staged.stagingDirectory.lastPathComponent.hasPrefix(".quadrant-update."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.appURL.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "暂存不应触碰目标应用")
    }

    func testStageRejectsVersionMismatchAndCleansUp() throws {
        let dmg = try makeDMG(version: "0.0.3")
        let target = root.appendingPathComponent("QuadrantTodo.app")

        XCTAssertThrowsError(
            try UpdateInstaller(runner: CodesignStubRunner()).stage(dmg: dmg, nextTo: target, expectedVersion: AppVersion("0.0.2")!)
        ) { error in
            guard case .invalidBundle = error as? UpdateError else { return XCTFail("应为 invalidBundle：\(error)") }
        }
        XCTAssertEqual(try stagingLeftovers(in: root), [])
    }

    func testStageRejectsForeignBundleIdentifier() throws {
        let dmg = try makeDMG(version: "0.0.2", bundleID: "com.example.other")
        let target = root.appendingPathComponent("QuadrantTodo.app")

        XCTAssertThrowsError(
            try UpdateInstaller(runner: CodesignStubRunner()).stage(dmg: dmg, nextTo: target, expectedVersion: AppVersion("0.0.2")!)
        )
        XCTAssertEqual(try stagingLeftovers(in: root), [])
    }

    func testStageRejectsInvalidSignatureAndCleansUp() throws {
        let dmg = try makeDMG(version: "0.0.2")
        let target = root.appendingPathComponent("QuadrantTodo.app")

        XCTAssertThrowsError(
            try UpdateInstaller(runner: CodesignStubRunner(codesignFails: true))
                .stage(dmg: dmg, nextTo: target, expectedVersion: AppVersion("0.0.2")!)
        )
        XCTAssertEqual(try stagingLeftovers(in: root), [])
    }

    func testBackupCopiesDataDirectoryWithSpacesAndChinese() throws {
        let data = root.appendingPathComponent("数据 目录")
        try FileManager.default.createDirectory(at: data.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try Data("store".utf8).write(to: data.appendingPathComponent("Tasks.store"))
        try Data("png".utf8).write(to: data.appendingPathComponent("Attachments/a.png"))
        let backupRoot = root.appendingPathComponent("Backups")

        let backup = try UpdateInstaller().backup(
            dataDirectory: data, backupRoot: backupRoot, defaultsDomain: "com.cutey.quadranttodo.tests.absent"
        )

        XCTAssertTrue(backup.lastPathComponent.hasPrefix("update-"))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Data/Tasks.store")), Data("store".utf8))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Data/Attachments/a.png")), Data("png".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Settings.plist").path))
        XCTAssertEqual(try Data(contentsOf: data.appendingPathComponent("Tasks.store")), Data("store".utf8), "原数据不变")
    }

    func testBackupWithoutDataDirectoryStillCreatesFolder() throws {
        let backup = try UpdateInstaller().backup(
            dataDirectory: root.appendingPathComponent("missing"),
            backupRoot: root.appendingPathComponent("Backups"),
            defaultsDomain: "com.cutey.quadranttodo.tests.absent"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Data").path))
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

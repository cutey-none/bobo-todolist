import XCTest
@testable import QuadrantTodo

final class UpdateHelperScriptTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("helper-\(UUID().uuidString)/My Apps 中文")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func makeApp(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent("Contents/marker"))
    }

    private func marker(_ app: URL) -> String? {
        (try? Data(contentsOf: app.appendingPathComponent("Contents/marker"))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func startSleeper(_ seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    /// 运行助手脚本并等待结束，返回退出码。
    private func runHelper(pid: Int32, staged: URL, target: URL, backup: URL, result: URL, wait: String = "5") throws -> Int32 {
        let script = try UpdateHelperScript.write(to: root.deletingLastPathComponent())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, String(pid), staged.path, target.path, backup.path, result.path, "0.0.2"]
        var env = ProcessInfo.processInfo.environment
        env["QT_UPDATE_OPEN_CMD"] = "/usr/bin/true"
        env["QT_UPDATE_WAIT_SECONDS"] = wait
        process.environment = env
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func readResult(_ url: URL) throws -> UpdateResult {
        try JSONDecoder().decode(UpdateResult.self, from: Data(contentsOf: url))
    }

    func testHelperReplacesAppAtPathWithSpaces() throws {
        let target = root.appendingPathComponent("QuadrantTodo.app")
        let staging = root.appendingPathComponent(".quadrant-update.test")
        let staged = staging.appendingPathComponent("QuadrantTodo.app")
        let backup = root.appendingPathComponent("备份 dir")
        let result = root.appendingPathComponent("result.json")
        try makeApp(at: target, marker: "old")
        try makeApp(at: staged, marker: "new")

        let sleeper = try startSleeper("0.3")
        let status = try runHelper(pid: sleeper.processIdentifier, staged: staged, target: target, backup: backup, result: result)

        XCTAssertEqual(status, 0)
        XCTAssertEqual(marker(target), "new")
        XCTAssertEqual(marker(backup.appendingPathComponent("Previous.app")), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try readResult(result), UpdateResult(status: "success", version: "0.0.2", backup: backup.path))
    }

    func testHelperGivesUpWhenOldProcessDoesNotExit() throws {
        let target = root.appendingPathComponent("QuadrantTodo.app")
        let staging = root.appendingPathComponent(".quadrant-update.test")
        let staged = staging.appendingPathComponent("QuadrantTodo.app")
        let backup = root.appendingPathComponent("backup")
        let result = root.appendingPathComponent("result.json")
        try makeApp(at: target, marker: "old")
        try makeApp(at: staged, marker: "new")

        let sleeper = try startSleeper("10")
        defer { sleeper.terminate() }
        let status = try runHelper(pid: sleeper.processIdentifier, staged: staged, target: target, backup: backup, result: result, wait: "1")

        XCTAssertEqual(status, 1)
        XCTAssertEqual(marker(target), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try readResult(result).status, "timeout")
    }

    func testHelperRestoresOldAppWhenPlacementFails() throws {
        let target = root.appendingPathComponent("QuadrantTodo.app")
        let staging = root.appendingPathComponent(".quadrant-update.test")
        let missingStaged = staging.appendingPathComponent("QuadrantTodo.app")
        let backup = root.appendingPathComponent("backup")
        let result = root.appendingPathComponent("result.json")
        try makeApp(at: target, marker: "old")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let sleeper = try startSleeper("0.1")
        let status = try runHelper(pid: sleeper.processIdentifier, staged: missingStaged, target: target, backup: backup, result: result)

        XCTAssertEqual(status, 1)
        XCTAssertEqual(marker(target), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Previous.app").path))
        XCTAssertEqual(try readResult(result).status, "restored")
    }
}

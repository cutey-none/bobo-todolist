import XCTest
@testable import QuadrantTodo

@MainActor
final class UpdateControllerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("controller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func controller(feed json: String?, current: String? = "0.0.1", arch: String = "arm64") throws -> UpdateController {
        let feed = root.appendingPathComponent("latest.json")
        if let json { try Data(json.utf8).write(to: feed) }
        return UpdateController(
            installer: UpdateInstaller(),
            feedURL: feed,
            currentVersion: current.flatMap(AppVersion.init),
            architecture: arch,
            appURL: root.appendingPathComponent("QuadrantTodo.app")
        )
    }

    private let release002 = #"""
    {"tag_name":"v0.0.2","body":"新增应用内更新","assets":[
      {"name":"QuadrantTodo_0.0.2_arm64.dmg","browser_download_url":"https://example.com/a.dmg"},
      {"name":"QuadrantTodo_0.0.2_arm64.dmg.sha256","browser_download_url":"https://example.com/a.dmg.sha256"}]}
    """#

    func testNewerReleaseBecomesAvailable() async throws {
        let updater = try controller(feed: release002)
        updater.check()
        XCTAssertEqual(updater.phase, .checking)
        await updater.waitForCurrentTask()
        XCTAssertEqual(updater.phase, .available(version: "0.0.2", notes: "新增应用内更新"))
    }

    func testSameVersionIsUpToDate() async throws {
        let updater = try controller(feed: release002, current: "0.0.2")
        updater.check()
        await updater.waitForCurrentTask()
        XCTAssertEqual(updater.phase, .upToDate)
    }

    func testMissingArchitectureIsReported() async throws {
        let updater = try controller(feed: release002, arch: "x86_64")
        updater.check()
        await updater.waitForCurrentTask()
        XCTAssertEqual(updater.phase, .unavailableForArch(version: "0.0.2"))
    }

    func testUnrecognizedTagFails() async throws {
        let updater = try controller(feed: #"{"tag_name":"nightly","body":null,"assets":[]}"#)
        updater.check()
        await updater.waitForCurrentTask()
        XCTAssertEqual(updater.phase, .failed(UpdateError.unrecognizedVersion.message))
    }

    func testUnreadableFeedFails() async throws {
        let updater = try controller(feed: nil)
        updater.check()
        await updater.waitForCurrentTask()
        guard case .failed = updater.phase else { return XCTFail("应为 failed：\(updater.phase)") }
    }

    func testUnknownCurrentVersionFailsWithoutNetwork() throws {
        let updater = try controller(feed: release002, current: nil)
        updater.check()
        XCTAssertEqual(updater.phase, .failed(UpdateError.unrecognizedVersion.message))
    }

    /// 用户点「升级」后在下载期间又开始编辑：替换前必须再次检查，不能退出应用丢掉正在输入的内容。
    func testEditingStartedDuringDownloadStopsBeforeQuitting() async throws {
        let dmg = try UpdateTestSupport.makeDMG(in: root, version: "0.0.2")
        let sums = root.appendingPathComponent("sums.sha256")
        try Data("\(try UpdateChecksum.sha256Hex(of: dmg))\n".utf8).write(to: sums)
        let feed = root.appendingPathComponent("latest.json")
        try Data("""
        {"tag_name":"v0.0.2","body":"","assets":[
          {"name":"QuadrantTodo_0.0.2_arm64.dmg","browser_download_url":"\(dmg.absoluteString)"},
          {"name":"QuadrantTodo_0.0.2_arm64.dmg.sha256","browser_download_url":"\(sums.absoluteString)"}]}
        """.utf8).write(to: feed)
        let apps = root.appendingPathComponent("Apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)

        var probes = 0
        var terminated = false
        let updater = UpdateController(
            installer: UpdateInstaller(runner: CodesignStubRunner()),
            feedURL: feed,
            currentVersion: AppVersion("0.0.1"),
            architecture: "arm64",
            appURL: apps.appendingPathComponent("QuadrantTodo.app"),
            locations: .init(
                downloads: root.appendingPathComponent("Downloads"),
                data: root.appendingPathComponent("data"),
                backupRoot: root.appendingPathComponent("Backups"),
                resultFile: root.appendingPathComponent("result.json")
            ),
            editingProbe: {
                probes += 1
                return (isEditing: probes > 1, drafts: [])
            },
            terminate: { terminated = true }
        )

        updater.check()
        await updater.waitForCurrentTask()
        updater.install()
        await updater.waitForCurrentTask()

        XCTAssertEqual(updater.phase, .failed(UpdatePreflightProblem.editing.message))
        XCTAssertFalse(terminated, "仍在编辑时不应退出应用")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: apps.path), [], "不应留下暂存副本")
    }

    func testInstallWithoutAvailableReleaseDoesNothing() throws {
        let updater = try controller(feed: release002)
        updater.install()
        XCTAssertEqual(updater.phase, .idle)
    }
}

final class UpdateTerminationTests: XCTestCase {
    func testQuitIsHeldOnlyWhilePreparing() {
        XCTAssertFalse(UpdateController.allowsTermination(during: .preparing))
        XCTAssertTrue(UpdateController.allowsTermination(during: .downloading(0.5)))
        XCTAssertTrue(UpdateController.allowsTermination(during: .relaunching))
        XCTAssertTrue(UpdateController.allowsTermination(during: .idle))
    }
}

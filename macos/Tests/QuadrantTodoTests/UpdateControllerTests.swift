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

    func testInstallWithoutAvailableReleaseDoesNothing() throws {
        let updater = try controller(feed: release002)
        updater.install()
        XCTAssertEqual(updater.phase, .idle)
    }
}

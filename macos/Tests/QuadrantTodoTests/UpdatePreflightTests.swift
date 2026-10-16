import XCTest
@testable import QuadrantTodo

final class UpdatePreflightTests: XCTestCase {
    private func input(
        isEditing: Bool = false,
        hasDrafts: Bool = false,
        path: String = "/Users/me/Applications/QuadrantTodo.app",
        readOnly: Bool = false,
        writable: Bool = true
    ) -> UpdatePreflightInput {
        UpdatePreflightInput(
            isEditing: isEditing,
            hasDrafts: hasDrafts,
            appURL: URL(fileURLWithPath: path),
            isOnReadOnlyVolume: readOnly,
            isParentWritable: writable
        )
    }

    func testInstalledWritableIdleAppPasses() {
        XCTAssertNil(UpdatePreflight.check(input()))
    }

    func testOpenEditorBlocksFirst() {
        XCTAssertEqual(UpdatePreflight.check(input(isEditing: true, hasDrafts: true, writable: false)), .editing)
    }

    func testDraftsBlock() {
        XCTAssertEqual(UpdatePreflight.check(input(hasDrafts: true)), .unsavedDrafts)
    }

    func testRunningFromDiskImageOrTranslocationIsNotInstalled() {
        XCTAssertEqual(UpdatePreflight.check(input(path: "/Volumes/QuadrantTodo/QuadrantTodo.app", readOnly: true)), .notInstalled)
        XCTAssertEqual(
            UpdatePreflight.check(input(path: "/private/var/folders/x/AppTranslocation/ABC/d/QuadrantTodo.app")),
            .notInstalled
        )
    }

    func testBareExecutableIsNotInstalled() {
        XCTAssertEqual(UpdatePreflight.check(input(path: "/repo/macos/.build/debug")), .notInstalled)
    }

    func testUnwritableParentIsReportedWithDirectory() {
        XCTAssertEqual(
            UpdatePreflight.check(input(path: "/Applications/QuadrantTodo.app", writable: false)),
            .notWritable("/Applications")
        )
    }

    func testInputTreatsWhitespaceDraftsAsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("preflight-\(UUID().uuidString)")
        let app = dir.appendingPathComponent("QuadrantTodo.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let blank = UpdatePreflight.input(appURL: app, isEditing: false, drafts: ["", "  \n"])
        XCTAssertFalse(blank.hasDrafts)
        XCTAssertTrue(blank.isParentWritable)
        XCTAssertFalse(blank.isOnReadOnlyVolume)
        XCTAssertTrue(UpdatePreflight.input(appURL: app, isEditing: false, drafts: ["买牛奶"]).hasDrafts)
    }

    func testMessagesAreUserFacing() {
        XCTAssertTrue(UpdatePreflightProblem.notWritable("/Applications").message.contains("/Applications"))
        XCTAssertTrue(UpdatePreflightProblem.notInstalled.message.contains("应用程序"))
    }
}

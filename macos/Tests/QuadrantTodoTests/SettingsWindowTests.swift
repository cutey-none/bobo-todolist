import AppKit
import SwiftUI
import XCTest
@testable import QuadrantTodo

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testShowOpensVisibleWindowAndReusesIt() throws {
        let controller = SettingsWindowController { Text("设置内容") }
        controller.show()
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible, "Settings window must appear when opened from the menu bar")
        XCTAssertEqual(window.title, "设置")

        window.close()
        controller.show()
        XCTAssertTrue(controller.window === window, "Reopening reuses the same settings window")
        XCTAssertTrue(window.isVisible)
        window.close()
    }
}

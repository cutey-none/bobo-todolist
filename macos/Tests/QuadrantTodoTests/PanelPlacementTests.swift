import AppKit
import XCTest
@testable import QuadrantTodo

@MainActor
final class PanelPlacementTests: XCTestCase {
    func testEveryCollapsedEdgeBypassesAppKitFrameConstraints() {
        let visible = NSRect(x: 0, y: 70, width: 1440, height: 805)
        let frames = [
            NSRect(x: -642, y: 200, width: 680, height: 560),
            NSRect(x: 1402, y: 200, width: 680, height: 560),
            NSRect(x: 300, y: 837, width: 680, height: 560),
            NSRect(x: 300, y: -452, width: 680, height: 560)
        ]
        for frame in frames {
            XCTAssertTrue(PanelController.requiresDirectPlacement(frame, visibleFrame: visible))
        }
        XCTAssertFalse(PanelController.requiresDirectPlacement(
            NSRect(x: 300, y: 200, width: 680, height: 560), visibleFrame: visible))
    }
}

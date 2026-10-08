import AppKit
import XCTest
import SwiftUI
@testable import QuadrantTodo

@MainActor
final class PanelPlacementTests: XCTestCase {
    func testDragToPhysicalEdgesSnapsAcrossMenuBarAndDock() {
        let visible = NSRect(x: 0, y: 62, width: 1920, height: 988)
        // Header dragged to the physical screen edge; window itself need not be near visibleFrame.
        XCTAssertEqual(PanelController.snapEdge(mouse: NSPoint(x: 960, y: 1079),
                        frame: NSRect(x: 620, y: 520, width: 680, height: 560), visible: visible), .top)
        XCTAssertEqual(PanelController.snapEdge(mouse: NSPoint(x: 960, y: 1),
                        frame: NSRect(x: 620, y: -529, width: 680, height: 560), visible: visible), .bottom)
        XCTAssertNil(PanelController.snapEdge(mouse: NSPoint(x: 960, y: 600),
                     frame: NSRect(x: 620, y: 300, width: 680, height: 560), visible: visible))
    }

    func testTopAndBottomWindowSizeAndHoverRoundTrip() {
        _ = NSApplication.shared
        for edge in [EdgeSide.top, .bottom] {
            let domain = "PanelPlacementTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            let settings = SettingsStore(defaults: defaults)
            settings.edge = edge
            let persistence = PersistenceController(inMemory: true)
            let state = AppState(persistence: persistence, settings: settings)
            let root = RootView(state: state, settings: settings).modelContainer(persistence.container)
            let controller = PanelController(state: state, settings: settings, rootView: AnyView(root))
            state.controller = controller
            defer { controller.panel.orderOut(nil) }
            // Initial size publishers used to restore the full content size after collapse.
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            XCTAssertEqual(controller.panel.frame.size, NSSize(width: 296, height: 38))
            let rail = controller.panel.frame
            let mouse = NSPoint(x: rail.midX, y: rail.midY)
            let start = Date()
            controller.updateMouse(at: mouse, now: start)
            XCTAssertFalse(state.isExpanded)
            controller.updateMouse(at: mouse, now: start.addingTimeInterval(Metrics.hoverExpandDelay + 0.01))
            XCTAssertTrue(state.isExpanded)
            controller.applyLayout(animated: false)
            XCTAssertEqual(controller.panel.frame.size, settings.panelSize)
            let outside = NSPoint(x: -10000, y: -10000)
            controller.updateMouse(at: outside, now: start.addingTimeInterval(1))
            controller.updateMouse(at: outside, now: start.addingTimeInterval(2))
            XCTAssertFalse(state.isExpanded)
            XCTAssertEqual(controller.panel.frame.size, NSSize(width: 296, height: 38))
        }
    }

    func testCollapsedWindowsStayInsideWorkAreaAtEveryEdge() {
        let visible = NSRect(x: 0, y: 62, width: 1920, height: 988)
        let hiddenFrames: [(EdgeSide, NSRect)] = [
            (.left, NSRect(x: -642, y: 300, width: 680, height: 560)),
            (.right, NSRect(x: 1882, y: 300, width: 680, height: 560)),
            (.top, NSRect(x: 620, y: 1012, width: 680, height: 560)),
            (.bottom, NSRect(x: 620, y: -460, width: 680, height: 560))
        ]
        for (edge, hidden) in hiddenFrames {
            let rail = PanelController.collapsedFrame(edge: edge, panelFrame: hidden)
            XCTAssertTrue(visible.contains(rail), "\(edge): \(rail)")
            XCTAssertEqual(rail.size, edge.isVertical
                           ? NSSize(width: 38, height: 296) : NSSize(width: 296, height: 38))
            switch edge {
            case .left: XCTAssertEqual(rail.minX, visible.minX)
            case .right: XCTAssertEqual(rail.maxX, visible.maxX)
            case .top: XCTAssertEqual(rail.maxY, visible.maxY)
            case .bottom: XCTAssertEqual(rail.minY, visible.minY)
            }
        }
    }

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

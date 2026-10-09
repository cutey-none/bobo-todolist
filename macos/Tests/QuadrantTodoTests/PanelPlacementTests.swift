import AppKit
import XCTest
import SwiftUI
@testable import QuadrantTodo

@MainActor
final class PanelPlacementTests: XCTestCase {
    func testStationaryPointerAtDockedOuterEdgeDoesNotCycle() {
        _ = NSApplication.shared
        for edge in [EdgeSide.left, .right, .top, .bottom] {
            let domain = "EdgeHover.\(UUID().uuidString)"
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let rail = controller.panel.frame
            let mouse: NSPoint
            switch edge {
            case .left: mouse = NSPoint(x: rail.minX + 1, y: rail.midY)
            case .right: mouse = NSPoint(x: rail.maxX - 1, y: rail.midY)
            case .top: mouse = NSPoint(x: rail.midX, y: rail.maxY - 1)
            case .bottom: mouse = NSPoint(x: rail.midX, y: rail.minY + 1)
            }
            let start = Date()
            controller.updateMouse(at: mouse, now: start)
            controller.updateMouse(at: mouse, now: start.addingTimeInterval(0.2))
            XCTAssertTrue(state.isExpanded)
            controller.applyLayout(animated: false)
            for step in 1...20 {
                controller.updateMouse(at: mouse, now: start.addingTimeInterval(0.2 + Double(step) * 0.2))
                XCTAssertTrue(state.isExpanded, "\(edge) cycled at stationary pointer step \(step)")
            }
            let outside = NSPoint(x: -10000, y: -10000)
            controller.updateMouse(at: outside, now: start.addingTimeInterval(5))
            controller.updateMouse(at: outside, now: start.addingTimeInterval(6))
            XCTAssertFalse(state.isExpanded, "\(edge) must still collapse after leaving the edge region")
        }
    }

    func testPanelDisplayDoesNotFollowFocusOnAnotherDisplay() {
        let screens = [NSRect(x: 0, y: 0, width: 1920, height: 1080),
                       NSRect(x: 1920, y: 0, width: 1440, height: 900)]
        let railOnB = NSRect(x: 3322, y: 300, width: 38, height: 296)
        XCTAssertEqual(PanelController.placementScreenIndex(panelFrame: railOnB,
                       mouse: NSPoint(x: 500, y: 500), screens: screens), 1)
        XCTAssertEqual(PanelController.placementScreenIndex(panelFrame: nil,
                       mouse: NSPoint(x: 2100, y: 500), screens: screens), 1)
        // If B is disconnected, recover on an available display.
        XCTAssertEqual(PanelController.placementScreenIndex(panelFrame: railOnB,
                       mouse: NSPoint(x: 500, y: 500), screens: [screens[0]]), 0)
    }

    func testFullScreenOnADoesNotCoverBInHorizontalOrVerticalArrangements() {
        let a = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let aQuartz = PanelController.quartzScreenFrame(a, primaryMaxY: 1080)
        for b in [NSRect(x: 1920, y: 0, width: 1440, height: 900),
                  NSRect(x: 0, y: 1080, width: 1440, height: 900),
                  NSRect(x: 0, y: -900, width: 1440, height: 900)] {
            let bQuartz = PanelController.quartzScreenFrame(b, primaryMaxY: 1080)
            XCTAssertFalse(PanelController.coversScreen(window: aQuartz, screen: bQuartz))
            XCTAssertTrue(PanelController.coversScreen(window: bQuartz, screen: bQuartz))
        }
        XCTAssertEqual(PanelController.quartzScreenFrame(NSRect(x: 0, y: 1080, width: 1440, height: 900),
                        primaryMaxY: 1080).minY, -900)
        XCTAssertEqual(PanelController.quartzScreenFrame(NSRect(x: 0, y: -900, width: 1440, height: 900),
                        primaryMaxY: 1080).minY, 1080)
    }

    func testFullScreenRestoresCollapsedAndExpandedPanelsWithoutMovingThem() {
        _ = NSApplication.shared
        let domain = "FullScreenVisibility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults)
        let persistence = PersistenceController(inMemory: true)
        let state = AppState(persistence: persistence, settings: settings)
        let root = RootView(state: state, settings: settings).modelContainer(persistence.container)
        let controller = PanelController(state: state, settings: settings, rootView: AnyView(root))
        state.controller = controller
        defer { controller.panel.orderOut(nil) }
        for expanded in [false, true] {
            state.isExpanded = expanded
            state.isPinned = true
            controller.applyLayout(animated: false)
            let frame = controller.panel.frame
            controller.updateFullScreenVisibility(covered: true)
            XCTAssertFalse(controller.panel.isVisible)
            controller.updateFullScreenVisibility(covered: false)
            XCTAssertTrue(controller.panel.isVisible)
            XCTAssertEqual(controller.panel.frame, frame)
            XCTAssertEqual(state.isExpanded, expanded)
        }
        settings.showInFullScreen = true
        controller.updateFullScreenVisibility(covered: true)
        XCTAssertTrue(controller.panel.isVisible)
        controller.hideApp()
        controller.updateFullScreenVisibility(covered: false)
        XCTAssertFalse(controller.panel.isVisible, "Explicit hide must not be undone by app activation")
    }

    func testExpandedEdgesReceiveMouseHits() {
        _ = NSApplication.shared
        let domain = "ResizeHits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(defaults: defaults)
        settings.keepFloating(at: CGPoint(x: 300, y: 200))
        let persistence = PersistenceController(inMemory: true)
        let state = AppState(persistence: persistence, settings: settings)
        state.isExpanded = true
        state.isPinned = true
        let root = RootView(state: state, settings: settings).modelContainer(persistence.container)
        let controller = PanelController(state: state, settings: settings, rootView: AnyView(root))
        defer { controller.panel.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let content = controller.panel.contentView!
        content.layoutSubtreeIfNeeded()
        for point in [NSPoint(x: 8, y: 280), NSPoint(x: 672, y: 280),
                      NSPoint(x: 340, y: 8), NSPoint(x: 340, y: 552)] {
            let hit = content.hitTest(point)
            XCTAssertTrue(hit is ResizeHandleView, "\(point): \(String(describing: hit))")
        }
    }

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

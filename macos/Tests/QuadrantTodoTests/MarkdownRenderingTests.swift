import AppKit
import SwiftUI
import XCTest
@testable import QuadrantTodo

final class MarkdownRenderingTests: XCTestCase {
    @MainActor func testLargeDescriptionExpansionRemainsResponsive() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AttachmentStore(directory: directory)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4000, pixelsHigh: 3000,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 4000, height: 3000).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let source = try XCTUnwrap(store.save(data))
        let thumbnail = try XCTUnwrap(store.thumbnail(for: source))
        XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), 1024)
        XCTAssertEqual(CGFloat(thumbnail.width) / CGFloat(thumbnail.height), 4.0 / 3.0, accuracy: 0.01)
        var markdown = "### 长说明展开验证\n\n"
        for index in 0..<120 {
            markdown += "第 \(index) 段：" + String(repeating: "这是一段包含 **重点** 和普通文字的详细说明。", count: 5) + "\n\n"
            if index % 15 == 0 {
                let source = try XCTUnwrap(store.save(data))
                markdown += "![测试图片](\(try XCTUnwrap(store.url(for: source)).path))\n\n"
            }
        }
        let task = TaskItem(title: "长文与多图展开验证", note: markdown, quadrant: .importantUrgent)
        for attempt in 0..<2 {
            let start = CFAbsoluteTimeGetCurrent()
            let host = NSHostingView(rootView: ScrollView {
                MatrixLayout(columns: 2, minimumHeight: 500) {
                    VStack(alignment: .leading) {
                        TaskRowView(task: task, hasDescription: true, isExpanded: true,
                                    isFocused: false, isTargeted: false,
                                    onToggle: {}, onToggleExpand: {}, onEdit: {}, onDelete: {},
                                    onDropBefore: { _ in false }, onTargeted: { _ in })
                    }
                    Text("另一象限")
                    Text("下方象限")
                    Text("下方象限")
                }
            }.background(Color.white).environment(\.colorScheme, .light))
            host.frame = NSRect(x: 0, y: 0, width: 680, height: 560)
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("Description expansion \(attempt): \(elapsed) seconds")
            // 首次渲染包含 SwiftUI 冷启动开销，放宽预算；第二次才严格检查展开本身。
            XCTAssertLessThan(elapsed, attempt == 0 ? 0.5 : 0.2, "Long description blocks the main thread when expanded")
            if attempt == 1, let output = ProcessInfo.processInfo.environment["QT_RENDER_SCREENSHOT"] {
                let window = NSWindow(contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                host.layoutSubtreeIfNeeded()
                let screenshot = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: screenshot)
                try XCTUnwrap(screenshot.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: output))
                window.orderOut(nil)
            }
        }
    }
}

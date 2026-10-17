import AppKit
import SwiftUI

/// 自管的设置窗口。macOS 14 起 SwiftUI 会忽略 `showSettingsWindow:`，
/// 菜单栏应用无法可靠打开 Settings 场景，因此直接用 NSWindow 承载设置视图。
@MainActor
final class SettingsWindowController {
    private let makeContent: () -> AnyView
    private(set) var window: NSWindow?

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        makeContent = { AnyView(content()) }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

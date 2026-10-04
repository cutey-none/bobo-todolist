import AppKit

/// 菜单栏入口：展开 / 收起、钉住、设置与退出（PRD 4.3 / 4.4）。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let state: AppState
    private let settings: SettingsStore
    private weak var controller: PanelController?
    private let openSettings: () -> Void

    init(state: AppState, settings: SettingsStore, controller: PanelController, openSettings: @escaping () -> Void) {
        self.state = state
        self.settings = settings
        self.controller = controller
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "四象限待办")
            image?.isTemplate = true
            button.image = image ?? NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: "四象限待办")
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "四象限待办 · \(settings.edge.label)贴边"
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            state.toggle(focusInput: !state.isExpanded)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: state.isExpanded ? "收起面板" : "展开面板", action: #selector(togglePanel), keyEquivalent: "")
        let pinItem = menu.addItem(withTitle: state.isPinned ? "取消钉住" : "钉住面板", action: #selector(togglePin), keyEquivalent: "")
        pinItem.state = state.isPinned ? .on : .off
        menu.addItem(withTitle: "新建任务…", action: #selector(newTask), keyEquivalent: "")
        menu.addItem(.separator())

        let edgeMenu = NSMenu()
        for edge in EdgeSide.allCases {
            let item = edgeMenu.addItem(withTitle: "贴\(edge.label)", action: #selector(setEdge(_:)), keyEquivalent: "")
            item.representedObject = edge.rawValue
            item.state = settings.edge == edge ? .on : .off
        }
        let edgeItem = NSMenuItem(title: "贴边位置", action: nil, keyEquivalent: "")
        edgeItem.submenu = edgeMenu
        menu.addItem(edgeItem)

        let topItem = menu.addItem(withTitle: "窗口置顶", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        topItem.state = settings.alwaysOnTop ? .on : .off

        let fsItem = menu.addItem(withTitle: "全屏 App 时显示", action: #selector(toggleFullScreenVisibility), keyEquivalent: "")
        fsItem.state = settings.showInFullScreen ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出四象限待办", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items where item.action != nil { item.target = self }
        menu.items.forEach { item in item.submenu?.items.forEach { $0.target = self } }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePanel() { state.toggle(focusInput: !state.isExpanded) }
    @objc private func togglePin() { state.isPinned.toggle(); if state.isPinned { state.expand() } }
    @objc private func newTask() { state.expand(focusInput: true) }

    @objc private func setEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = EdgeSide(rawValue: raw) else { return }
        settings.dock(to: edge)
    }

    @objc private func toggleAlwaysOnTop() { settings.alwaysOnTop.toggle() }
    @objc private func toggleFullScreenVisibility() { settings.showInFullScreen.toggle() }
    @objc private func showSettings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

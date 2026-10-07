import AppKit
import Combine
import QuartzCore
import SwiftUI

/// 无边框浮动面板，作为贴边悬浮窗（PRD F1）。
final class EdgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 左侧 rail 需要让大部分窗口位于屏幕负坐标区域。
    /// NSWindow 默认会把这种 frame 强制拉回屏幕内（通常是 x = 10），
    /// 因此仅对这个受控贴边面板关闭系统 frame 约束。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class PanelController: NSObject {
    let panel: EdgePanel

    private let state: AppState
    private let settings: SettingsStore
    private let hosting: NSHostingView<AnyView>
    private var cancellables = Set<AnyCancellable>()
    private var collapseTimer: Timer?
    private var hoverTimer: Timer?
    private var hoverSince: Date?
    private var suppressHoverUntilMouseLeavesRail = false
    private var outsideSince: Date?
    private var fullScreenObserver: NSObjectProtocol?
    private var hiddenByUser = false
    private var isWindowDragging = false
    /// 拖动触边时会连续修改 isDocked / edge / isExpanded。
    /// 暂停这些属性各自的布局订阅，避免多个相反方向的窗口动画互相覆盖。
    private var isApplyingDragSnap = false
    private var manualDragStartOrigin: NSPoint?
    private var manualDragStartMouse: NSPoint?
    /// 正在拖动边缘调整大小：期间不响应悬停收起，也不让尺寸设置回写窗口。
    private var resizeEdges: ResizeEdges = []
    private var resizeStartFrame: NSRect?

    init(state: AppState, settings: SettingsStore, rootView: AnyView) {
        self.state = state
        self.settings = settings

        let size = settings.panelSize
        panel = EdgePanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hosting = NSHostingView(rootView: rootView)
        super.init()
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 窗口移动由 SwiftUI 标题栏 / rail 的显式 DragGesture 驱动。
        // 不使用 isMovableByWindowBackground / windowWillMove：程序主动重排
        // 也可能触发窗口 delegate，造成下一次 mouseUp 被误判为用户拖动。
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.level = settings.alwaysOnTop ? .floating : .normal

        // 面板固定尺寸，不随内容自适应：尺寸只由设置决定。
        hosting.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        panel.contentView = hosting

        bind()
        startMouseWatch()
        observeActiveApp()
        applyLayout(animated: false)
        panel.orderFrontRegardless()
    }

    // MARK: - 状态绑定

    private func bind() {
        state.$isExpanded
            .removeDuplicates()
            // 初始 false 只表示 AppState 尚未展开，不是用户点了「收起」。
            // 初始窗口位置已由 init 末尾的 applyLayout 处理；忽略它才能
            // 正确恢复上次保存的自由浮动位置。
            .dropFirst()
            .sink { [weak self] expanded in
                guard let self else { return }
                // 拖动开始时由 beginPanelDrag 无动画展开；这里的展开动画
                // 会在拖动中继续改 frame，与跟手移动互相抢位置。
                guard !self.isApplyingDragSnap, !self.isWindowDragging else { return }
                // 自由浮动窗口没有可收进的屏幕边缘。用户主动点「收起」时，
                // 先回到上一次选择的边缘，再收成 rail，避免在屏幕中央留下
                // 一个只有小 rail、却占着整块透明窗口的区域。
                if !expanded, !self.settings.isDocked {
                    let edge = self.settings.edge
                    self.settings.dock(to: edge)
                    DispatchQueue.main.async { [weak self] in
                        self?.applyLayout(expanded: false, edge: edge, animated: true)
                    }
                    return
                }
                if expanded {
                    self.hiddenByUser = false
                    self.panel.orderFrontRegardless()
                }
                self.applyLayout(expanded: expanded, animated: true)
            }
            .store(in: &cancellables)

        settings.$edge
            .removeDuplicates()
            .sink { [weak self] edge in
                // @Published 在赋值前发出通知，这里必须使用新值计算布局。
                guard let self else { return }
                guard !self.isApplyingDragSnap else { return }
                self.applyLayout(expanded: self.state.isExpanded, edge: edge, animated: true)
            }
            .store(in: &cancellables)

        settings.$isDocked
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] docked in
                guard let self else { return }
                guard !self.isApplyingDragSnap else { return }
                if docked { self.applyLayout(expanded: self.state.isExpanded, animated: true) }
            }
            .store(in: &cancellables)

        settings.$alwaysOnTop
            .removeDuplicates()
            .sink { [weak self] onTop in
                self?.panel.level = onTop ? .floating : .normal
            }
            .store(in: &cancellables)

        // 设置里改动窗口尺寸后立即生效（固定尺寸，不做动画）。
        // @Published 在赋值前发通知，必须等这一轮赋值结束再读尺寸，
        // 否则会用到旧值（宽度已改、高度还是上一次的）。
        settings.$panelWidth
            .merge(with: settings.$panelHeight)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyPanelSize() }
            }
            .store(in: &cancellables)
    }

    /// 按设置同步窗口与宿主视图尺寸，并保持当前展开 / 收起位置。
    private func applyPanelSize() {
        let size = settings.panelSize
        hosting.frame = NSRect(origin: .zero, size: size)
        applyLayout(expanded: state.isExpanded, animated: false)
    }

    // MARK: - 布局

    private var activeScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return screen }
        return panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func centerY(on screen: NSScreen) -> CGFloat {
        let visible = screen.visibleFrame
        let desired = visible.midY + CGFloat(settings.peekOffset)
        let minY = visible.minY + min(Metrics.railHeight, visible.height) / 2
        let maxY = visible.maxY - min(Metrics.railHeight, visible.height) / 2
        return min(max(desired, minY), maxY)
    }

    private func centerX(on screen: NSScreen) -> CGFloat {
        let visible = screen.visibleFrame
        let desired = visible.midX + CGFloat(settings.peekOffset)
        let half = min(Metrics.railHeight, visible.width) / 2
        return min(max(desired, visible.minX + half), visible.maxX - half)
    }

    private func frames(on screen: NSScreen, edge: EdgeSide? = nil) -> (expanded: NSRect, collapsed: NSRect) {
        let visible = screen.visibleFrame
        let size = settings.panelSize
        let side = edge ?? settings.edge
        let centerY = centerY(on: screen)
        let centerX = centerX(on: screen)
        let x: CGFloat
        let y: CGFloat
        let collapsedX: CGFloat
        let collapsedY: CGFloat
        switch side {
        case .right:
            x = visible.maxX - size.width - Metrics.screenMargin
            y = min(max(centerY - size.height / 2, visible.minY), visible.maxY - size.height)
            collapsedX = visible.maxX - Metrics.railWidth
            collapsedY = y
        case .left:
            x = visible.minX + Metrics.screenMargin
            y = min(max(centerY - size.height / 2, visible.minY), visible.maxY - size.height)
            // 左侧收起：窗口向左移出，只露出窗口最右侧的贴边条。
            collapsedX = visible.minX - (size.width - Metrics.railWidth)
            collapsedY = y
        case .top:
            x = min(max(centerX - size.width / 2, visible.minX), visible.maxX - size.width)
            y = visible.maxY - size.height - Metrics.screenMargin
            collapsedX = x
            collapsedY = visible.maxY - Metrics.railWidth
        case .bottom:
            x = min(max(centerX - size.width / 2, visible.minX), visible.maxX - size.width)
            y = visible.minY + Metrics.screenMargin
            collapsedX = x
            collapsedY = visible.minY - (size.height - Metrics.railWidth)
        }

        return (
            NSRect(x: x, y: y, width: size.width, height: size.height),
            NSRect(x: collapsedX, y: collapsedY, width: size.width, height: size.height)
        )
    }

    func applyLayout(animated: Bool) {
        applyLayout(expanded: state.isExpanded, edge: settings.edge, animated: animated)
    }

    private func applyLayout(expanded: Bool, edge: EdgeSide? = nil, animated: Bool) {
        if !settings.isDocked, let origin = settings.floatingOrigin {
            let target = clampedFloatingFrame(origin: origin, size: settings.panelSize)
            hosting.frame = NSRect(origin: .zero, size: settings.panelSize)
            panel.setFrame(target, display: true)
            return
        }
        let screen = activeScreen
        let layout = frames(on: screen, edge: edge)
        let target = expanded ? layout.expanded : layout.collapsed
        guard panel.frame != target else { return }
        // macOS 会把负 x 的 setFrame 动画强制拉回屏幕内。左侧收起必须
        // 用 setFrameOrigin 直接落位，才能真正只露出最右侧 rail。
        if target.minX < screen.visibleFrame.minX {
            if panel.frame.size != target.size { panel.setContentSize(target.size) }
            panel.setFrameOrigin(target.origin)
            return
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Metrics.expandDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    /// 收起态贴边条由 SwiftUI 手势驱动，使整个窗口跟随鼠标。
    func beginPanelDrag() {
        // 以按下时的屏幕坐标为基准，收起态先展开导致的窗口跳位不计入拖动位移。
        manualDragStartMouse = screenMouseLocation()
        isWindowDragging = true
        if !state.isExpanded {
            state.expand()
            // 贴边条开始拖动时先成为完整面板，避免带着屏外的大片隐藏区移动。
            applyLayout(expanded: true, animated: false)
        }
        manualDragStartOrigin = panel.frame.origin
        hoverSince = nil
        outsideSince = nil
    }

    /// 按屏幕坐标下的鼠标位移移动窗口。不能用 DragGesture 的 translation：
    /// 它以视图坐标计算，窗口一移动视图坐标也跟着移，位移会被抵消一半，
    /// 表现为拖动抖动、窗口跟不上鼠标而拖不到屏幕边缘。
    func dragPanel() {
        guard let origin = manualDragStartOrigin, let start = manualDragStartMouse else { return }
        let mouse = screenMouseLocation()
        panel.setFrameOrigin(NSPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y))
    }

    /// 当前鼠标事件在屏幕上的位置；取不到事件时退回系统光标位置。
    /// 用事件产生时记录的全局坐标，而不是 locationInWindow：后者要按窗口
    /// 当前位置换算，窗口刚被移动（如收起态拖动时先展开）就会算偏。
    private func screenMouseLocation() -> NSPoint {
        if let event = NSApp.currentEvent,
           [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type),
           let location = event.cgEvent?.location,
           let primary = NSScreen.screens.first {
            // CoreGraphics 以主屏左上角为原点、y 向下；AppKit 以左下角为原点。
            return NSPoint(x: location.x, y: primary.frame.maxY - location.y)
        }
        return NSEvent.mouseLocation
    }

    func endPanelDrag() {
        guard isWindowDragging else { return }
        isWindowDragging = false
        manualDragStartOrigin = nil
        manualDragStartMouse = nil
        finishWindowDrag()
    }

    // MARK: - 拖动边缘调整大小

    func beginResize(_ edges: ResizeEdges) {
        guard state.isExpanded, !edges.isEmpty else { return }
        resizeEdges = edges
        resizeStartFrame = panel.frame
        manualDragStartMouse = screenMouseLocation()
        outsideSince = nil
    }

    /// 被拖动的边跟随鼠标，对边保持不动；尺寸夹在设置允许的范围内。
    func resize() {
        guard let start = resizeStartFrame, let startMouse = manualDragStartMouse else { return }
        let mouse = screenMouseLocation()
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        var width = start.width
        var height = start.height
        if resizeEdges.contains(.left) { width -= dx }
        if resizeEdges.contains(.right) { width += dx }
        if resizeEdges.contains(.top) { height += dy }
        if resizeEdges.contains(.bottom) { height -= dy }
        let size = SettingsStore.clampPanelSize(CGSize(width: width, height: height))
        // AppKit 原点在左下角：拖左边 / 下边时，右边 / 上边保持不动。
        let x = resizeEdges.contains(.left) ? start.maxX - size.width : start.minX
        let y = resizeEdges.contains(.bottom) ? start.maxY - size.height : start.minY
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func endResize() {
        guard !resizeEdges.isEmpty else { return }
        resizeEdges = []
        resizeStartFrame = nil
        manualDragStartMouse = nil
        let frame = panel.frame
        // 先记下位置，再写尺寸：尺寸变化会触发一次重新布局，必须落在用户松手的位置上。
        if settings.isDocked {
            let visible = (panel.screen ?? activeScreen).visibleFrame
            let offset = settings.edge.isVertical ? frame.midY - visible.midY : frame.midX - visible.midX
            settings.peekOffset = Double(max(-900, min(900, offset)))
        } else {
            settings.keepFloating(at: frame.origin)
        }
        settings.setPanelSize(width: frame.width, height: frame.height)
    }

    /// 松手时只在鼠标或窗口确实进入屏幕边带时磁吸；否则保留自由位置。
    private func finishWindowDrag() {
        let mouse = screenMouseLocation()
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(mouse) })
            ?? panel.screen ?? activeScreen
        let visible = screen.visibleFrame
        let frame = panel.frame
        let threshold = Metrics.edgeSnapThreshold

        // 同时照顾两种直觉：把鼠标拖进屏幕边带，或把窗口外缘准确贴到边缘。
        // 未进入边带时绝不按“最近边”吸附。
        let candidates: [(EdgeSide, CGFloat)] = [
            (.left, min(abs(mouse.x - visible.minX), abs(frame.minX - visible.minX))),
            (.right, min(abs(visible.maxX - mouse.x), abs(visible.maxX - frame.maxX))),
            (.top, min(abs(visible.maxY - mouse.y), abs(visible.maxY - frame.maxY))),
            (.bottom, min(abs(mouse.y - visible.minY), abs(frame.minY - visible.minY)))
        ]
        let touchedEdges = candidates.filter { $0.1 <= threshold }
        if let nearest = touchedEdges.min(by: { $0.1 < $1.1 }) {
            let offset = nearest.0.isVertical ? frame.midY - visible.midY : frame.midX - visible.midX
            settings.peekOffset = Double(max(-900, min(900, offset)))
            // 明确写入最终状态，再执行唯一一次收起布局。这里不依赖
            // AppState.collapse() 的 guard 或下一轮 runloop，避免跨边拖动时
            // edge / isDocked 的同步通知把最终 rail frame 覆盖掉。
            isApplyingDragSnap = true
            settings.isDocked = true
            settings.edge = nearest.0
            state.isPinned = false
            state.isExpanded = false
            state.focusedTaskID = nil
            isApplyingDragSnap = false
            // 松手时鼠标通常仍压在刚出现的 rail 上；若立刻响应悬停，
            // 120ms 后窗口会重新展开，用户会误以为没有吸附。
            suppressHoverUntilMouseLeavesRail = true
            applyLayout(expanded: false, edge: nearest.0, animated: true)
        } else {
            // 未进入磁吸区时保持用户位置，但夹在可见区内，避免窗口无法再次操作。
            let safeX = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
            let safeY = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
            let origin = NSPoint(x: safeX, y: safeY)
            panel.setFrameOrigin(origin)
            settings.keepFloating(at: origin)
            if !state.isExpanded { state.expand() }
        }
    }

    private func clampedFloatingFrame(origin: CGPoint, size: CGSize) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(origin) }) ?? panel.screen ?? activeScreen
        let visible = screen.visibleFrame
        let x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func focusPanelIfNeeded() {
        // 用户明确要输入时（新建 / 编辑）才激活并让面板成为键盘焦点，
        // 单纯悬停展开不会抢焦点。
        if !NSApp.isActive { NSApp.activate() }
        if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
        if !panel.isKeyWindow { panel.makeKey() }
    }

    func hideApp() {
        hiddenByUser = true
        state.isExpanded = false
        state.isPinned = false
        panel.orderOut(nil)
    }

    func showApp(expanded: Bool) {
        hiddenByUser = false
        applyLayout(animated: false)
        panel.orderFrontRegardless()
        if expanded { state.expand() }
    }

    // MARK: - 悬停展开 / 移出收起

    private func startMouseWatch() {
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        collapseTimer = timer
    }

    private func tick() {
        guard !hiddenByUser else { return }
        guard !isWindowDragging, resizeEdges.isEmpty else { return }
        guard settings.isDocked else { return }

        let mouse = NSEvent.mouseLocation

        guard state.isExpanded else {
            outsideSince = nil
            let hoveringRail = railScreenRect().contains(mouse)
            if suppressHoverUntilMouseLeavesRail {
                hoverSince = nil
                if !hoveringRail { suppressHoverUntilMouseLeavesRail = false }
                return
            }
            // 悬停贴边条 120ms 后展开（PRD 4.4）。
            if hoveringRail {
                let since = hoverSince ?? Date()
                hoverSince = since
                if Date().timeIntervalSince(since) >= Metrics.hoverExpandDelay {
                    hoverSince = nil
                    state.expand()
                }
            } else {
                hoverSince = nil
            }
            return
        }

        hoverSince = nil
        if ProcessInfo.processInfo.environment["QT_KEEP_OPEN"] == "1" { outsideSince = nil; return }
        guard !state.isPinned, !state.isDraggingTask else { outsideSince = nil; return }
        // 输入行有内容或正在编辑事项时保持展开，避免打断录入。
        if state.hasUnsubmittedDraft || state.editing != nil {
            outsideSince = nil
            return
        }

        let visible = visibleFrameOfPanel()
        if visible.contains(mouse) {
            outsideSince = nil
        } else {
            let since = outsideSince ?? Date()
            outsideSince = since
            // 正在看展开的描述、或有可撤销提示时多等一会儿，手滑出面板不会立刻收起。
            let busy = state.expandedTaskID != nil || state.notice?.action != nil || !state.pendingCompletionIDs.isEmpty
            let delay = busy ? Metrics.busyCollapseDelay : Metrics.hoverCollapseDelay
            if Date().timeIntervalSince(since) >= delay {
                state.collapse()
                outsideSince = nil
            }
        }
    }

    private func visibleFrameOfPanel() -> NSRect {
        let screen = activeScreen.visibleFrame
        return panel.frame.intersection(screen).insetBy(dx: -2, dy: -2)
    }

    /// 收起态下贴边条在屏幕上的可点击区域。
    private func railScreenRect() -> NSRect {
        let collapsed = frames(on: activeScreen).collapsed
        switch settings.edge {
        case .right:
            return NSRect(x: collapsed.minX, y: collapsed.midY - Metrics.railHeight / 2, width: Metrics.railWidth, height: Metrics.railHeight).insetBy(dx: -2, dy: -2)
        case .left:
            return NSRect(x: collapsed.maxX - Metrics.railWidth, y: collapsed.midY - Metrics.railHeight / 2, width: Metrics.railWidth, height: Metrics.railHeight).insetBy(dx: -2, dy: -2)
        case .top:
            return NSRect(x: collapsed.midX - Metrics.railHeight / 2, y: collapsed.minY, width: Metrics.railHeight, height: Metrics.railWidth).insetBy(dx: -2, dy: -2)
        case .bottom:
            return NSRect(x: collapsed.midX - Metrics.railHeight / 2, y: collapsed.maxY - Metrics.railWidth, width: Metrics.railHeight, height: Metrics.railWidth).insetBy(dx: -2, dy: -2)
        }
    }

    /// 悬停在贴边条上：120ms 防误触后展开。
    func railHoverChanged(_ hovering: Bool) {
        hoverTimer?.invalidate()
        guard hovering, !suppressHoverUntilMouseLeavesRail, !state.isExpanded, !hiddenByUser else { return }
        let timer = Timer(timeInterval: Metrics.hoverExpandDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.state.isExpanded else { return }
                self.state.expand()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    // MARK: - 其他 App 全屏时隐藏（PRD 4.3）

    private func observeActiveApp() {
        fullScreenObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluateFullScreen() }
        }
    }

    private func evaluateFullScreen() {
        guard !settings.showInFullScreen, !hiddenByUser else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let screen = activeScreen
        let covering = isAnotherAppCoveringFullScreen(screen: screen)
        if covering {
            panel.orderOut(nil)
        } else if !state.isExpanded {
            panel.orderFrontRegardless()
            applyLayout(animated: false)
        }
    }

    private func isAnotherAppCoveringFullScreen(screen: NSScreen) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID != myPID,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let tolerance: CGFloat = 4
            if abs(bounds.minX - screen.frame.minX) < tolerance,
               abs(bounds.minY - screen.frame.minY) < tolerance,
               abs(bounds.width - screen.frame.width) < tolerance,
               abs(bounds.height - screen.frame.height) < tolerance {
                return true
            }
        }
        return false
    }
}

/// 正在拖动的窗口边；角落同时包含两条边。
struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let top = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)
}

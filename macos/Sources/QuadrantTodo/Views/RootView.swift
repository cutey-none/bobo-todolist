import AppKit
import SwiftData
import SwiftUI

/// 根视图：贴边条与展开面板共用同一个窗口，靠窗口位移实现「滑出 / 收回」。
struct RootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: SettingsStore
    @Query private var allTasks: [TaskItem]
    private var describedTaskIDs: Set<UUID> {
        repository.describedTaskIDs(from: allTasks)
    }

    @State private var eventMonitor: Any?
    @ObservedObject private var ticker = MinuteTicker()

    private var repository: TaskRepository { state.repository }

    var body: some View {
        ZStack {
            bodyView
                .frame(width: settings.panelWidth - 16, height: settings.panelHeight - 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bodyAlignment)
                .padding(bodyEdgePadding)
                .opacity(state.isExpanded ? 1 : 0)
                .scaleEffect(state.isExpanded ? 1 : 0.985, anchor: .center)
                .animation(.easeOut(duration: 0.18), value: state.isExpanded)

            RailView(
                counts: activeCounts,
                total: activeCounts.values.reduce(0, +),
                edge: settings.edge,
                onHover: { state.controller?.railHoverChanged($0) },
                onDragBegan: { state.controller?.beginPanelDrag() },
                onDrag: { state.controller?.dragPanel() },
                onDragEnded: { state.controller?.endPanelDrag() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: railAlignment)
            .opacity(state.isExpanded ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: state.isExpanded)
            .allowsHitTesting(!state.isExpanded)
        }
        .frame(width: settings.panelWidth, height: settings.panelHeight)
        .overlay(alignment: .bottom) { undoToast }
        .overlay(alignment: .top) { noticeBanner }
        .animation(.easeOut(duration: 0.18), value: state.notice)
        .overlay { editOverlay }
        .onAppear(perform: installEventMonitor)
        .onDisappear { removeEventMonitor() }
    }

    // MARK: - 子视图

    private var bodyView: some View {
        PanelBodyView(
            state: state,
            today: ticker.now,
            activeCounts: activeCounts,
            completedCounts: completedCounts,
            activeTasks: activeByQuadrant,
            completedTasks: completedByQuadrant,
            describedTaskIDs: describedTaskIDs,
            onToggle: { state.toggleCompletion($0) },
            onEdit: { task in
                state.controller?.focusPanelIfNeeded()
                withAnimation(.easeOut(duration: 0.15)) { state.editing = task }
            },
            onDrop: handleDrop,
            onCollapse: { state.collapse() },
            onWindowDragBegan: { state.controller?.beginPanelDrag() },
            onWindowDrag: { state.controller?.dragPanel() },
            onWindowDragEnded: { state.controller?.endPanelDrag() }
        )
    }

    @ViewBuilder
    private var undoToast: some View {
        if let undo = state.undo, state.isExpanded {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                Text("已删除「\(undo.title)」")
                    .font(.system(size: 11))
                    .lineLimit(1)
                if state.undoQueue.count > 1 {
                    Text("另有 \(state.undoQueue.count - 1) 项可撤销")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                }
                Spacer(minLength: 4)
                Button("撤销") { state.performUndo() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            )
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(.bottom, 58)
            .padding(.horizontal, 34)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// 完成、恢复、新建等操作的短暂反馈；失败时显示为错误样式。
    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = state.notice, state.isExpanded {
            HStack(spacing: 10) {
                Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.isError ? Theme.red : .primary)
                    .lineLimit(1)
                if let title = notice.actionTitle, let action = notice.action {
                    Button(title, action: action)
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.15), radius: 8, y: 3))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(.top, 16)
            .padding(.horizontal, 24)
            .transition(.opacity.combined(with: .move(edge: .top)))
            // 只有带动作的提示需要接收点击，其余不挡住下面的顶栏。
            .allowsHitTesting(notice.action != nil)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    @ViewBuilder
    private var editOverlay: some View {
        if let task = state.editing {
            EditOverlayView(
                task: task,
                repository: repository,
                state: state,
                preview: $state.imagePreview,
                onClose: { withAnimation(.easeOut(duration: 0.15)) { state.imagePreview = nil; state.editing = nil } }
            )
            .id(task.id)
        }
    }

    // MARK: - 数据

    private var activeCounts: [Quadrant: Int] {
        var result: [Quadrant: Int] = [:]
        for quadrant in Quadrant.allCases {
            result[quadrant] = repository.activeTasks(in: quadrant, from: allTasks).count
        }
        return result
    }

    private var completedCounts: [Quadrant: Int] {
        var result: [Quadrant: Int] = [:]
        for quadrant in Quadrant.allCases {
            result[quadrant] = repository.completedTasks(in: quadrant, from: allTasks).count
        }
        return result
    }

    private var activeByQuadrant: [Quadrant: [TaskItem]] {
        var result: [Quadrant: [TaskItem]] = [:]
        for quadrant in Quadrant.allCases {
            result[quadrant] = repository.activeTasks(in: quadrant, from: allTasks)
        }
        return result
    }

    private var completedByQuadrant: [Quadrant: [TaskItem]] {
        var result: [Quadrant: [TaskItem]] = [:]
        for quadrant in Quadrant.allCases {
            result[quadrant] = repository.completedTasks(in: quadrant, from: allTasks)
        }
        return result
    }

    // MARK: - 布局辅助

    private var bodyAlignment: Alignment {
        switch settings.edge {
        case .right: return .leading
        case .left: return .trailing
        case .top: return .bottom
        case .bottom: return .top
        }
    }
    /// 收起时窗口只有贴屏幕边缘的一小条可见：贴边条必须画在窗口的对应一侧。
    private var railAlignment: Alignment {
        switch settings.edge {
        case .right: return .leading
        case .left: return .trailing
        case .top: return .bottom
        case .bottom: return .top
        }
    }

    private var bodyEdgePadding: EdgeInsets {
        switch settings.edge {
        case .right: return EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0)
        case .left: return EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 8)
        case .top: return EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8)
        case .bottom: return EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 8)
        }
    }

    private func handleDrop(rawID: String, quadrant: Quadrant, index: Int?) {
        defer { state.isDraggingTask = false }
        guard let id = UUID(uuidString: rawID), let task = allTasks.first(where: { $0.id == id }) else { return }
        let moved = withAnimation(.easeOut(duration: 0.2)) {
            repository.move(task, to: quadrant, dropIndex: index)
        }
        // 保存失败时 repository 已恢复原象限与顺序，这里只需提示。
        if !moved { state.show("移动失败，请重试", isError: true) }
    }

    // MARK: - 键盘

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { event in
            guard let panel = state.controller?.panel else { return event }
            if event.type == .leftMouseUp {
                state.isDraggingTask = false
                return event
            }
            guard panel.isKeyWindow, event.window === panel else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let editingText = panel.firstResponder is NSTextView

            if state.editing != nil, event.keyCode != 53 { return event }

            switch event.keyCode {
            case 53: // Esc
                if state.imagePreview != nil {
                    state.imagePreview = nil
                } else if state.editing != nil {
                    state.requestEditorClose()
                } else if let quadrant = state.focusedInput, state.clearDraft(in: quadrant) {
                    // 输入行的 Esc 只清空未提交草稿并保持焦点。
                } else {
                    state.collapse()
                }
                return nil
            case 49: // Space
                if editingText || flags.contains(.command) || state.focusedInput != nil { return event }
                guard let task = state.focusedTask(allTasks) else { return event }
                state.toggleCompletion(task)
                return nil
            case 51: // Delete
                if flags.contains(.command), let task = state.focusedTask(allTasks) {
                    withAnimation(.easeOut(duration: 0.18)) { state.delete(task) }
                    return nil
                }
                return editingText ? event : nil
            case 125, 126: // ↓ / ↑
                if editingText { return event }
                let quadrant = state.focusedTask(allTasks)?.quadrant ?? state.selectedQuadrant
                let list = repository.activeTasks(in: quadrant, from: allTasks)
                state.moveFocus(in: quadrant, tasks: list, delta: event.keyCode == 125 ? 1 : -1)
                return nil
            default:
                break
            }

            if flags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "n":
                    state.focusInput(state.selectedQuadrant)
                    return nil
                case "z":
                    state.performUndo()
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
}

/// 每分钟刷新一次，保证跨天 / 计时类界面保持最新。
final class MinuteTicker: ObservableObject {
    @Published var now = Date()
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }
}

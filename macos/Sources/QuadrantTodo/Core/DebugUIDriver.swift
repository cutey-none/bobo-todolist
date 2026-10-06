#if DEBUG
import AppKit

/// 仅 debug 构建：按 `QT_UI_SCRIPT` 脚本向面板窗口投递真实 NSEvent，用于无辅助功能权限时的界面验证。
///
/// 脚本每行一条命令，坐标为面板内容区左上角起的点坐标：
/// `click x y` · `doubleclick x y` · `drag x y dx dy`（从 x y 按住拖动 dx dy 屏幕点） ·
/// `type 文本`（`\n` 表示换行） · `key esc|return` · `wait 毫秒` ·
/// `shot 名称`（写出 `名称.req`，等外部截图后删除该文件再继续）。
@MainActor
final class DebugUIDriver {
    private let window: NSWindow
    private var commands: [String]
    private let requestDirectory: URL

    static func startIfRequested(window: NSWindow) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["QT_UI_SCRIPT"], let script = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let directory = URL(fileURLWithPath: env["QT_UI_DIR"] ?? NSTemporaryDirectory(), isDirectory: true)
        let driver = DebugUIDriver(window: window, script: script, requestDirectory: directory)
        running = driver
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { driver.next() }
    }

    private static var running: DebugUIDriver?

    private init(window: NSWindow, script: String, requestDirectory: URL) {
        self.window = window
        self.commands = script.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        self.requestDirectory = requestDirectory
    }

    private func next(after delay: Double = 0.25) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in run() }
    }

    private func run() {
        guard !commands.isEmpty else { NSLog("QuadrantTodo: UI 脚本执行完毕"); return }
        let line = commands.removeFirst()
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        NSLog("QuadrantTodo: UI 脚本 %@", line)
        switch parts[0] {
        case "click", "doubleclick":
            let numbers = argument.split(separator: " ").compactMap { Double($0) }
            guard numbers.count == 2 else { return next() }
            click(at: NSPoint(x: numbers[0], y: numbers[1]), times: parts[0] == "click" ? 1 : 2)
            // 单击需等待双击判定窗口过去后才会触发。
            next(after: NSEvent.doubleClickInterval + 0.35)
        case "drag":
            let numbers = argument.split(separator: " ").compactMap { Double($0) }
            guard numbers.count == 4 else { return next() }
            drag(from: NSPoint(x: numbers[0], y: numbers[1]), by: CGSize(width: numbers[2], height: numbers[3]))
        case "type":
            window.makeKey()
            (window.firstResponder as? NSTextView)?.insertText(argument.replacingOccurrences(of: "\\n", with: "\n"),
                                                               replacementRange: NSRange(location: NSNotFound, length: 0))
            next()
        case "key":
            key(argument)
            next(after: 0.4)
        case "wait":
            next(after: (Double(argument) ?? 300) / 1000)
        case "shot":
            let request = requestDirectory.appendingPathComponent("\(argument).req")
            try? "\(window.windowNumber)".write(to: request, atomically: true, encoding: .utf8)
            waitForShot(request)
        default:
            next()
        }
    }

    private func waitForShot(_ request: URL) {
        if FileManager.default.fileExists(atPath: request.path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in waitForShot(request) }
        } else {
            next()
        }
    }

    private func click(at point: NSPoint, times: Int) {
        guard let content = window.contentView else { return }
        let local = NSPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y)
        let location = content.convert(local, to: nil)
        func event(_ type: NSEvent.EventType, _ count: Int) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: count, pressure: 1)
        }
        for count in 1...times {
            // 先把 mouseUp 放进队列：原生控件在 mouseDown 里会进入跟踪循环等待它。
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(count - 1) * 0.08) { [window] in
                guard let down = event(.leftMouseDown, count), let up = event(.leftMouseUp, count) else { return }
                NSApp.postEvent(up, atStart: false)
                window.sendEvent(down)
            }
        }
    }

    /// 模拟真实鼠标：光标在屏幕上匀速移动，每一步都按窗口当前位置换算成窗口坐标。
    /// 窗口跟着拖动移动时，同一屏幕点对应的窗口坐标会变化，这正是真实拖动的情形。
    private func drag(from point: NSPoint, by delta: CGSize, steps: Int = 30) {
        guard let content = window.contentView else { return next() }
        let local = NSPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y)
        let start = window.convertPoint(toScreen: content.convert(local, to: nil))
        func send(_ type: NSEvent.EventType, at screen: NSPoint) {
            guard let event = NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screen),
                                                 modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            // 走事件队列而不是 window.sendEvent，保证 NSApp.currentEvent 与真实拖动一致。
            NSApp.postEvent(event, atStart: false)
        }
        send(.leftMouseDown, at: start)
        var step = 0
        func advance() {
            step += 1
            let t = CGFloat(step) / CGFloat(steps)
            let screen = NSPoint(x: start.x + delta.width * t, y: start.y - delta.height * t)
            if step <= steps {
                send(.leftMouseDragged, at: screen)
                NSLog("QuadrantTodo: drag step %d mouse=(%.0f,%.0f) origin=(%.0f,%.0f)",
                      step, screen.x, screen.y, window.frame.minX, window.frame.minY)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { advance() }
            } else {
                send(.leftMouseUp, at: NSPoint(x: start.x + delta.width, y: start.y - delta.height))
                NSLog("QuadrantTodo: drag end frame=%@", NSStringFromRect(window.frame))
                next(after: 0.6)
            }
        }
        advance()
    }

    private func key(_ name: String) {
        let (code, characters): (UInt16, String) = name == "esc" ? (53, "\u{1B}") : (36, "\r")
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code) else { continue }
            NSApp.sendEvent(event)
        }
    }
}
#endif

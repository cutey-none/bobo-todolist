import AppKit
import SwiftUI

enum EdgeSide: String, CaseIterable, Identifiable {
    case left
    case right
    case top
    case bottom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .left: return "左侧"
        case .right: return "右侧"
        case .top: return "上方"
        case .bottom: return "下方"
        }
    }

    var isVertical: Bool { self == .left || self == .right }
}

/// 应用设置，落在 UserDefaults 本地（PRD 5.2 Settings）。
final class SettingsStore: ObservableObject {
    /// 供 SwiftUI Settings 场景与 AppDelegate 共用同一份设置。
    static let shared = SettingsStore()

    private enum Key {
        static let edge = "settings.edge"
        static let peekOffset = "settings.peekOffset"
        static let alwaysOnTop = "settings.alwaysOnTop"
        static let showInFullScreen = "settings.showInFullScreen"
        static let hotkey = "settings.hotkey"
        static let seeded = "settings.didSeedSampleTasks"
        static let panelWidth = "settings.panelWidth"
        static let panelHeight = "settings.panelHeight"
        static let isDocked = "settings.isDocked"
        static let floatingX = "settings.floatingX"
        static let floatingY = "settings.floatingY"
    }

    private let defaults: UserDefaults

    @Published var edge: EdgeSide {
        didSet { defaults.set(edge.rawValue, forKey: Key.edge) }
    }

    /// false 表示窗口由用户自由放置，不随展开 / 收起回到屏幕边缘。
    @Published var isDocked: Bool {
        didSet { defaults.set(isDocked, forKey: Key.isDocked) }
    }

    private(set) var floatingOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Key.floatingX) != nil,
                  defaults.object(forKey: Key.floatingY) != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.floatingX), y: defaults.double(forKey: Key.floatingY))
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.floatingX); defaults.removeObject(forKey: Key.floatingY); return
            }
            defaults.set(Double(newValue.x), forKey: Key.floatingX)
            defaults.set(Double(newValue.y), forKey: Key.floatingY)
        }
    }

    func dock(to edge: EdgeSide) {
        isDocked = true
        self.edge = edge
    }

    func keepFloating(at origin: CGPoint) {
        floatingOrigin = origin
        isDocked = false
    }

    /// 贴边条中心相对屏幕中心的偏移：左右边为垂直偏移，上下边为水平偏移。
    @Published var peekOffset: Double {
        didSet { defaults.set(peekOffset, forKey: Key.peekOffset) }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    @Published var showInFullScreen: Bool {
        didSet { defaults.set(showInFullScreen, forKey: Key.showInFullScreen) }
    }

    @Published var hotkey: HotKeyPreset {
        didSet { defaults.set(hotkey.rawValue, forKey: Key.hotkey) }
    }

    /// 面板宽度（pt）。默认 560，可在设置中调整；超出范围会被夹紧。
    @Published var panelWidth: CGFloat {
        didSet { defaults.set(Double(panelWidth), forKey: Key.panelWidth) }
    }

    /// 面板高度（pt）。默认 470，可在设置中调整；超出范围会被夹紧。
    @Published var panelHeight: CGFloat {
        didSet { defaults.set(Double(panelHeight), forKey: Key.panelHeight) }
    }

    var didSeedSampleTasks: Bool {
        get { defaults.bool(forKey: Key.seeded) }
        set { defaults.set(newValue, forKey: Key.seeded) }
    }

    var panelSize: CGSize { CGSize(width: panelWidth, height: panelHeight) }

    /// 设置面板尺寸（会夹到允许范围内），用于预设与数值输入。
    func setPanelSize(width: CGFloat, height: CGFloat) {
        let size = SettingsStore.clampPanelSize(CGSize(width: width, height: height))
        if panelWidth != size.width { panelWidth = size.width }
        if panelHeight != size.height { panelHeight = size.height }
    }

    func resetPanelSize() {
        setPanelSize(width: Metrics.defaultPanelWidth, height: Metrics.defaultPanelHeight)
    }

    static func clampPanelSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, Metrics.minPanelWidth), Metrics.maxPanelWidth),
            height: min(max(size.height, Metrics.minPanelHeight), Metrics.maxPanelHeight)
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edge = EdgeSide(rawValue: defaults.string(forKey: Key.edge) ?? "") ?? .right
        isDocked = defaults.object(forKey: Key.isDocked) as? Bool ?? true
        peekOffset = defaults.object(forKey: Key.peekOffset) as? Double ?? 0
        alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? true
        showInFullScreen = defaults.object(forKey: Key.showInFullScreen) as? Bool ?? false
        hotkey = HotKeyPreset(rawValue: defaults.string(forKey: Key.hotkey) ?? "") ?? .optionSpace
        let stored = SettingsStore.clampPanelSize(
            CGSize(
                width: defaults.object(forKey: Key.panelWidth) as? Double ?? Double(Metrics.defaultPanelWidth),
                height: defaults.object(forKey: Key.panelHeight) as? Double ?? Double(Metrics.defaultPanelHeight)
            )
        )
        panelWidth = stored.width
        panelHeight = stored.height
    }
}

/// 设置里的一键尺寸预设。
enum PanelSizePreset: String, CaseIterable, Identifiable {
    case compact
    case standard
    case roomy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "默认"
        case .roomy: return "宽松"
        }
    }

    var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 420, height: 320)
        case .standard: return CGSize(width: Metrics.defaultPanelWidth, height: Metrics.defaultPanelHeight)
        case .roomy: return CGSize(width: 720, height: 640)
        }
    }
}

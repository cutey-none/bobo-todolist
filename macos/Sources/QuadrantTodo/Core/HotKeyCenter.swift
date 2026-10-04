import Carbon.HIToolbox
import Foundation

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case optionSpace
    case controlOptionSpace
    case optionT

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        case .optionT: return "⌥ T"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .controlOptionSpace: return UInt32(kVK_Space)
        case .optionT: return UInt32(kVK_ANSI_T)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace, .optionT: return UInt32(optionKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        }
    }
}

/// 全局快捷键（Carbon RegisterEventHotKey，无需辅助功能权限）。
final class HotKeyCenter {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.handler?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func register(_ preset: HotKeyPreset, handler: @escaping () -> Void) {
        unregister()
        self.handler = handler
        let hotKeyID = EventHotKeyID(signature: OSType(0x51544F44), id: 1) // 'QTOD'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
            NSLog("QuadrantTodo: 全局快捷键已注册 \(preset.label)")
        } else {
            NSLog("QuadrantTodo: 注册全局快捷键失败 status=\(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

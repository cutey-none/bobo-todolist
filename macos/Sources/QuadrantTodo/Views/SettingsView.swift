import AppKit
import SwiftUI

/// 设置窗口：贴边侧、置顶、全屏行为与全局快捷键。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onRevealData: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("四象限待办")
                    .font(.system(size: 15, weight: .semibold))
                Text("贴边悬浮 · 本地存储 · 无需账户")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            section("窗口") {
                row("贴边位置") {
                    Picker("", selection: Binding(
                        get: { settings.edge },
                        set: { settings.dock(to: $0) }
                    )) {
                        ForEach(EdgeSide.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                row("窗口置顶") {
                    Toggle("", isOn: $settings.alwaysOnTop).labelsHidden().toggleStyle(.switch)
                }
                row("全屏 App 时显示") {
                    Toggle("", isOn: $settings.showInFullScreen).labelsHidden().toggleStyle(.switch)
                }
            }

            section("窗口大小") {
                row("宽度") {
                    sizeStepper($settings.panelWidth, range: Metrics.minPanelWidth...Metrics.maxPanelWidth)
                }
                row("高度") {
                    sizeStepper($settings.panelHeight, range: Metrics.minPanelHeight...Metrics.maxPanelHeight)
                }
                HStack(spacing: 6) {
                    ForEach(PanelSizePreset.allCases) { preset in
                        Button(preset.label) {
                            settings.setPanelSize(width: preset.size.width, height: preset.size.height)
                        }
                        .font(.system(size: 11))
                        .controlSize(.small)
                    }
                    Spacer(minLength: 6)
                    Button("恢复默认") { settings.resetPanelSize() }
                        .font(.system(size: 11))
                        .buttonStyle(.link)
                }
                Text("默认 \(Int(Metrics.defaultPanelWidth)) × \(Int(Metrics.defaultPanelHeight)) pt。面板为固定尺寸，内容纵向超出用滚轮滚动；宽度约 650 pt 以上时四象限按 2×2 排列，否则纵向排列。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("快捷键") {
                row("展开 / 收起") {
                    Picker("", selection: $settings.hotkey) {
                        ForEach(HotKeyPreset.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                Text("面板内：⌘N 新建 · Tab 切换象限 · Space 完成 · ⌘⌫ 删除 · Esc 收起")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("数据") {
                Text(PersistenceController.storeURL().deletingLastPathComponent().path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button("在访达中显示", action: onRevealData)
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("退出应用") { NSApp.terminate(nil) }
                    .font(.system(size: 11.5))
            }
        }
        .padding(18)
        .frame(width: 380, height: 560, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(cornerRadius: 10))
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer(minLength: 8)
            content()
        }
    }

    @ViewBuilder
    private func sizeStepper(_ value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        HStack(spacing: 6) {
            Text("\(Int(value.wrappedValue)) pt")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            Stepper("", value: value, in: range, step: Metrics.panelSizeStep)
                .labelsHidden()
        }
    }
}

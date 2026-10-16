import SwiftUI

/// 设置页「关于与更新」区中随更新状态变化的部分。
struct UpdateStatusView: View {
    @ObservedObject var updater: UpdateController
    @State private var showsAllNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch updater.phase {
            case .idle:
                checkButton
            case .checking:
                busy("正在检查更新…")
            case .upToDate:
                HStack {
                    caption("已是最新版本")
                    Spacer(minLength: 8)
                    checkButton
                }
            case .unavailableForArch(let version):
                caption("新版本 \(version) 暂无适用于本机芯片的安装包。")
                checkButton
            case .available(let version, let notes):
                HStack {
                    Text("发现新版本 \(version)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 8)
                    Button("升级到 \(version)") { updater.install() }
                        .controlSize(.small)
                        .font(.system(size: 11))
                }
                if !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(showsAllNotes ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Button(showsAllNotes ? "收起说明" : "展开说明") { showsAllNotes.toggle() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
                caption("升级会退出并重新打开应用。待办数据不会被替换，并会先自动备份。")
            case .downloading(let progress):
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .controlSize(.small)
                    Button("取消") { updater.cancel() }
                        .controlSize(.small)
                        .font(.system(size: 11))
                }
                caption("正在下载 \(Int(progress * 100))%")
            case .preparing:
                busy("正在校验安装包并备份数据…")
            case .relaunching:
                busy("即将重新打开应用…")
            case .failed(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                checkButton
            }
        }
    }

    private var checkButton: some View {
        Button("检查更新") { updater.check() }
            .controlSize(.small)
            .font(.system(size: 11))
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            caption(text)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

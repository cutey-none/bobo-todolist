import SwiftUI

/// 渲染事项描述的 Markdown：主界面展开查看与编辑弹框预览共用。
struct MarkdownView: View {
    let markdown: String
    var attachments: AttachmentStore = .shared
    var fontSize: CGFloat = 12.5
    var imageMaxHeight: CGFloat = 200
    var onImageTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownDocument.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold))
                .padding(.top, 2)
        case .paragraph(let text):
            inline(text).font(.system(size: fontSize))
        case .bullet(let text):
            listItem(marker: "•", text: text)
        case .task(let checked, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Theme.accent : Theme.secondaryText)
                    .accessibilityLabel(checked ? "已勾选" : "未勾选")
                inline(text)
            }
            .font(.system(size: fontSize))
            .padding(.leading, 4)
        case .ordered(let number, let text):
            listItem(marker: "\(number).", text: text)
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(Theme.hairline).frame(width: 3)
                inline(text).font(.system(size: fontSize)).foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let text):
            Text(text)
                .font(.system(size: fontSize - 1, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        case .image(let alt, let source):
            imageView(alt: alt, source: source)
        }
    }

    private func listItem(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker).foregroundStyle(Theme.secondaryText).monospacedDigit()
            inline(text)
        }
        .font(.system(size: fontSize))
        .padding(.leading, 4)
    }

    @ViewBuilder private func imageView(alt: String, source: String) -> some View {
        if let image = attachments.image(for: source) {
            let content = Image(nsImage: image).resizable().scaledToFit()
                .frame(maxHeight: imageMaxHeight, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(alt.isEmpty ? "图片" : alt)
            if let onImageTap {
                Button { onImageTap(source) } label: { content }.buttonStyle(.plain).help("查看大图")
            } else {
                content
            }
        } else {
            Label(alt.isEmpty ? "图片无法显示" : alt, systemImage: "photo")
                .font(.system(size: fontSize - 1))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) { return Text(attributed) }
        return Text(text)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 4
        case 2: return fontSize + 2.5
        default: return fontSize + 1
        }
    }
}

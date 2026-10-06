import AppKit
import SwiftUI

/// 工具栏通过它在光标处插入 Markdown，而不是总追加到末尾。
@MainActor
final class MarkdownEditorController: ObservableObject {
    fileprivate weak var textView: NSTextView?

    static let linePrefixes = ["###### ", "##### ", "#### ", "### ", "## ", "# ", "- ", "* ", "+ ", "> "]

    /// 把光标所在行设为指定前缀（nil 表示还原为正文）。
    func setLinePrefix(_ prefix: String?) {
        guard let textView else { return }
        let text = textView.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
        var line = text.substring(with: lineRange)
        let newline = line.hasSuffix("\n") ? "\n" : ""
        if !newline.isEmpty { line.removeLast() }
        let existing = Self.linePrefixes.first { line.hasPrefix($0) }
        let body = existing.map { String(line.dropFirst($0.count)) } ?? line
        let replacement = (existing == prefix ? "" : (prefix ?? "")) + body + newline
        replace(lineRange, with: replacement, caret: lineRange.location + (replacement as NSString).length - (newline as NSString).length)
    }

    /// 在光标处另起一行插入一段内容（用于图片）。
    func insertBlock(_ block: String) {
        guard let textView else { return }
        let text = textView.string as NSString
        let location = textView.selectedRange().location
        let needsBreak = location > 0 && text.character(at: location - 1) != 10
        let insertion = (needsBreak ? "\n" : "") + block + "\n"
        replace(NSRange(location: location, length: textView.selectedRange().length), with: insertion,
                caret: location + (insertion as NSString).length)
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    private func replace(_ range: NSRange, with string: String, caret: Int) {
        guard let textView, textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.window?.makeFirstResponder(textView)
    }
}

/// 纯文本 Markdown 编辑器：等宽字体、支持撤销，粘贴图片时交给外部保存为附件。
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var placeholder = ""
    let onPasteImage: (NSImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PastingTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.setAccessibilityLabel("Markdown 描述")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? PastingTextView else { return }
        textView.onPasteImage = onPasteImage
        if textView.string != text { textView.string = text }
        controller.textView = textView
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
        }
    }
}

private final class PastingTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?
    var placeholder = ""

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) == nil, let image = NSImage(pasteboard: pasteboard) {
            onPasteImage?(image)
            return
        }
        pasteAsPlainText(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 12.5),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        (placeholder as NSString).draw(in: NSRect(origin: origin, size: NSSize(width: bounds.width - origin.x * 2, height: bounds.height)),
                                       withAttributes: attributes)
    }
}

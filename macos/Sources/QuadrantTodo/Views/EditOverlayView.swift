import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 编辑浮层（UI PRD 7）：一个编辑外框内，顶部是事项名称（页面级标题），下方是 Markdown 描述。
/// 只在点「保存」时写入；有未保存修改时，所有离开路径统一询问保存 / 放弃 / 继续编辑。
struct EditOverlayView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case edit = "编辑"
        case preview = "预览"
        var id: String { rawValue }
    }

    let task: TaskItem
    let repository: TaskRepository
    @ObservedObject var state: AppState
    @Binding var preview: Data?
    let onClose: () -> Void

    @State private var title: String
    @State private var quadrant: Quadrant
    @State private var markdown: String
    @State private var mode: Mode
    @State private var importing = false
    @State private var message: String?
    @State private var titleProblem: String?
    @State private var saveFailed = false
    @State private var saving = false
    @State private var confirmingLeave = false
    @State private var openedAt = Date()
    @FocusState private var titleFocused: Bool
    @StateObject private var editor = MarkdownEditorController()

    // 最近一次成功保存的内容；必须放在 SwiftUI state 里，否则视图重建时会被重新取值。
    @State private var originalTitle: String
    @State private var originalQuadrant: Quadrant
    @State private var originalMarkdown: String

    init(task: TaskItem, repository: TaskRepository, state: AppState, preview: Binding<Data?>, onClose: @escaping () -> Void) {
        self.task = task
        self.repository = repository
        self.state = state
        _preview = preview
        self.onClose = onClose
        let initial = repository.description(for: task)
        _title = State(initialValue: task.title)
        _quadrant = State(initialValue: task.quadrant)
        _markdown = State(initialValue: initial)
        // 大多数时候是来看描述的：有描述时先预览，单击正文再进入编辑。
        _mode = State(initialValue: TaskDescription.normalized(initial) == nil ? .edit : .preview)
        _originalTitle = State(initialValue: task.title)
        _originalQuadrant = State(initialValue: task.quadrant)
        _originalMarkdown = State(initialValue: initial)
    }

    private var isDirty: Bool {
        title != originalTitle || quadrant != originalQuadrant
            || TaskDescription.normalized(markdown) != TaskDescription.normalized(originalMarkdown)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.18).contentShape(Rectangle()).onTapGesture(perform: backgroundTapped)
                VStack(spacing: 0) {
                    editorFrame.padding(.horizontal, 20).padding(.top, 20)
                    footer
                }
                .frame(width: min(560, max(0, geometry.size.width - 24)), height: max(0, geometry.size.height - 24))
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)).shadow(color: .black.opacity(0.28), radius: 24, y: 10))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1))
                .overlay { if confirmingLeave { leaveConfirmation } }

                if let preview, let image = ImageAttachment.image(from: preview) { imagePreview(image) }
            }
        }
        .transition(.opacity)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: false, onCompletion: importImage)
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
        .onAppear {
            openedAt = Date()
            // 打开后焦点进入标题。
            DispatchQueue.main.async { titleFocused = true }
        }
        .onChange(of: title) { _, newValue in
            // 标题始终是单行：粘贴的换行转为空格，Enter 不写入换行。
            let single = TaskTitle.singleLine(newValue)
            if single != newValue { title = single }
            if case .failure(.tooLong) = TaskTitle.validate(single) {
                titleProblem = TaskTitle.Problem.tooLong.message
            } else {
                titleProblem = nil
            }
            saveFailed = false
        }
        .onChange(of: state.editorCloseRequest) { _, _ in
            // Esc：确认框已打开时等同「继续编辑」。
            if confirmingLeave { confirmingLeave = false } else { requestLeave() }
        }
        .onDisappear { preview = nil }
    }

    // MARK: - 编辑外框

    private var editorFrame: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    TextField("事项名称", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1...3)
                        .focused($titleFocused)
                        .onSubmit { mode = .edit; DispatchQueue.main.async { editor.focus() } }
                        .accessibilityLabel("事项名称")
                        .accessibilityAddTraits(.isHeader)
                    Button(action: requestLeave) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                            .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                    .help("关闭（Esc）")
                    .accessibilityLabel("关闭编辑")
                }
                if let titleProblem {
                    Label(titleProblem, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(Theme.red)
                }
                HStack(spacing: 8) {
                    quadrantMenu
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            Divider().overlay(Theme.hairline)
            descriptionArea.frame(minHeight: 160, maxHeight: .infinity)
            Divider().overlay(Theme.hairline)
            toolbar.padding(.horizontal, 12).frame(height: 40)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var quadrantMenu: some View {
        Menu {
            ForEach(Quadrant.allCases) { item in Button(item.name) { quadrant = item } }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(quadrant.color).frame(width: 7, height: 7)
                Text(quadrant.name).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(quadrant.color)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("所属象限：\(quadrant.name)")
    }

    @ViewBuilder private var descriptionArea: some View {
        switch mode {
        case .edit:
            MarkdownTextView(text: $markdown, controller: editor,
                             placeholder: "用 Markdown 写描述：### 小标题、- 列表、粘贴图片…",
                             onPasteImage: pasteImage)
        case .preview:
            ScrollView {
                if TaskDescription.normalized(markdown) == nil {
                    Text("暂无描述").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownView(markdown: markdown, attachments: repository.attachments) { source in
                        preview = repository.attachments.data(for: source)
                    }
                }
            }
            .padding(16)
            .contentShape(Rectangle())
            // 单击正文进入编辑；图片自身是按钮，点它仍是查看大图。
            .onTapGesture { startEditing() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolButton("正文", help: "当前行改为正文") { editor.setLinePrefix(nil) }
            toolButton("标题", help: "当前行设为小标题（### ）") { editor.setLinePrefix("### ") }
            toolButton("列表", help: "当前行设为列表项（- ）") { editor.setLinePrefix("- ") }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 14).padding(.horizontal, 5)
            toolButton("图片", help: "插入图片，也可直接粘贴", action: addImage)
            Spacer()
            if mode == .preview {
                Text("单击正文开始编辑").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    private func startEditing() {
        mode = .edit
        DispatchQueue.main.async { editor.focus() }
    }

    private func toolButton(_ label: String, help: String, action: @escaping () -> Void) -> some View {
        // 预览时点工具栏先切回编辑，再作用到编辑器。
        Button(label) {
            if mode == .preview {
                startEditing()
                // 等编辑器视图创建并拿到焦点后再执行。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { action() }
            } else {
                action()
            }
        }.buttonStyle(.plain).font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText).padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle()).help(help)
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 10) {
            Button(role: .destructive, action: deleteTask) {
                Label("删除", systemImage: "trash").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.red)
            .help("删除事项，8 秒内可撤销")

            if saveFailed {
                Label("保存失败，请重试", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.red)
            } else if isDirty {
                Text("有未保存的更改").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button("取消", action: requestLeave).buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
            Button(action: { _ = save() }) {
                Text(saving ? "正在保存…" : "保存").font(.system(size: 12, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    /// 有修改时离开前的统一确认（Esc、点遮罩、关闭按钮、取消都走这里）。
    private var leaveConfirmation: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.12))
            VStack(alignment: .leading, spacing: 12) {
                Text("保存对「\(originalTitle)」的修改吗？").font(.system(size: 13, weight: .semibold))
                Text("不保存的话，这次修改会丢失。").font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 8) {
                    Button("放弃修改") { confirmingLeave = false; onClose() }
                    Spacer()
                    Button("继续编辑") { confirmingLeave = false }
                        .keyboardShortcut(.cancelAction)
                    Button("保存") { confirmingLeave = false; save() }
                        .keyboardShortcut(.defaultAction)
                }
                .font(.system(size: 12))
            }
            .padding(18)
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)).shadow(color: .black.opacity(0.25), radius: 16, y: 6))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("未保存的修改")
    }

    // MARK: - 行为

    private func backgroundTapped() {
        // 双击标题时第二下会落到刚出现的遮罩上：不能因此立刻关闭浮层。
        guard Date().timeIntervalSince(openedAt) > NSEvent.doubleClickInterval else { return }
        requestLeave()
    }

    private func requestLeave() {
        guard isDirty else { return onClose() }
        // 撤掉背后输入框的焦点，Enter / Esc 才会落到确认框的「保存 / 继续编辑」上。
        titleFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
        confirmingLeave = true
    }

    /// 保存标题、象限与描述；成功后关闭，失败时保留浮层与全部草稿。
    @discardableResult
    private func save() -> Bool {
        let valid: String
        switch TaskTitle.validate(title) {
        case .success(let value): valid = value
        case .failure(let problem):
            titleProblem = problem.message
            titleFocused = true
            return false
        }
        saving = true
        defer { saving = false }
        guard repository.update(task, title: valid, note: TaskDescription.normalized(markdown), quadrant: quadrant) else {
            saveFailed = true
            return false
        }
        originalTitle = valid
        originalQuadrant = quadrant
        originalMarkdown = markdown
        // 浮层关闭、列表更新就是保存成功的反馈；只有失败才提示。
        onClose()
        return true
    }

    private func deleteTask() {
        if state.delete(task) { onClose() }
    }

    // MARK: - 图片

    private func addImage() { guard imageCount < 6 else { message = "一个事项最多 6 张图片"; return }; importing = true }
    private func importImage(_ result: Result<[URL], Error>) {
        guard imageCount < 6 else { message = "一个事项最多 6 张图片"; return }
        guard case .success(let urls) = result, let url = urls.first else { if case .failure = result { message = "无法读取这张图片，请选择其他图片。" }; return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = ImageAttachment.normalizedData(from: url) else { message = "无法读取这张图片，请选择其他图片。"; return }
        insertImage(data)
    }
    private func pasteImage(_ image: NSImage) {
        guard imageCount < 6 else { message = "一个事项最多 6 张图片"; return }
        guard let data = ImageAttachment.normalizedData(from: image) else { message = "无法读取这张图片，请选择其他图片。"; return }
        insertImage(data)
    }
    /// 图片文件立即写入附件目录，Markdown 引用随「保存」一起写入事项。
    private func insertImage(_ data: Data) {
        guard let source = repository.attachments.save(data) else { message = "图片保存失败，请重试。"; return }
        let line = "![图片](\(source))"
        if !editor.insertBlock(line) {
            markdown += (markdown.isEmpty || markdown.hasSuffix("\n") ? "" : "\n") + line + "\n"
        }
    }
    private var imageCount: Int { MarkdownDocument.imageSources(in: markdown).count }

    private func imagePreview(_ image: NSImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.88).onTapGesture { preview = nil }
            Image(nsImage: image).resizable().scaledToFit().padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).onTapGesture { preview = nil }
            Button { preview = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.white) }
                .buttonStyle(.plain).padding(12).help("关闭图片预览（Esc）")
        }
    }
}

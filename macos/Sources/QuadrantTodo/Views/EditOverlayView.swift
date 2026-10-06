import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var mode: Mode = .edit
    @State private var importing = false
    @State private var message: String?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var skipDisappearSave = false
    @State private var appeared = false
    @StateObject private var editor = MarkdownEditorController()

    // These snapshots must live in SwiftUI state. Plain stored properties are rebuilt
    // whenever the view is re-rendered, which would make Cancel capture autosaved edits.
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
        _originalTitle = State(initialValue: task.title)
        _originalQuadrant = State(initialValue: task.quadrant)
        _originalMarkdown = State(initialValue: initial)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.18).contentShape(Rectangle()).onTapGesture { closeSaving() }
                VStack(spacing: 0) {
                    header
                    Divider().overlay(Theme.hairline)
                    descriptionSection.frame(maxHeight: .infinity)
                    Divider().overlay(Theme.hairline)
                    footer
                }
                .frame(width: min(520, max(0, geometry.size.width - 24)), height: max(0, geometry.size.height - 24))
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)).shadow(color: .black.opacity(0.28), radius: 24, y: 10))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1))

                if let preview, let image = ImageAttachment.image(from: preview) { imagePreview(image) }
            }
        }
        .transition(.opacity)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: false, onCompletion: importImage)
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
        .onAppear(perform: initialFocus)
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: quadrant) { _, _ in scheduleSave() }
        .onChange(of: markdown) { _, _ in scheduleSave() }
        .onChange(of: state.editorCloseRequest) { _, _ in closeSaving() }
        .onDisappear {
            saveTask?.cancel()
            if !skipDisappearSave { flushSave() }
            preview = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("编辑事项").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { closeSaving() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }.buttonStyle(.plain)
            }
            TextField("事项名称", text: $title)
                .textFieldStyle(.plain).font(.system(size: 20, weight: .bold))
                .onSubmit { mode = .edit; DispatchQueue.main.async { editor.focus() } }
            Menu {
                ForEach(Quadrant.allCases) { item in Button(item.name) { quadrant = item } }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(quadrant.color).frame(width: 7, height: 7)
                    Text(quadrant.name).font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(quadrant.color).padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(quadrant.color.opacity(0.12)))
                .overlay(Capsule().strokeBorder(quadrant.color.opacity(0.35), lineWidth: 1))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("事项描述").font(.system(size: 13, weight: .semibold))
                Text("Markdown").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            editorCard
        }.padding(.horizontal, 20).padding(.vertical, 18)
    }

    private var editorCard: some View {
        VStack(spacing: 0) {
            Group {
                switch mode {
                case .edit:
                    MarkdownTextView(text: $markdown, controller: editor,
                                     placeholder: "用 Markdown 记录：### 小标题、- 列表、粘贴图片…",
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
                }
            }
            .frame(minHeight: 160, maxHeight: .infinity)
            Divider().overlay(Theme.hairline)
            toolbar.padding(.horizontal, 12).frame(height: 44)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolButton("正文", help: "当前行改为正文") { editor.setLinePrefix(nil) }
            toolButton("标题", help: "当前行设为小标题（### ）") { editor.setLinePrefix("### ") }
            toolButton("列表", help: "当前行设为列表项（- ）") { editor.setLinePrefix("- ") }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 14).padding(.horizontal, 5)
            toolButton("图片", help: "插入图片，也可直接粘贴", action: addImage)
            Spacer()
        }
        .disabled(mode == .preview)
        .opacity(mode == .preview ? 0.45 : 1)
    }

    private func toolButton(_ label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(.plain).font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText).padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle()).help(help)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.green.opacity(0.75)).frame(width: 7, height: 7)
            Text(saving ? "正在保存…" : "内容已自动保存").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            Spacer()
            Button("取消", action: cancel).buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
            Button(action: closeSaving) {
                Text("保存更改").font(.system(size: 12, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
            }.buttonStyle(.plain).disabled(trimmedTitle.isEmpty).opacity(trimmedTitle.isEmpty ? 0.5 : 1)
        }.padding(.horizontal, 20).padding(.vertical, 16)
    }

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
    private func insertImage(_ data: Data) {
        guard let source = repository.attachments.save(data) else { message = "图片保存失败，请重试。"; return }
        let line = "![图片](\(source))"
        if !editor.insertBlock(line) {
            markdown += (markdown.isEmpty || markdown.hasSuffix("\n") ? "" : "\n") + line + "\n"
        }
    }
    private var imageCount: Int { MarkdownDocument.imageSources(in: markdown).count }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func initialFocus() {
        appeared = true
        DispatchQueue.main.async { editor.focus() }
    }
    private func scheduleSave() {
        guard appeared else { return }; saveTask?.cancel(); saving = true
        saveTask = Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); guard !Task.isCancelled else { return }; flushSave() }
    }
    private func flushSave() {
        saveTask?.cancel(); guard !trimmedTitle.isEmpty else { saving = false; return }
        repository.update(task, title: trimmedTitle, note: task.note, quadrant: quadrant); repository.saveDescription(markdown, for: task); saving = false
    }
    private func closeSaving() { guard !trimmedTitle.isEmpty else { return }; flushSave(); onClose() }
    private func cancel() {
        saveTask?.cancel(); skipDisappearSave = true
        repository.update(task, title: originalTitle, note: task.note, quadrant: originalQuadrant); repository.saveDescription(originalMarkdown, for: task); onClose()
    }
    private func imagePreview(_ image: NSImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.88).onTapGesture { preview = nil }
            Image(nsImage: image).resizable().scaledToFit().padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).onTapGesture { preview = nil }
            Button { preview = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.white) }
                .buttonStyle(.plain).padding(12).help("关闭图片预览（Esc）")
        }
    }
}

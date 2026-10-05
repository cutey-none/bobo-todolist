import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditOverlayView: View {
    let task: TaskItem
    let repository: TaskRepository
    @ObservedObject var state: AppState
    @Binding var preview: Data?
    let onClose: () -> Void

    @State private var title: String
    @State private var quadrant: Quadrant
    @State private var blocks: [DescriptionBlock]
    @State private var importing = false
    @State private var message: String?
    @State private var hovered: UUID?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var skipDisappearSave = false
    @State private var appeared = false
    @FocusState private var titleFocused: Bool
    @FocusState private var focusedBlock: UUID?

    // These snapshots must live in SwiftUI state. Plain stored properties are rebuilt
    // whenever the view is re-rendered, which would make Cancel capture autosaved edits.
    @State private var originalTitle: String
    @State private var originalQuadrant: Quadrant
    @State private var originalBlocks: [DescriptionBlock]

    init(task: TaskItem, repository: TaskRepository, state: AppState, preview: Binding<Data?>, onClose: @escaping () -> Void) {
        self.task = task
        self.repository = repository
        self.state = state
        _preview = preview
        self.onClose = onClose
        let initial = repository.descriptionBlocks(for: task)
        _title = State(initialValue: task.title)
        _quadrant = State(initialValue: task.quadrant)
        _blocks = State(initialValue: initial)
        _originalTitle = State(initialValue: task.title)
        _originalQuadrant = State(initialValue: task.quadrant)
        _originalBlocks = State(initialValue: initial)
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
        .onPasteCommand(of: [.image]) { _ in pasteImage() }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
        .onAppear(perform: initialFocus)
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: quadrant) { _, _ in scheduleSave() }
        .onChange(of: blocks) { _, _ in scheduleSave() }
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
                Text("事项详情").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { closeSaving() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                        .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }.buttonStyle(.plain)
            }
            TextField("事项名称", text: $title)
                .textFieldStyle(.plain).font(.system(size: 20, weight: .bold)).focused($titleFocused)
                .onSubmit { focusedBlock = blocks.last(where: { $0.kind != .image })?.id }
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
                Spacer()
                Text("记录关键信息，随时修改").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            editorCard
        }.padding(.horizontal, 20).padding(.vertical, 18)
    }

    private var editorCard: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if blocks.isEmpty {
                        Button {
                            let block = DescriptionBlock(kind: .paragraph)
                            blocks.append(block)
                            DispatchQueue.main.async { focusedBlock = block.id }
                        } label: {
                            Text("记点什么…").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    } else { ForEach(blocks) { block in blockRow(block) } }
                }.padding(16)
            }.frame(minHeight: 200)
            Divider().overlay(Theme.hairline)
            toolbar.padding(.horizontal, 12).frame(height: 44)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func blockRow(_ block: DescriptionBlock) -> some View {
        HStack(alignment: block.kind == .bullet ? .firstTextBaseline : .top, spacing: 7) {
            if block.kind == .bullet { Text("•").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText).padding(.leading, 6) }
            if block.kind == .image, let data = block.image, let image = ImageAttachment.image(from: data) {
                Button { preview = data } label: {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).help("查看大图")
            } else {
                TextField("", text: textBinding(block.id), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(block.kind == .heading ? .system(size: 15, weight: .semibold) : .system(size: 12.5))
                    .focused($focusedBlock, equals: block.id).onSubmit { insertBlock(after: block.id) }
            }
            Spacer(minLength: 0)
            if hovered == block.id {
                Button { removeBlock(block.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondaryText).frame(width: 18, height: 18)
                }.buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .onTapGesture { if block.kind != .image { focusedBlock = block.id } }
            .onHover { hovered = $0 ? block.id : nil }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            typeButton("正文", .paragraph); typeButton("标题", .heading); typeButton("列表", .bullet)
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 14).padding(.horizontal, 5)
            Button("图片", action: addImage).buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).padding(8)
            Spacer()
        }
    }

    private func typeButton(_ label: String, _ kind: DescriptionBlockKind) -> some View {
        let selected = focusedBlock.flatMap { id in blocks.first(where: { $0.id == id })?.kind } == kind
        return Button(label) { changeType(kind) }.buttonStyle(.plain).font(.system(size: 11.5))
            .foregroundStyle(selected ? Theme.accent : Theme.secondaryText).padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accent.opacity(0.14) : .clear))
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

    private func textBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { blocks.first(where: { $0.id == id })?.text ?? "" }, set: { value in
            if let index = blocks.firstIndex(where: { $0.id == id }) { blocks[index].text = value }
        })
    }

    private func changeType(_ kind: DescriptionBlockKind) {
        if let id = focusedBlock, let i = blocks.firstIndex(where: { $0.id == id }), blocks[i].kind != .image { blocks[i].kind = kind }
        else { let b = DescriptionBlock(kind: kind); blocks.append(b); DispatchQueue.main.async { focusedBlock = b.id } }
    }

    private func insertBlock(after id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        let current = blocks[i]
        let kind: DescriptionBlockKind
        if current.kind == .bullet && current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.remove(at: i); kind = .paragraph }
        else { kind = current.kind == .bullet ? .bullet : .paragraph }
        let b = DescriptionBlock(kind: kind); blocks.insert(b, at: min(i + 1, blocks.count)); DispatchQueue.main.async { focusedBlock = b.id }
    }

    private func removeBlock(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks.remove(at: i); focusedBlock = blocks.indices.contains(i) ? blocks[i].id : blocks.last?.id
    }

    private func addImage() { guard imageCount < 6 else { message = "一个事项最多 6 张图片"; return }; importing = true }
    private func importImage(_ result: Result<[URL], Error>) {
        guard imageCount < 6 else { message = "一个事项最多 6 张图片"; return }
        guard case .success(let urls) = result, let url = urls.first else { if case .failure = result { message = "无法读取这张图片，请选择其他图片。" }; return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = ImageAttachment.normalizedData(from: url) else { message = "无法读取这张图片，请选择其他图片。"; return }
        blocks.append(DescriptionBlock(kind: .image, image: data))
    }
    private func pasteImage() {
        guard let image = NSImage(pasteboard: .general) else { return }
        guard imageCount < 6 else { message = "一个事项最多 6 张图片"; return }
        guard let data = ImageAttachment.normalizedData(from: image) else { message = "无法读取这张图片，请选择其他图片。"; return }
        blocks.append(DescriptionBlock(kind: .image, image: data))
    }
    private var imageCount: Int { blocks.filter { $0.kind == .image && $0.image != nil }.count }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func initialFocus() {
        appeared = true
        DispatchQueue.main.async { if let id = blocks.last(where: { $0.kind != .image })?.id { focusedBlock = id } else { titleFocused = true } }
    }
    private func scheduleSave() {
        guard appeared else { return }; saveTask?.cancel(); saving = true
        saveTask = Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); guard !Task.isCancelled else { return }; flushSave() }
    }
    private func flushSave() {
        saveTask?.cancel(); guard !trimmedTitle.isEmpty else { saving = false; return }
        repository.update(task, title: trimmedTitle, note: task.note, quadrant: quadrant); repository.saveDescription(blocks, for: task); saving = false
    }
    private func closeSaving() { guard !trimmedTitle.isEmpty else { return }; flushSave(); onClose() }
    private func cancel() {
        saveTask?.cancel(); skipDisappearSave = true
        repository.update(task, title: originalTitle, note: task.note, quadrant: originalQuadrant); repository.saveDescription(originalBlocks, for: task); onClose()
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

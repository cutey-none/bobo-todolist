import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 任务编辑浮层：标题、备注、所属象限（PRD F4 / 4.6）。
struct EditOverlayView: View {
    let task: TaskItem
    let repository: TaskRepository
    @Binding var preview: Data?
    @Query private var entries: [ProgressEntry]
    let onSave: (String, String?, Quadrant) -> Void
    let onClose: () -> Void

    @State private var title: String
    @State private var note: String
    @State private var quadrant: Quadrant
    @FocusState private var titleFocused: Bool
    @State private var progressText = ""
    @State private var pendingImage: Data?
    @State private var importing = false
    @State private var imageError: String?

    init(task: TaskItem, repository: TaskRepository, preview: Binding<Data?>, onSave: @escaping (String, String?, Quadrant) -> Void, onClose: @escaping () -> Void) {
        self.task = task
        self.repository = repository
        _preview = preview
        let taskID = task.id
        _entries = Query(filter: #Predicate<ProgressEntry> { $0.taskID == taskID }, sort: \ProgressEntry.createdAt, order: .reverse)
        self.onSave = onSave
        self.onClose = onClose
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note ?? "")
        _quadrant = State(initialValue: task.quadrant)
    }

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            Color.black.opacity(0.18)
                .onTapGesture(perform: onClose)
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("任务详情")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("任务名称").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                    TextField("任务名称", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(CardBackground(cornerRadius: 8))
                        .focused($titleFocused)
                        .onSubmit(commit)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("备注（可选）").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                    TextField("补充说明", text: $note)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(CardBackground(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("所属象限").font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(Quadrant.allCases) { item in
                            Button {
                                quadrant = item
                            } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(item.color).frame(width: 6, height: 6)
                                    Text(item.name).font(.system(size: 11))
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(quadrant == item ? item.color.opacity(0.16) : Color.primary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(quadrant == item ? item.color.opacity(0.7) : .clear, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("取消", action: onClose)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(CardBackground(cornerRadius: 8))
                    Button(action: commit) {
                        Text("保存更改")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
                Divider()
                progressSection
              }
              .padding(14)
            }
            .frame(width: min(380, max(0, geometry.size.width - 24)), height: max(0, geometry.size.height - 24))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .onAppear { titleFocused = true }
            if let preview, let image = ImageAttachment.image(from: preview) {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.88).onTapGesture { self.preview = nil }
                    Image(nsImage: image).resizable().scaledToFit().padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture { self.preview = nil }
                    Button { self.preview = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.white)
                    }.buttonStyle(.plain).padding(12).help("关闭图片预览（Esc）")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = ImageAttachment.normalizedData(from: url) { pendingImage = data; imageError = nil }
                else { imageError = "无法读取这张图片，请选择其他图片。" }
            case .failure(let error): imageError = error.localizedDescription
            }
        }
        .onPasteCommand(of: [.image]) { _ in
            if let image = NSImage(pasteboard: .general), let data = ImageAttachment.normalizedData(from: image) {
                pendingImage = data
                imageError = nil
            }
        }
        .onDisappear { preview = nil }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("进度记录").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("共 \(entries.count) 条").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            ZStack(alignment: .topLeading) {
                if progressText.isEmpty {
                    Text("记录一条进度…").foregroundStyle(Theme.secondaryText).padding(.horizontal, 5).padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $progressText).scrollContentBackground(.hidden).frame(height: 64)
                    .accessibilityLabel("进度内容")
            }.font(.system(size: 12)).padding(5).background(CardBackground(cornerRadius: 8))
            if let pendingImage {
                HStack(alignment: .top) {
                    thumbnail(pendingImage)
                    Button { self.pendingImage = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help("移除待添加图片")
                }
            }
            if let imageError { Text(imageError).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("添加图片") { importing = true }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                Spacer()
                Button {
                    repository.addProgress(taskID: task.id, text: progressText, imageData: pendingImage)
                    progressText = ""
                    pendingImage = nil
                } label: {
                    Text("记录进度").foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
                }.buttonStyle(.plain).disabled(!canRecord).opacity(canRecord ? 1 : 0.5)
            }.font(.system(size: 12))
            if entries.isEmpty { Text("还没有进度记录").font(.system(size: 12)).foregroundStyle(Theme.secondaryText).padding(.vertical, 8) }
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Self.timestamp.string(from: entry.createdAt)).font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Button { repository.deleteProgress(entry) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                                .buttonStyle(.plain).foregroundStyle(Theme.secondaryText).help("删除这条进度")
                        }
                        if !entry.text.isEmpty { Text(entry.text).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        if let data = entry.imageData { thumbnail(data) }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(CardBackground(cornerRadius: 8))
                }
            }
        }
    }

    private var canRecord: Bool { !progressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil }

    @ViewBuilder private func thumbnail(_ data: Data) -> some View {
        if let image = ImageAttachment.image(from: data) {
            Button { preview = data } label: {
                Image(nsImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).help("查看大图")
        }
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func commit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, note.isEmpty ? nil : note, quadrant)
    }
}

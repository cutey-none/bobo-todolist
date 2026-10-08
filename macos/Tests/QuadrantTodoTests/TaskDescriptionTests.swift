import AppKit
import SwiftData
import XCTest
@testable import QuadrantTodo

final class TaskDescriptionTests: XCTestCase {
    private var attachmentDirectory: URL!

    override func setUpWithError() throws {
        attachmentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuadrantTodoTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: attachmentDirectory)
    }

    func testLegacyPlainTextStaysAsMarkdown() {
        XCTAssertNil(TaskDescription.legacyBlocks(from: "一段旧备注"))
        XCTAssertEqual(TaskDescription.markdown(fromStored: "一段旧备注") { _ in nil }, "一段旧备注")
    }

    func testLegacyBlocksConvertToMarkdown() throws {
        let blocks = [
            DescriptionBlock(kind: .heading, text: "关键信息"),
            DescriptionBlock(kind: .paragraph, text: "说明正文"),
            DescriptionBlock(kind: .bullet, text: "列表一"),
            DescriptionBlock(kind: .bullet, text: "列表二"),
            DescriptionBlock(kind: .image, image: Data([0x01, 0x02]))
        ]
        let json = try legacyJSON(blocks)

        let markdown = TaskDescription.markdown(fromStored: json) { _ in "attachments/a.jpg" }

        XCTAssertEqual(markdown, "### 关键信息\n\n说明正文\n\n- 列表一\n- 列表二\n\n![图片](attachments/a.jpg)")
    }

    func testEmptyMarkdownIsNotPersisted() {
        XCTAssertNil(TaskDescription.normalized("  \n"))
        XCTAssertEqual(TaskDescription.normalized("\n- 项\n"), "- 项")
    }

    func testAttachmentStoreSavesAndResolvesImages() throws {
        let store = AttachmentStore(directory: attachmentDirectory)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x00])

        let source = try XCTUnwrap(store.save(png))

        XCTAssertTrue(source.hasPrefix(AttachmentStore.prefix))
        XCTAssertTrue(source.hasSuffix(".png"))
        XCTAssertEqual(store.data(for: source), png)
        XCTAssertNil(store.url(for: "attachments/../Tasks.store"))
    }

    @MainActor
    func testMarkdownDescriptionPersists() throws {
        let (context, repository) = try makeRepository()
        let task = TaskItem(title: "测试事项")
        context.insert(task)

        repository.saveDescription("### 标题\n\n- 列表\n", for: task)

        XCTAssertEqual(task.note, "### 标题\n\n- 列表")
        XCTAssertEqual(repository.description(for: task), "### 标题\n\n- 列表")
        repository.saveDescription("   ", for: task)
        XCTAssertNil(task.note)
    }

    @MainActor
    func testLegacyDescriptionMigratesToMarkdownWithAttachments() throws {
        let (context, repository) = try makeRepository()
        let image = Data([0xFF, 0xD8, 0xFF])
        let task = TaskItem(title: "测试事项", note: try legacyJSON([
            DescriptionBlock(kind: .paragraph, text: "正文"),
            DescriptionBlock(kind: .image, image: image)
        ]))
        context.insert(task)

        repository.migrateLegacyDescriptionsToMarkdown(from: [task])

        let markdown = try XCTUnwrap(task.note)
        XCTAssertNil(TaskDescription.legacyBlocks(from: markdown))
        let sources = MarkdownDocument.imageSources(in: markdown)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(repository.attachments.data(for: sources[0]), image)
    }

    @MainActor
    func testLegacyProgressMigratesIntoDescription() throws {
        let (context, repository) = try makeRepository()
        let task = TaskItem(title: "测试事项", note: "旧备注")
        context.insert(task)
        context.insert(ProgressEntry(taskID: task.id, text: "第一条进度", createdAt: Date(timeIntervalSince1970: 1)))
        context.insert(ProgressEntry(taskID: task.id, text: "", imageData: Data([0x04, 0x05]), createdAt: Date(timeIntervalSince1970: 2)))
        try context.save()

        repository.migrateLegacyProgressToDescriptions(from: [task])

        XCTAssertTrue(repository.progress(for: task.id).isEmpty)
        let blocks = MarkdownDocument.parse(repository.description(for: task))
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .paragraph("旧备注"))
        XCTAssertEqual(blocks[1], .paragraph("第一条进度"))
        guard case .image(_, let source) = blocks[2] else { return XCTFail("缺少图片") }
        XCTAssertEqual(repository.attachments.data(for: source), Data([0x04, 0x05]))
    }

    @MainActor
    func testPastingImageWithTextRepresentationInsertsImage() throws {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            pasteboard.clearContents()
            let items = previous.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 20)).fill()
        image.unlockFocus()
        pasteboard.clearContents()
        pasteboard.setData(try XCTUnwrap(image.tiffRepresentation), forType: .tiff)
        let textView = PastingTextView()
        let pasteMenu = NSMenuItem(title: "粘贴", action: #selector(NSTextView.paste(_:)), keyEquivalent: "v")
        XCTAssertTrue(textView.validateUserInterfaceItem(pasteMenu))
        pasteboard.setString("image.png", forType: .string)
        var pasted = false
        textView.onPasteImage = { _ in pasted = true }
        textView.paste(nil)
        XCTAssertTrue(pasted)
        XCTAssertEqual(textView.string, "")

        pasteboard.clearContents()
        pasteboard.setString("普通文字", forType: .string)
        pasted = false
        textView.paste(nil)
        XCTAssertFalse(pasted)
        XCTAssertEqual(textView.string, "普通文字")
    }

    @MainActor
    func testAttachmentCleanupPreservesUndoSharedFilesAndExternalOriginals() throws {
        let (context, repository) = try makeRepository()
        let source = try XCTUnwrap(repository.attachments.save(Data([1, 2, 3])))
        let markdown = "![图片](\(source))"
        let task = TaskItem(title: "删除图片", note: markdown)
        context.insert(task)
        XCTAssertTrue(repository.save())
        let snapshot = try XCTUnwrap(repository.delete(task))
        repository.removeUnusedAttachments([source], preserving: [snapshot.note!])
        XCTAssertNotNil(repository.attachments.data(for: source))
        XCTAssertTrue(repository.restore(snapshot))
        repository.removeUnusedAttachments([source])
        XCTAssertNotNil(repository.attachments.data(for: source))

        let shared = TaskItem(title: "共用图片", note: markdown)
        context.insert(shared)
        let restored = try XCTUnwrap(repository.allTasks().first { $0.id == snapshot.id })
        XCTAssertNotNil(repository.delete(restored))
        repository.removeUnusedAttachments([source])
        XCTAssertNotNil(repository.attachments.data(for: source))
        XCTAssertNotNil(repository.delete(shared))
        repository.removeUnusedAttachments([source])
        XCTAssertNil(repository.attachments.data(for: source))

        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        let original = attachmentDirectory.appendingPathComponent("original.png")
        try Data([4]).write(to: original)
        repository.attachments.remove(original.path)
        repository.attachments.remove(original.absoluteString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertNil(repository.attachments.url(for: "attachments/.."))
    }

    @MainActor
    private func makeRepository() throws -> (ModelContext, TaskRepository) {
        let container = try ModelContainer(
            for: TaskItem.self, ProgressEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        retainedContainers.append(container)
        let repository = TaskRepository(context: container.mainContext,
                                        attachments: AttachmentStore(directory: attachmentDirectory))
        return (container.mainContext, repository)
    }

    private var retainedContainers: [ModelContainer] = []

    private func legacyJSON(_ blocks: [DescriptionBlock]) throws -> String {
        struct Envelope: Encodable { let version: Int; let blocks: [DescriptionBlock] }
        let data = try JSONEncoder().encode(Envelope(version: 1, blocks: blocks))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

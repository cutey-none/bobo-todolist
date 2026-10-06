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

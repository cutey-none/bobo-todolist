import SwiftData
import XCTest
@testable import QuadrantTodo

final class TaskDescriptionTests: XCTestCase {
    func testLegacyPlainTextBecomesParagraph() {
        let blocks = TaskDescription.decode("一段旧备注")

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .paragraph)
        XCTAssertEqual(blocks[0].text, "一段旧备注")
    }

    func testBlocksRoundTripWithImageData() {
        let original = [
            DescriptionBlock(kind: .heading, text: "关键信息"),
            DescriptionBlock(kind: .paragraph, text: "说明正文"),
            DescriptionBlock(kind: .bullet, text: "普通列表"),
            DescriptionBlock(kind: .image, image: Data([0x01, 0x02, 0x03]))
        ]

        let encoded = TaskDescription.encode(original)
        XCTAssertNotNil(encoded)
        XCTAssertEqual(TaskDescription.decode(encoded), original)
    }

    func testEmptyBlocksAreNotPersisted() {
        let blocks = [
            DescriptionBlock(kind: .paragraph, text: "  \n"),
            DescriptionBlock(kind: .image)
        ]

        XCTAssertNil(TaskDescription.encode(blocks))
        XCTAssertTrue(TaskDescription.isEmpty(blocks))
    }

    @MainActor
    func testLegacyProgressMigratesIntoDescription() throws {
        let container = try ModelContainer(
            for: TaskItem.self, ProgressEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let repository = TaskRepository(context: context)
        let task = TaskItem(title: "测试事项", note: "旧备注")
        context.insert(task)
        context.insert(ProgressEntry(taskID: task.id, text: "第一条进度", createdAt: Date(timeIntervalSince1970: 1)))
        context.insert(ProgressEntry(taskID: task.id, text: "", imageData: Data([0x04, 0x05]), createdAt: Date(timeIntervalSince1970: 2)))
        try context.save()

        repository.migrateLegacyProgressToDescriptions(from: [task])

        XCTAssertTrue(repository.progress(for: task.id).isEmpty)
        let blocks = repository.descriptionBlocks(for: task)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .paragraph, .image])
        XCTAssertEqual(blocks[0].text, "旧备注")
        XCTAssertEqual(blocks[1].text, "第一条进度")
        XCTAssertEqual(blocks[2].image, Data([0x04, 0x05]))
    }
}

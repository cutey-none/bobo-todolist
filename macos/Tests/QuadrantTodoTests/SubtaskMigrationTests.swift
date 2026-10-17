import SwiftData
import XCTest
@testable import QuadrantTodo

@MainActor
final class SubtaskMigrationTests: XCTestCase {
    /// 子待办之前的数据库（只有事项与旧进度表）必须原样打开，否则启动时会被当成损坏库移走。
    func testStoreFromBeforeSubtasksOpensWithDataIntact() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Tasks.store")
        let taskID = UUID()

        do {
            let old = try ModelContainer(for: TaskItem.self, ProgressEntry.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            context.insert(TaskItem(id: taskID, title: "旧事项", note: "旧描述", quadrant: .importantNotUrgent))
            context.insert(ProgressEntry(taskID: taskID, text: "旧进度"))
            try context.save()
        }

        let upgraded = try ModelContainer(for: Schema(PersistenceController.modelTypes), configurations: ModelConfiguration(url: url))
        let context = ModelContext(upgraded)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(tasks.map(\.title), ["旧事项"])
        XCTAssertEqual(tasks.first?.note, "旧描述")
        XCTAssertEqual(tasks.first?.quadrant, .importantNotUrgent)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgressEntry>()).map(\.text), ["旧进度"])

        context.insert(SubtaskItem(parentID: taskID, title: "a"))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<SubtaskItem>()).map(\.title), ["a"])
    }

    func testSnapshotRoundTripKeepsIdentityAndState() {
        let done = Date(timeIntervalSince1970: 100)
        let item = SubtaskItem(parentID: UUID(), title: "b", isCompleted: true, completedAt: done, sortOrder: 3)
        let snapshot = SubtaskSnapshot(item, index: 1)
        let restored = snapshot.makeSubtask(sortOrder: 7)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertEqual(restored.parentID, item.parentID)
        XCTAssertEqual(restored.title, "b")
        XCTAssertTrue(restored.isCompleted)
        XCTAssertEqual(restored.completedAt, done)
        XCTAssertEqual(restored.sortOrder, 7)
        XCTAssertEqual(snapshot.index, 1)
    }

    func testProgressIsCompleteOnlyWhenAllDone() {
        XCTAssertFalse(SubtaskProgress(done: 1, total: 4).isComplete)
        XCTAssertTrue(SubtaskProgress(done: 4, total: 4).isComplete)
    }
}

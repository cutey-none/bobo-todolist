import SwiftData
import XCTest
@testable import QuadrantTodo

@MainActor
final class SubtaskRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: TaskRepository!
    private var parent: TaskItem!

    override func setUp() async throws {
        TaskRepository.simulatesSaveFailure = false
        container = try SubtaskTestSupport.makeContainer()
        repository = TaskRepository(context: container.mainContext)
        parent = try XCTUnwrap(repository.addTask(title: "准备发布", quadrant: .importantUrgent, to: []))
    }

    override func tearDown() async throws {
        TaskRepository.simulatesSaveFailure = false
    }

    private func titles() -> [String] { repository.subtasks(of: parent.id).map(\.title) }

    @discardableResult
    private func add(_ titles: String...) -> [SubtaskItem] {
        titles.compactMap { repository.addSubtask(title: $0, to: parent.id) }
    }

    func testSubtasksAreAppendedInOrder() {
        add("a", "b", "c", "d")
        XCTAssertEqual(titles(), ["a", "b", "c", "d"])
    }

    func testInvalidTitleCreatesNothing() {
        XCTAssertNil(repository.addSubtask(title: "   ", to: parent.id))
        XCTAssertNil(repository.addSubtask(title: String(repeating: "字", count: 201), to: parent.id))
        XCTAssertEqual(titles(), [])
    }

    func testPastedNewlinesBecomeSpacesAndTitleIsTrimmed() {
        add("  写\n更新说明  ")
        XCTAssertEqual(titles(), ["写 更新说明"])
    }

    func testFailedAddLeavesNoSubtask() {
        TaskRepository.simulatesSaveFailure = true
        XCTAssertNil(repository.addSubtask(title: "a", to: parent.id))
        TaskRepository.simulatesSaveFailure = false
        XCTAssertEqual(titles(), [])
    }

    func testRenameValidatesAndRollsBackOnFailure() throws {
        let item = try XCTUnwrap(add("a").first)
        XCTAssertFalse(repository.renameSubtask(item, to: " "))
        XCTAssertEqual(item.title, "a")
        XCTAssertTrue(repository.renameSubtask(item, to: " 写说明 "))
        XCTAssertEqual(item.title, "写说明")
        TaskRepository.simulatesSaveFailure = true
        XCTAssertFalse(repository.renameSubtask(item, to: "别的"))
        XCTAssertEqual(item.title, "写说明")
    }

    func testToggleSetsAndClearsCompletionTime() throws {
        let item = try XCTUnwrap(add("a").first)
        XCTAssertTrue(repository.toggleSubtask(item))
        XCTAssertTrue(item.isCompleted)
        XCTAssertNotNil(item.completedAt)
        XCTAssertTrue(repository.toggleSubtask(item))
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
    }

    func testFailedToggleKeepsState() throws {
        let item = try XCTUnwrap(add("a").first)
        TaskRepository.simulatesSaveFailure = true
        XCTAssertFalse(repository.toggleSubtask(item))
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
    }

    func testTogglingSubtasksNeverCompletesParent() throws {
        for item in add("a", "b") { XCTAssertTrue(repository.toggleSubtask(item)) }
        XCTAssertFalse(parent.isCompleted)
    }

    func testMoveByDeltaStopsAtEnds() {
        let items = add("a", "b", "c")
        XCTAssertTrue(repository.moveSubtask(items[2], by: -1))
        XCTAssertEqual(titles(), ["a", "c", "b"])
        XCTAssertTrue(repository.moveSubtask(items[0], by: -5))
        XCTAssertEqual(titles(), ["a", "c", "b"])
        XCTAssertTrue(repository.moveSubtask(items[0], by: 9))
        XCTAssertEqual(titles(), ["c", "b", "a"])
    }

    func testMoveBeforeTargetOrToEnd() {
        let items = add("a", "b", "c", "d")
        XCTAssertTrue(repository.moveSubtask(items[3], before: items[1].id))
        XCTAssertEqual(titles(), ["a", "d", "b", "c"])
        XCTAssertTrue(repository.moveSubtask(items[0], before: nil))
        XCTAssertEqual(titles(), ["d", "b", "c", "a"])
    }

    func testFailedReorderRestoresSiblingOrder() {
        let items = add("a", "b", "c")
        TaskRepository.simulatesSaveFailure = true
        XCTAssertFalse(repository.moveSubtask(items[2], before: items[0].id))
        TaskRepository.simulatesSaveFailure = false
        XCTAssertEqual(titles(), ["a", "b", "c"])
        XCTAssertEqual(items.map(\.sortOrder), [0, 1, 2])
    }

    func testProgressCountsPerParentAndIgnoresOtherParents() throws {
        let other = try XCTUnwrap(repository.addTask(title: "别的", quadrant: .importantUrgent, to: repository.allTasks()))
        let items = add("a", "b", "c")
        repository.toggleSubtask(items[1])
        repository.addSubtask(title: "x", to: other.id)

        let progress = TaskRepository.progress(of: repository.allSubtasks())
        XCTAssertEqual(progress[parent.id], SubtaskProgress(done: 1, total: 3))
        XCTAssertEqual(progress[other.id], SubtaskProgress(done: 0, total: 1))
    }

    func testSubtasksNeverAppearAsQuadrantTasks() {
        add("a", "b")
        let tasks = repository.allTasks()
        XCTAssertEqual(repository.activeTasks(in: .importantUrgent, from: tasks).map(\.title), ["准备发布"])
        XCTAssertEqual(tasks.count, 1)
    }

    func testSubtasksFollowParentAcrossQuadrants() {
        add("a")
        XCTAssertTrue(repository.move(parent, to: .notImportantUrgent))
        XCTAssertEqual(titles(), ["a"])
    }

    func testTaskLookupByID() {
        XCTAssertEqual(repository.task(withID: parent.id)?.title, "准备发布")
        XCTAssertNil(repository.task(withID: UUID()))
    }
}

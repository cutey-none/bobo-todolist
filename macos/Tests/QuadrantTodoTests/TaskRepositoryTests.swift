import SwiftData
import XCTest
@testable import QuadrantTodo

@MainActor
final class TaskRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: TaskRepository!

    override func setUp() async throws {
        container = try ModelContainer(
            for: TaskItem.self, ProgressEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        repository = TaskRepository(context: container.mainContext)
        TaskRepository.simulatesSaveFailure = false
    }

    override func tearDown() async throws {
        TaskRepository.simulatesSaveFailure = false
    }

    private func titles(in quadrant: Quadrant) -> [String] {
        repository.activeTasks(in: quadrant, from: repository.allTasks()).map(\.title)
    }

    func testNewTasksAreAppendedToTheEnd() {
        repository.addTask(title: "一", quadrant: .importantNotUrgent, to: repository.allTasks())
        repository.addTask(title: "二", quadrant: .importantNotUrgent, to: repository.allTasks())
        repository.addTask(title: "三", quadrant: .importantNotUrgent, to: repository.allTasks())
        XCTAssertEqual(titles(in: .importantNotUrgent), ["一", "二", "三"])
    }

    func testDuplicateTitlesCreateSeparateTasks() {
        repository.addTask(title: "整理材料", quadrant: .importantUrgent, to: repository.allTasks())
        repository.addTask(title: "整理材料", quadrant: .importantUrgent, to: repository.allTasks())
        XCTAssertEqual(titles(in: .importantUrgent), ["整理材料", "整理材料"])
    }

    func testFailedAddLeavesNoTask() {
        TaskRepository.simulatesSaveFailure = true
        XCTAssertNil(repository.addTask(title: "整理材料", quadrant: .importantUrgent, to: repository.allTasks()))
        TaskRepository.simulatesSaveFailure = false
        XCTAssertTrue(repository.allTasks().isEmpty)
    }

    func testFailedCompletionKeepsTaskActive() throws {
        let task = try XCTUnwrap(repository.addTask(title: "一", quadrant: .importantUrgent, to: []))
        TaskRepository.simulatesSaveFailure = true
        XCTAssertFalse(repository.toggleCompletion(task))
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
    }

    func testRestoredTaskIsAppendedToActiveList() throws {
        let first = try XCTUnwrap(repository.addTask(title: "一", quadrant: .importantUrgent, to: repository.allTasks()))
        repository.addTask(title: "二", quadrant: .importantUrgent, to: repository.allTasks())
        XCTAssertTrue(repository.toggleCompletion(first))
        XCTAssertEqual(titles(in: .importantUrgent), ["二"])
        XCTAssertTrue(repository.toggleCompletion(first))
        XCTAssertEqual(titles(in: .importantUrgent), ["二", "一"])
    }

    func testReorderMovesWithinQuadrant() throws {
        repository.addTask(title: "一", quadrant: .importantUrgent, to: repository.allTasks())
        let second = try XCTUnwrap(repository.addTask(title: "二", quadrant: .importantUrgent, to: repository.allTasks()))
        repository.addTask(title: "三", quadrant: .importantUrgent, to: repository.allTasks())
        XCTAssertTrue(repository.reorder(second, by: -1))
        XCTAssertEqual(titles(in: .importantUrgent), ["二", "一", "三"])
        XCTAssertTrue(repository.reorder(second, by: 5))
        XCTAssertEqual(titles(in: .importantUrgent), ["一", "三", "二"])
    }

    func testUndoRestoresOriginalPosition() throws {
        repository.addTask(title: "一", quadrant: .importantUrgent, to: repository.allTasks())
        let second = try XCTUnwrap(repository.addTask(title: "二", quadrant: .importantUrgent, to: repository.allTasks()))
        repository.addTask(title: "三", quadrant: .importantUrgent, to: repository.allTasks())
        let snapshot = try XCTUnwrap(repository.delete(second))
        XCTAssertEqual(titles(in: .importantUrgent), ["一", "三"])
        XCTAssertTrue(repository.restore(snapshot))
        XCTAssertEqual(titles(in: .importantUrgent), ["一", "二", "三"])
    }

    func testFailedReorderKeepsOrder() throws {
        repository.addTask(title: "一", quadrant: .importantUrgent, to: repository.allTasks())
        let second = try XCTUnwrap(repository.addTask(title: "二", quadrant: .importantUrgent, to: repository.allTasks()))
        TaskRepository.simulatesSaveFailure = true
        XCTAssertFalse(repository.reorder(second, by: -1))
        XCTAssertEqual(titles(in: .importantUrgent), ["一", "二"])
    }

    func testFailedDeleteKeepsTask() throws {
        let task = try XCTUnwrap(repository.addTask(title: "一", quadrant: .importantUrgent, to: repository.allTasks()))
        TaskRepository.simulatesSaveFailure = true
        XCTAssertNil(repository.delete(task))
        TaskRepository.simulatesSaveFailure = false
        XCTAssertEqual(titles(in: .importantUrgent), ["一"])
    }

    func testUndoCompletionRestoresOriginalPosition() throws {
        let first = try XCTUnwrap(repository.addTask(title: "一", quadrant: .importantUrgent, to: repository.allTasks()))
        repository.addTask(title: "二", quadrant: .importantUrgent, to: repository.allTasks())
        let before = CompletionState(first)
        XCTAssertTrue(repository.toggleCompletion(first))
        XCTAssertTrue(repository.restoreCompletion(first, to: before))
        XCTAssertFalse(first.isCompleted)
        XCTAssertNil(first.completedAt)
        XCTAssertEqual(titles(in: .importantUrgent), ["一", "二"])
    }
}

import XCTest
@testable import QuadrantTodo

@MainActor
final class SubtaskStateTests: XCTestCase {
    private var state: AppState!
    private var parent: TaskItem!

    override func setUp() async throws {
        TaskRepository.simulatesSaveFailure = false
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "subtask-state-\(UUID().uuidString)"))
        state = AppState(persistence: PersistenceController(inMemory: true), settings: SettingsStore(defaults: defaults))
        parent = try XCTUnwrap(state.repository.addTask(title: "准备发布", quadrant: .importantUrgent, to: []))
    }

    override func tearDown() async throws {
        TaskRepository.simulatesSaveFailure = false
    }

    private func titles() -> [String] { state.repository.subtasks(of: parent.id).map(\.title) }

    func testAddReportsValidationProblems() {
        XCTAssertEqual(state.addSubtask("  ", to: parent.id), TaskTitle.Problem.empty.message)
        XCTAssertNil(state.addSubtask("a", to: parent.id))
        XCTAssertEqual(titles(), ["a"])
    }

    func testAddReportsSaveFailure() {
        TaskRepository.simulatesSaveFailure = true
        XCTAssertEqual(state.addSubtask("a", to: parent.id), "保存失败，请重试")
    }

    func testRenameReportsProblemAndKeepsTitle() throws {
        XCTAssertNil(state.addSubtask("a", to: parent.id))
        let item = try XCTUnwrap(state.repository.subtasks(of: parent.id).first)
        XCTAssertEqual(state.renameSubtask(item, to: ""), TaskTitle.Problem.empty.message)
        XCTAssertNil(state.renameSubtask(item, to: "b"))
        XCTAssertEqual(titles(), ["b"])
    }

    func testDeleteSubtaskIsUndoable() throws {
        for title in ["a", "b", "c"] { XCTAssertNil(state.addSubtask(title, to: parent.id)) }
        let b = try XCTUnwrap(state.repository.subtasks(of: parent.id).first { $0.title == "b" })
        state.deleteSubtask(b)
        XCTAssertEqual(titles(), ["a", "c"])
        XCTAssertEqual(state.undo?.message, "已删除子待办「b」")

        state.performUndo()
        XCTAssertEqual(titles(), ["a", "b", "c"])
        XCTAssertTrue(state.undoQueue.isEmpty)
    }

    func testPromotionIsUndoable() throws {
        XCTAssertNil(state.addSubtask("a", to: parent.id))
        let a = try XCTUnwrap(state.repository.subtasks(of: parent.id).first)
        state.promoteSubtask(a)
        XCTAssertEqual(titles(), [])
        XCTAssertEqual(state.repository.allTasks().count, 2)
        XCTAssertEqual(state.undo?.message, "已将「a」提升为独立待办")

        state.performUndo()
        XCTAssertEqual(titles(), ["a"])
        XCTAssertEqual(state.repository.allTasks().map(\.title), ["准备发布"])
    }

    func testDeletingParentUndoRestoresSubtasks() {
        XCTAssertNil(state.addSubtask("a", to: parent.id))
        let parentID = parent.id
        XCTAssertTrue(state.delete(parent))
        XCTAssertEqual(state.undo?.message, "已删除「准备发布」")
        state.performUndo()
        XCTAssertEqual(state.repository.subtasks(of: parentID).map(\.title), ["a"])
    }

    func testUndoSubtaskAfterParentDeletedIsDroppedWithNotice() throws {
        XCTAssertNil(state.addSubtask("a", to: parent.id))
        let a = try XCTUnwrap(state.repository.subtasks(of: parent.id).first)
        state.deleteSubtask(a)
        // 父待办在子待办撤销期内被删除且其撤销已不可用（直接经仓储删除，不进撤销队列）。
        XCTAssertNotNil(state.repository.delete(parent))
        XCTAssertEqual(state.undoQueue.count, 1)

        state.performUndo()
        XCTAssertTrue(state.undoQueue.isEmpty)
        XCTAssertEqual(state.notice?.text, "原待办已删除，无法撤销")
        XCTAssertTrue(state.repository.allSubtasks().isEmpty)
    }

    func testPendingSubtaskInputKeepsPanelOpen() {
        XCTAssertFalse(state.hasUnsubmittedDraft)
        let token = UUID()
        state.activeSubtaskInputs.insert(token)
        XCTAssertTrue(state.hasUnsubmittedDraft)
        state.activeSubtaskInputs.remove(token)
        XCTAssertFalse(state.hasUnsubmittedDraft)
    }

    /// 主面板与编辑浮层可能同时有子待办列表：任一列表的输入框有焦点都算，且各自只撤销自己的标记。
    func testSubtaskFieldFocusIsTrackedPerList() {
        let row = UUID(), popup = UUID()
        XCTAssertFalse(state.focusedSubtaskField)
        state.focusedSubtaskInputs.insert(row)
        state.focusedSubtaskInputs.insert(popup)
        state.focusedSubtaskInputs.remove(row)
        XCTAssertTrue(state.focusedSubtaskField, "另一个列表仍有焦点")
        state.focusedSubtaskInputs.remove(popup)
        XCTAssertFalse(state.focusedSubtaskField)
    }

    func testFailedToggleShowsError() throws {
        XCTAssertNil(state.addSubtask("a", to: parent.id))
        let a = try XCTUnwrap(state.repository.subtasks(of: parent.id).first)
        TaskRepository.simulatesSaveFailure = true
        state.toggleSubtask(a)
        XCTAssertFalse(a.isCompleted)
        XCTAssertEqual(state.notice?.isError, true)
    }
}

final class SubtaskDragTests: XCTestCase {
    func testPayloadRoundTripsAndRejectsTaskIDs() {
        let id = UUID()
        XCTAssertEqual(SubtaskDrag.id(from: SubtaskDrag.payload(id)), id)
        XCTAssertNil(SubtaskDrag.id(from: id.uuidString), "普通事项的拖拽载荷不能被当作子待办")
        XCTAssertNil(SubtaskDrag.id(from: "subtask:not-a-uuid"))
    }
}

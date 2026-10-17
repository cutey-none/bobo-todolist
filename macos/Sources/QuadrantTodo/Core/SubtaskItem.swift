import Foundation
import SwiftData

/// 子待办（PRD 15）：只有一层，没有描述与象限，随父待办显示，靠 parentID 关联。
@Model
final class SubtaskItem {
    @Attribute(.unique) var id: UUID
    var parentID: UUID
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        parentID: UUID,
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 删除或提升后可撤销的快照；index 是当时在父待办中的位置。
struct SubtaskSnapshot: Equatable {
    let id: UUID
    let parentID: UUID
    let title: String
    let isCompleted: Bool
    let completedAt: Date?
    let createdAt: Date
    let index: Int

    init(_ item: SubtaskItem, index: Int) {
        id = item.id
        parentID = item.parentID
        title = item.title
        isCompleted = item.isCompleted
        completedAt = item.completedAt
        createdAt = item.createdAt
        self.index = index
    }

    func makeSubtask(sortOrder: Int) -> SubtaskItem {
        SubtaskItem(
            id: id,
            parentID: parentID,
            title: title,
            isCompleted: isCompleted,
            completedAt: completedAt,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }
}

/// 父待办行上的进度胶囊。
struct SubtaskProgress: Equatable {
    let done: Int
    let total: Int

    var isComplete: Bool { done == total }
}

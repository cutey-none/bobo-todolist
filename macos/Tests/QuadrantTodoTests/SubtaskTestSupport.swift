import SwiftData
@testable import QuadrantTodo

enum SubtaskTestSupport {
    /// 与应用相同的完整 schema，存于内存。
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(PersistenceController.modelTypes),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

import XCTest
@testable import QuadrantTodo

@MainActor
final class SampleTaskTests: XCTestCase {
    private func withSettings(_ body: (SettingsStore) throws -> Void) rethrows {
        let suite = "QuadrantTodo.SampleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(SettingsStore(defaults: defaults))
    }

    func testFirstLaunchSeedsExactlyFourIncludingOneCompleted() {
        withSettings { settings in
            let persistence = PersistenceController(inMemory: true)
            persistence.seedSampleTasksIfNeeded(settings: settings)
            let tasks = persistence.repository.allTasks()
            XCTAssertEqual(tasks.count, 4)
            XCTAssertEqual(tasks.filter(\.isCompleted).count, 1)
            XCTAssertEqual(Set(tasks.map(\.quadrant)), Set(Quadrant.allCases))
            XCTAssertNotNil(tasks.first(where: \.isCompleted)?.completedAt)
            persistence.seedSampleTasksIfNeeded(settings: settings)
            XCTAssertEqual(persistence.repository.allTasks().count, 4)
        }
    }

    func testExistingDataIsUnchangedAndEmptyingItDoesNotReseed() {
        withSettings { settings in
            let persistence = PersistenceController(inMemory: true)
            let repository = persistence.repository
            let task = repository.addTask(title: "我的事项", quadrant: .importantUrgent,
                                          note: "- [ ] 原有描述", to: [])!
            persistence.seedSampleTasksIfNeeded(settings: settings)
            XCTAssertEqual(repository.allTasks().map(\.id), [task.id])
            XCTAssertEqual(task.note, "- [ ] 原有描述")
            XCTAssertTrue(settings.didSeedSampleTasks)
            _ = repository.delete(task)
            persistence.seedSampleTasksIfNeeded(settings: settings)
            XCTAssertTrue(repository.allTasks().isEmpty)
        }
    }

    func testFailedSeedingCanBeRetried() {
        withSettings { settings in
            let persistence = PersistenceController(inMemory: true)
            TaskRepository.simulatesSaveFailure = true
            defer { TaskRepository.simulatesSaveFailure = false }
            persistence.seedSampleTasksIfNeeded(settings: settings)
            XCTAssertFalse(settings.didSeedSampleTasks)
            XCTAssertTrue(persistence.repository.allTasks().isEmpty)
            TaskRepository.simulatesSaveFailure = false
            persistence.seedSampleTasksIfNeeded(settings: settings)
            XCTAssertEqual(persistence.repository.allTasks().count, 4)
        }
    }
}

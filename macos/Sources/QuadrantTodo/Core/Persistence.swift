import Foundation
import SwiftData

/// SwiftData 容器（PRD 5.2）：本地 SQLite，无需账户与网络。
@MainActor
final class PersistenceController {
    let container: ModelContainer

    /// 与 SwiftUI `@Query` 使用同一个上下文，避免跨上下文删除 / 更新不生效。
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) {
        let storeURL = PersistenceController.storeURL()
        let configuration = ModelConfiguration(url: storeURL)
        do {
            container = try ModelContainer(
                for: TaskItem.self, ProgressEntry.self,
                configurations: inMemory ? ModelConfiguration(isStoredInMemoryOnly: true) : configuration
            )
        } catch {
            // 容器损坏时降级为内存存储，保证应用仍可打开。
            NSLog("QuadrantTodo: 打开本地数据库失败，改用内存存储 %@", String(reflecting: error))
            if !inMemory { Self.backupBrokenStore(at: storeURL) }
            container = try! ModelContainer(
                for: TaskItem.self, ProgressEntry.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        container.mainContext.autosaveEnabled = true
    }

    var repository: TaskRepository { TaskRepository(context: context) }

    private static func backupBrokenStore(at url: URL) {
        let suffix = ".broken-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        for component in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + component)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            do {
                try FileManager.default.moveItem(at: source, to: URL(fileURLWithPath: url.path + suffix + component))
            } catch {
                NSLog("QuadrantTodo: 备份数据库失败 %@: %@", source.path, String(reflecting: error))
            }
        }
    }

    static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = base.appendingPathComponent("QuadrantTodo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Tasks.store")
    }

    /// 首次启动放入示例任务，让四象限一眼可见（可在设置里清空）。
    func seedSampleTasksIfNeeded(settings: SettingsStore) {
        guard !settings.didSeedSampleTasks, repository.allTasks().isEmpty else { return }
        settings.didSeedSampleTasks = true

        let now = Date()
        let samples: [(String, Quadrant, Bool, Int)] = [
            ("修复发布阻塞问题", .importantUrgent, false, 0),
            ("回复客户关键邮件", .importantUrgent, false, 1),
            ("确认今日发布窗口", .importantUrgent, false, 2),
            ("制定下季度目标", .importantNotUrgent, false, 0),
            ("学习 SwiftUI 动画", .importantNotUrgent, false, 1),
            ("预订会议室", .notImportantUrgent, false, 0),
            ("回复合作方确认邮件", .notImportantUrgent, false, 1),
            ("整理桌面文件", .notImportantNotUrgent, false, 0),
            ("旧版界面回归检查", .importantUrgent, true, 0),
            ("同步团队周报模板", .importantNotUrgent, true, 0),
            ("归档上季度发票", .notImportantUrgent, true, 0),
            ("清理订阅邮件", .notImportantNotUrgent, true, 0)
        ]
        for (offset, sample) in samples.enumerated() {
            let task = TaskItem(
                title: sample.0,
                quadrant: sample.1,
                isCompleted: sample.2,
                createdAt: now.addingTimeInterval(Double(-offset * 60)),
                completedAt: sample.2 ? now.addingTimeInterval(Double(-offset * 30)) : nil,
                sortOrder: sample.3
            )
            context.insert(task)
        }
        repository.save()
    }
}

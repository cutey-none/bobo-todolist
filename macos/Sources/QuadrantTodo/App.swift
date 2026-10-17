import AppKit
import Combine
import SwiftData
import SwiftUI

@main
struct QuadrantTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // SwiftUI 至少需要一个场景；设置窗口实际由 AppDelegate.settingsWindow 管理。
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var persistence: PersistenceController!
    private var settings: SettingsStore!
    private var appState: AppState!
    private var controller: PanelController!
    private var hotKeys: HotKeyCenter!
    private var statusItem: StatusItemController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        persistence = PersistenceController()
        settings = SettingsStore.shared
        appState = AppState(persistence: persistence, settings: settings)
        persistence.seedSampleTasksIfNeeded(settings: settings)

        let root = RootView(state: appState, settings: settings)
            .modelContainer(persistence.container)

        controller = PanelController(state: appState, settings: settings, rootView: AnyView(root))
        appState.controller = controller

        // If the app quit during the delete-undo grace period, the task is gone but its
        // progress entries intentionally remained available for undo. A relaunch means
        // that undo is no longer possible, so reclaim any orphaned text/images now.
        persistence.repository.purgeOrphanProgress()
        persistence.repository.migrateLegacyProgressToDescriptions(from: persistence.repository.allTasks())
        persistence.repository.migrateLegacyDescriptionsToMarkdown(from: persistence.repository.allTasks())

        statusItem = StatusItemController(
            state: appState,
            settings: settings,
            controller: controller,
            openSettings: { AppDelegate.openSettingsWindow() },
            checkForUpdates: {
                AppDelegate.openSettingsWindow()
                UpdateController.shared.check()
            }
        )
        UpdateController.shared.appState = appState

        hotKeys = HotKeyCenter()
        registerHotKey()
        settings.$hotkey
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.registerHotKey() }
            .store(in: &cancellables)

        if ProcessInfo.processInfo.environment["QT_START_EXPANDED"] == "1" {
            NSLog("QuadrantTodo: 启动即展开")
            appState.expand()
        }
        // 助手脚本替换完成后会重新打开应用，这里告知升级结果，并清理被中断的升级留下的暂存副本。
        UpdateInstaller.removeStaleStaging(nextTo: Bundle.main.bundleURL)
        DispatchQueue.main.async { AppDelegate.presentUpdateResultIfNeeded() }
        #if DEBUG
        DebugUIDriver.startIfRequested(window: controller.panel)
        #endif
    }

    private func registerHotKey() {
        hotKeys.register(settings.hotkey) { [weak self] in
            guard let self else { return }
            if self.appState.isExpanded {
                self.appState.collapse()
            } else {
                self.appState.expand(focusInput: true)
            }
        }
    }

    private static let settingsWindow = SettingsWindowController {
        SettingsView(settings: SettingsStore.shared, updater: UpdateController.shared) {
            NSWorkspace.shared.activateFileViewerSelecting([PersistenceController.storeURL()])
        }
    }

    static func openSettingsWindow() {
        settingsWindow.show()
    }

    static func presentUpdateResultIfNeeded() {
        guard let result = UpdateResult.consume(at: UpdatePaths.resultFile) else { return }
        let alert = NSAlert()
        alert.alertStyle = result.succeeded ? .informational : .warning
        alert.messageText = result.title
        alert.informativeText = result.detail
        NSApp.activate()
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        UpdateController.allowsTermination(during: UpdateController.shared.phase) ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.finishPendingDeletes()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

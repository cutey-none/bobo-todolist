import AppKit
import Combine
import SwiftData
import SwiftUI

@main
struct QuadrantTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView(settings: SettingsStore.shared) {
                NSWorkspace.shared.activateFileViewerSelecting([PersistenceController.storeURL()])
            }
        }
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
            openSettings: { AppDelegate.openSettingsWindow() }
        )

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

    /// SwiftUI Settings 场景的标准打开方式（兼容不同系统版本的 selector 名称）。
    static func openSettingsWindow() {
        NSApp.activate()
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

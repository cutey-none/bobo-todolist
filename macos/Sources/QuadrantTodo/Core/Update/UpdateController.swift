import AppKit
import Combine

/// 应用内更新的状态机：检查 → 发现新版本 → 下载 → 校验与备份 → 退出并由助手替换。
@MainActor
final class UpdateController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, notes: String)
        case unavailableForArch(version: String)
        case downloading(Double)
        case preparing
        case relaunching
        case failed(String)
    }

    /// 下载、数据与备份位置；测试可替换为临时目录。
    struct Locations {
        var downloads: URL
        var data: URL
        var backupRoot: URL
        var resultFile: URL

        static var standard: Locations {
            Locations(
                downloads: UpdatePaths.downloadsDirectory,
                data: UpdatePaths.dataDirectory,
                backupRoot: UpdatePaths.backupRoot,
                resultFile: UpdatePaths.resultFile
            )
        }
    }

    typealias EditingSnapshot = (isEditing: Bool, drafts: [String])

    static let shared = UpdateController()

    @Published private(set) var phase: Phase = .idle
    weak var appState: AppState?
    let currentVersion: AppVersion?

    private let installer: UpdateInstaller
    private let feedURL: URL
    private let architecture: String
    private let appURL: URL
    private let locations: Locations
    private let editingProbe: (() -> EditingSnapshot)?
    private let terminate: @MainActor () -> Void
    private var package: UpdatePackage?
    private var availablePhase: Phase?
    private var task: Task<Void, Never>?

    init(
        installer: UpdateInstaller = UpdateInstaller(),
        feedURL: URL = UpdatePaths.feedURL,
        currentVersion: AppVersion? = .current,
        architecture: String = CPUArchitecture.current,
        appURL: URL = Bundle.main.bundleURL,
        locations: Locations = .standard,
        editingProbe: (() -> EditingSnapshot)? = nil,
        terminate: @escaping @MainActor () -> Void = { @MainActor in NSApp.terminate(nil) }
    ) {
        self.installer = installer
        self.feedURL = feedURL
        self.currentVersion = currentVersion
        self.architecture = architecture
        self.appURL = appURL
        self.locations = locations
        self.editingProbe = editingProbe
        self.terminate = terminate
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .preparing, .relaunching: return true
        default: return false
        }
    }

    /// 校验与备份阶段不能中断：此时退出会在应用旁留下不完整的暂存副本。
    nonisolated static func allowsTermination(during phase: Phase) -> Bool {
        phase != .preparing
    }

    func check() {
        guard !isBusy else { return }
        guard let currentVersion else {
            phase = .failed(UpdateError.unrecognizedVersion.message)
            return
        }
        phase = .checking
        let installer = installer, feedURL = feedURL, architecture = architecture
        task = Task {
            do {
                let release = try await installer.fetchRelease(from: feedURL)
                guard let lookup = release.lookup(current: currentVersion, architecture: architecture) else {
                    throw UpdateError.unrecognizedVersion
                }
                switch lookup {
                case .upToDate:
                    package = nil
                    phase = .upToDate
                case .missingPackage(let version):
                    package = nil
                    phase = .unavailableForArch(version: version.description)
                case .available(let found, let notes):
                    package = found
                    let available = Phase.available(version: found.version.description, notes: notes)
                    availablePhase = available
                    phase = available
                }
            } catch {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func install() {
        guard case .available = phase, let package, let snapshot = editingSnapshot() else { return }
        let input = UpdatePreflight.input(appURL: appURL, isEditing: snapshot.isEditing, drafts: snapshot.drafts)
        if let problem = UpdatePreflight.check(input) {
            phase = .failed(problem.message)
            return
        }

        let installer = installer, target = appURL, locations = locations
        phase = .downloading(0)
        task = Task {
            do {
                let folder = locations.downloads
                let dmg = folder.appendingPathComponent(package.dmgName)
                let checksum = folder.appendingPathComponent(package.dmgName + ".sha256")
                try await installer.download(package.dmgURL, to: dmg) { value in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.phase else { return }
                        self.phase = .downloading(value)
                    }
                }
                try await installer.download(package.checksumURL, to: checksum) { _ in }
                try Task.checkCancellation()

                phase = .preparing
                // hdiutil / ditto / codesign 是阻塞调用，放到后台执行。
                let (staged, backup) = try await Task.detached {
                    try installer.verifyChecksum(file: dmg, checksumFile: checksum, fileName: package.dmgName)
                    let staged = try installer.stage(dmg: dmg, nextTo: target, expectedVersion: package.version)
                    do {
                        let backup = try installer.backup(
                            dataDirectory: locations.data,
                            backupRoot: locations.backupRoot,
                            defaultsDomain: UpdatePaths.bundleIdentifier
                        )
                        return (staged, backup)
                    } catch {
                        try? FileManager.default.removeItem(at: staged.stagingDirectory)
                        throw error
                    }
                }.value

                // 下载与准备期间面板仍可使用；退出前再检查一次，避免丢掉刚开始的编辑或草稿。
                if let snapshot = editingSnapshot(),
                   let problem = UpdatePreflight.check(
                       UpdatePreflight.input(appURL: target, isEditing: snapshot.isEditing, drafts: snapshot.drafts)
                   ) {
                    try? FileManager.default.removeItem(at: staged.stagingDirectory)
                    phase = .failed(problem.message)
                    return
                }

                do {
                    try installer.launchHelper(
                        staged: staged, target: target, backup: backup, version: package.version, resultFile: locations.resultFile
                    )
                } catch {
                    try? FileManager.default.removeItem(at: staged.stagingDirectory)
                    throw error
                }
                try? FileManager.default.removeItem(at: dmg)
                phase = .relaunching
                terminate()
            } catch {
                if error is CancellationError || (error as? UpdateError) == .cancelled {
                    phase = availablePhase ?? .idle
                } else {
                    phase = .failed(Self.message(for: error))
                }
            }
        }
    }

    /// 只在下载阶段可取消；校验与备份很快，且中途取消会留下半成品。
    func cancel() {
        guard case .downloading = phase else { return }
        task?.cancel()
    }

    private func editingSnapshot() -> EditingSnapshot? {
        if let editingProbe { return editingProbe() }
        guard let appState else { return nil }
        return (appState.editing != nil, Array(appState.drafts.values))
    }

    func waitForCurrentTask() async {
        await task?.value
    }

    private static func message(for error: Error) -> String {
        (error as? UpdateError)?.message ?? error.localizedDescription
    }
}

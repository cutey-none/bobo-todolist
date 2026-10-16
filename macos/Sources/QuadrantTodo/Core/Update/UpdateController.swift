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

    static let shared = UpdateController()

    @Published private(set) var phase: Phase = .idle
    weak var appState: AppState?
    let currentVersion: AppVersion?

    private let installer: UpdateInstaller
    private let feedURL: URL
    private let architecture: String
    private let appURL: URL
    private var package: UpdatePackage?
    private var availablePhase: Phase?
    private var task: Task<Void, Never>?

    init(
        installer: UpdateInstaller = UpdateInstaller(),
        feedURL: URL = UpdatePaths.feedURL,
        currentVersion: AppVersion? = .current,
        architecture: String = CPUArchitecture.current,
        appURL: URL = Bundle.main.bundleURL
    ) {
        self.installer = installer
        self.feedURL = feedURL
        self.currentVersion = currentVersion
        self.architecture = architecture
        self.appURL = appURL
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
        guard case .available = phase, let package, let appState else { return }
        let input = UpdatePreflight.input(
            appURL: appURL,
            isEditing: appState.editing != nil,
            drafts: Array(appState.drafts.values)
        )
        if let problem = UpdatePreflight.check(input) {
            phase = .failed(problem.message)
            return
        }

        let installer = installer, target = appURL
        phase = .downloading(0)
        task = Task {
            do {
                let folder = UpdatePaths.downloadsDirectory
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
                            dataDirectory: UpdatePaths.dataDirectory,
                            backupRoot: UpdatePaths.backupRoot,
                            defaultsDomain: UpdatePaths.bundleIdentifier
                        )
                        return (staged, backup)
                    } catch {
                        try? FileManager.default.removeItem(at: staged.stagingDirectory)
                        throw error
                    }
                }.value

                do {
                    try installer.launchHelper(staged: staged, target: target, backup: backup, version: package.version)
                } catch {
                    try? FileManager.default.removeItem(at: staged.stagingDirectory)
                    throw error
                }
                try? FileManager.default.removeItem(at: dmg)
                phase = .relaunching
                NSApp.terminate(nil)
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

    func waitForCurrentTask() async {
        await task?.value
    }

    private static func message(for error: Error) -> String {
        (error as? UpdateError)?.message ?? error.localizedDescription
    }
}

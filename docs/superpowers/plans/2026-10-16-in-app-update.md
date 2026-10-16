# 应用内更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户在设置页或菜单栏手动「检查更新」，发现 GitHub Releases 上的新版本后一键下载、校验、备份、替换 `.app` 并重启，不改动任何待办数据。

**Architecture:** 纯逻辑（版本比较、Release 解析、预检、校验和解析）与副作用（下载、hdiutil、ditto、codesign、defaults、助手脚本）分离，副作用经可注入的 `CommandRunning` 执行。`UpdateController`（`@MainActor ObservableObject` 状态机）串联各步，供 SwiftUI 设置页和 AppKit 菜单使用。替换由 app 退出后独立运行的 zsh 助手脚本完成，结果写入 JSON，新版启动时读取并弹窗告知。

**Tech Stack:** Swift 5.9 / SwiftUI / AppKit、Foundation `URLSession`、CryptoKit、XCTest、zsh、系统 `hdiutil` / `ditto` / `codesign` / `defaults` / `xattr`。

**Spec:** `docs/superpowers/specs/2026-10-16-in-app-update-design.md`

## Global Constraints

- 只在用户手动点击「检查更新」时联网；不做启动自动检查或后台安装。
- 不引入任何第三方依赖或新的 Swift 包；`Package.swift` 不改。
- 最低系统 macOS 14（`Package.swift` 的 `.macOS(.v14)`），Swift 语言模式 v5。
- Release 源：`https://api.github.com/repos/cutey-none/bobo-todolist/releases/latest`；开发时可用环境变量 `QT_UPDATE_FEED_URL` 覆盖（支持 `file://`）。
- 资源命名与 `macos/package-dmg.sh` 一致：`QuadrantTodo_<版本>_<arch>.dmg` 与 `QuadrantTodo_<版本>_<arch>.dmg.sha256`，`<arch>` 为 `arm64` 或 `x86_64`；tag 为 `v<版本>`。
- Bundle id：`com.cutey.quadranttodo`；UserDefaults 域同名。
- 数据目录：`PersistenceController.storeURL().deletingLastPathComponent()`（自动遵循 `QT_DATA_DIR`）。升级流程**从不写入**数据目录和 UserDefaults。
- 备份根目录：`~/Library/Application Support/QuadrantTodoBackups/`（`QT_BACKUP_DIR` 可覆盖，与 `macos/upgrade.sh` 一致），每次升级建 `update-<yyyyMMdd-HHmmss>-<6位随机>/`，含 `Data/`、`Settings.plist`（域存在时）、替换后的 `Previous.app`。
- 下载与结果文件：`~/Library/Caches/QuadrantTodo/Updates/`（`Downloads/` 子目录、`last-result.json`）。
- 不请求管理员密码；目标目录不可写时拒绝并说明。
- 新代码放 `macos/Sources/QuadrantTodo/Core/Update/`，测试放 `macos/Tests/QuadrantTodoTests/`；注释与界面文案用中文，风格与现有代码一致。
- 每个任务一个（或少量）小步提交，Conventional Commit 前缀，提交信息末尾带 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。提交前检查 `git status`、`git diff --check`、暂存 diff。
- 所有代码改动完成后运行 `macos/build.sh` 重建 `macos/build/QuadrantTodo.app` 并报告结果。

**与 spec 的两处有意偏差（在 Task 1 提交时同步修订 spec）：**
1. 挂载使用显式 `-mountpoint <临时目录>` 代替 `-mountrandom`，免去解析 hdiutil 输出，效果等价。
2. 升级结果用 `NSAlert` 告知，而不是面板 notice：启动时面板处于收起状态，1.6 秒的 notice 用户看不到。

## Review Focus

1. **非纯数字 tag（如 `v0.0.2-beta`、`latest`）**：不得崩溃或误判为新版本，应提示「无法识别版本号」。→ Task 1 `testUnparseableTagYieldsNoLookup`、Task 4 `testUnrecognizedTagFails`。
2. **`.sha256` 文件格式变体**（大写十六进制、`*文件名` 二进制标记、末尾换行、只有哈希无文件名）：应接受；文件名不符应拒绝。→ Task 3 `UpdateChecksumTests`。
3. **路径含空格和中文**（`QT_DATA_DIR`、`~/Applications/My Apps 中文/`）：备份与替换都应正常。→ Task 3 `testBackupCopiesDataDirectoryWithSpacesAndChinese`、`testHelperReplacesAppAtPathWithSpaces`。
4. **Release 说明为空或 `null`**：应正常显示新版本，只是不显示说明。→ Task 1 `testNullBodyBecomesEmptyNotes`。
5. **升级流程中途任一步失败**（签名无效、版本不符、备份失败）：目标目录下不得残留 `.quadrant-update.*` 暂存目录，旧 app 不变。→ Task 3 `testStageRejectsVersionMismatchAndCleansUp`、`testStageRejectsInvalidSignatureAndCleansUp`。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| Create `macos/Sources/QuadrantTodo/Core/Update/AppVersion.swift` | 版本号解析与比较 |
| Create `macos/Sources/QuadrantTodo/Core/Update/ReleaseInfo.swift` | GitHub Release JSON 解码、按架构选资源、`CPUArchitecture` |
| Create `macos/Sources/QuadrantTodo/Core/Update/UpdatePreflight.swift` | 升级前检查（纯函数）+ 从文件系统收集输入 |
| Create `macos/Sources/QuadrantTodo/Core/Update/UpdateSupport.swift` | `UpdateError`、`UpdatePaths`、`CommandRunning` / `ProcessCommandRunner`、`UpdateChecksum`、`UpdateResult` |
| Create `macos/Sources/QuadrantTodo/Core/Update/UpdateHelperScript.swift` | 助手 zsh 脚本内容与落盘 |
| Create `macos/Sources/QuadrantTodo/Core/Update/UpdateInstaller.swift` | 获取 Release、下载、校验、挂载暂存、验签、备份、启动助手 |
| Create `macos/Sources/QuadrantTodo/Core/Update/UpdateController.swift` | 状态机 |
| Create `macos/Sources/QuadrantTodo/Views/UpdateStatusView.swift` | 设置页「关于与更新」区的状态视图 |
| Modify `macos/Sources/QuadrantTodo/Views/SettingsView.swift` | 加入 `updater` 与新 section，窗口加高 |
| Modify `macos/Sources/QuadrantTodo/Core/StatusItemController.swift` | 菜单项「检查更新…」 |
| Modify `macos/Sources/QuadrantTodo/App.swift` | 注入 `UpdateController`、启动时弹出升级结果 |
| Create tests `AppVersionTests.swift`、`ReleaseInfoTests.swift`、`UpdatePreflightTests.swift`、`UpdateChecksumTests.swift`、`UpdateInstallerTests.swift`、`UpdateHelperScriptTests.swift`、`UpdateControllerTests.swift` | 单元 / 集成测试 |
| Modify `macos/README.md`、`docs/prd/quadrant-todo-ui-prd.md`、`docs/verify/README.md` | 文档与验证记录 |

运行测试统一在仓库根目录执行：`swift test --package-path macos --filter <测试类名>`。

---

### Task 1: 版本比较与 Release 解析

**Files:**
- Create: `macos/Sources/QuadrantTodo/Core/Update/AppVersion.swift`
- Create: `macos/Sources/QuadrantTodo/Core/Update/ReleaseInfo.swift`
- Test: `macos/Tests/QuadrantTodoTests/AppVersionTests.swift`
- Test: `macos/Tests/QuadrantTodoTests/ReleaseInfoTests.swift`
- Modify: `docs/superpowers/specs/2026-10-16-in-app-update-design.md`（记录上面两处偏差）

**Interfaces:**
- Consumes: 无
- Produces:
  - `struct AppVersion: Comparable, CustomStringConvertible { let components: [Int]; init?(_ raw: String); static var current: AppVersion? }`
  - `struct ReleaseAsset: Decodable, Equatable { let name: String; let downloadURL: URL }`
  - `struct UpdatePackage: Equatable { let version: AppVersion; let dmgName: String; let dmgURL: URL; let checksumURL: URL }`
  - `enum ReleaseLookup: Equatable { case upToDate(AppVersion); case available(UpdatePackage, notes: String); case missingPackage(AppVersion) }`
  - `struct ReleaseInfo: Decodable, Equatable { let tagName: String; let body: String?; let assets: [ReleaseAsset]; static func decode(_ data: Data) throws -> ReleaseInfo; var version: AppVersion?; func lookup(current: AppVersion, architecture: String) -> ReleaseLookup? }`
  - `enum CPUArchitecture { static var current: String }`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/QuadrantTodoTests/AppVersionTests.swift`:

```swift
import XCTest
@testable import QuadrantTodo

final class AppVersionTests: XCTestCase {
    func testParsesPlainAndPrefixedVersions() {
        XCTAssertEqual(AppVersion("0.0.1")?.components, [0, 0, 1])
        XCTAssertEqual(AppVersion("v0.1.0")?.components, [0, 1, 0])
        XCTAssertEqual(AppVersion(" V1.2 ")?.components, [1, 2])
    }

    func testRejectsNonNumericVersions() {
        XCTAssertNil(AppVersion("v0.0.2-beta"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.2.3.4.5"))
        XCTAssertNil(AppVersion("１.0")) // 全角数字
    }

    func testComparesNumericallyNotLexically() {
        XCTAssertLessThan(AppVersion("0.0.9")!, AppVersion("0.0.10")!)
        XCTAssertLessThan(AppVersion("0.9.9")!, AppVersion("1.0.0")!)
        XCTAssertGreaterThan(AppVersion("0.1")!, AppVersion("0.0.9")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertFalse(AppVersion("1.0")! < AppVersion("1.0.0")!)
        XCTAssertLessThan(AppVersion("1.0")!, AppVersion("1.0.1")!)
    }

    func testDescriptionDropsPrefix() {
        XCTAssertEqual(AppVersion("v0.0.2")?.description, "0.0.2")
    }
}
```

`macos/Tests/QuadrantTodoTests/ReleaseInfoTests.swift`:

```swift
import XCTest
@testable import QuadrantTodo

final class ReleaseInfoTests: XCTestCase {
    private func release(tag: String, body: String? = "修复若干问题", assets: [String]) throws -> ReleaseInfo {
        let assetJSON = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)"}"#
        }.joined(separator: ",")
        let bodyJSON = body.map { #""\#($0)""# } ?? "null"
        let json = #"{"tag_name":"\#(tag)","body":\#(bodyJSON),"assets":[\#(assetJSON)]}"#
        return try ReleaseInfo.decode(Data(json.utf8))
    }

    func testNewerReleaseWithMatchingAssetsIsAvailable() throws {
        let info = try release(tag: "v0.0.2", assets: [
            "QuadrantTodo_0.0.2_arm64.dmg", "QuadrantTodo_0.0.2_arm64.dmg.sha256"
        ])
        let lookup = info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64")
        let expected = UpdatePackage(
            version: AppVersion("0.0.2")!,
            dmgName: "QuadrantTodo_0.0.2_arm64.dmg",
            dmgURL: URL(string: "https://example.com/QuadrantTodo_0.0.2_arm64.dmg")!,
            checksumURL: URL(string: "https://example.com/QuadrantTodo_0.0.2_arm64.dmg.sha256")!
        )
        XCTAssertEqual(lookup, .available(expected, notes: "修复若干问题"))
    }

    func testSameOrOlderReleaseIsUpToDate() throws {
        let info = try release(tag: "v0.0.1", assets: [])
        XCTAssertEqual(info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64"), .upToDate(AppVersion("0.0.1")!))
        XCTAssertEqual(info.lookup(current: AppVersion("0.1.0")!, architecture: "arm64"), .upToDate(AppVersion("0.0.1")!))
    }

    func testMissingArchitectureOrChecksumIsReported() throws {
        let armOnly = try release(tag: "v0.0.2", assets: [
            "QuadrantTodo_0.0.2_arm64.dmg", "QuadrantTodo_0.0.2_arm64.dmg.sha256"
        ])
        XCTAssertEqual(armOnly.lookup(current: AppVersion("0.0.1")!, architecture: "x86_64"), .missingPackage(AppVersion("0.0.2")!))

        let noChecksum = try release(tag: "v0.0.2", assets: ["QuadrantTodo_0.0.2_arm64.dmg"])
        XCTAssertEqual(noChecksum.lookup(current: AppVersion("0.0.1")!, architecture: "arm64"), .missingPackage(AppVersion("0.0.2")!))
    }

    func testAssetNamesMustMatchExactly() throws {
        let info = try release(tag: "v0.0.2", assets: [
            "quadranttodo_0.0.2_arm64.dmg", "quadranttodo_0.0.2_arm64.dmg.sha256",
            "QuadrantTodo_0.0.1_arm64.dmg", "QuadrantTodo_0.0.1_arm64.dmg.sha256"
        ])
        XCTAssertEqual(info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64"), .missingPackage(AppVersion("0.0.2")!))
    }

    func testUnparseableTagYieldsNoLookup() throws {
        let info = try release(tag: "v0.0.2-beta", assets: [
            "QuadrantTodo_0.0.2-beta_arm64.dmg", "QuadrantTodo_0.0.2-beta_arm64.dmg.sha256"
        ])
        XCTAssertNil(info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64"))
    }

    func testNullBodyBecomesEmptyNotes() throws {
        let info = try release(tag: "v0.0.2", body: nil, assets: [
            "QuadrantTodo_0.0.2_arm64.dmg", "QuadrantTodo_0.0.2_arm64.dmg.sha256"
        ])
        guard case .available(_, let notes) = info.lookup(current: AppVersion("0.0.1")!, architecture: "arm64") else {
            return XCTFail("应为 available")
        }
        XCTAssertEqual(notes, "")
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try ReleaseInfo.decode(Data("not json".utf8)))
    }

    func testCurrentArchitectureIsKnown() {
        XCTAssertTrue(["arm64", "x86_64"].contains(CPUArchitecture.current))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path macos --filter 'AppVersionTests|ReleaseInfoTests'`
Expected: 编译失败，`cannot find 'AppVersion' in scope` / `cannot find 'ReleaseInfo' in scope`。

- [ ] **Step 3: Write the implementation**

`macos/Sources/QuadrantTodo/Core/Update/AppVersion.swift`:

```swift
import Foundation

/// 发布版本号：`0.0.1`、`v0.1.0`。按数字逐段比较，缺少的段按 0 计；带后缀的预发布版本不识别。
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    /// 正在运行的应用版本（Info.plist 的 CFBundleShortVersionString）。
    static var current: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs) == rhs.padded(to: lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs).lexicographicallyPrecedes(rhs.padded(to: lhs))
    }

    private func padded(to other: AppVersion) -> [Int] {
        components + Array(repeating: 0, count: max(0, other.components.count - components.count))
    }
}
```

`macos/Sources/QuadrantTodo/Core/Update/ReleaseInfo.swift`:

```swift
import Foundation

struct ReleaseAsset: Decodable, Equatable {
    let name: String
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

/// 一次可安装的更新：本机架构的 DMG 与其 SHA-256 校验文件。
struct UpdatePackage: Equatable {
    let version: AppVersion
    let dmgName: String
    let dmgURL: URL
    let checksumURL: URL
}

enum ReleaseLookup: Equatable {
    case upToDate(AppVersion)
    case available(UpdatePackage, notes: String)
    case missingPackage(AppVersion)
}

/// GitHub `releases/latest` 响应中更新所需的字段。
struct ReleaseInfo: Decodable, Equatable {
    let tagName: String
    let body: String?
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }

    static func decode(_ data: Data) throws -> ReleaseInfo {
        try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    var version: AppVersion? { AppVersion(tagName) }

    /// 资源名与 package-dmg.sh 的产物一致：`QuadrantTodo_<版本>_<arch>.dmg` 及同名 `.sha256`。
    /// tag 无法识别时返回 nil。
    func lookup(current: AppVersion, architecture: String) -> ReleaseLookup? {
        guard let version else { return nil }
        guard current < version else { return .upToDate(version) }
        var versionText = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if versionText.first == "v" || versionText.first == "V" { versionText.removeFirst() }
        let dmgName = "QuadrantTodo_\(versionText)_\(architecture).dmg"
        guard let dmg = assets.first(where: { $0.name == dmgName }),
              let checksum = assets.first(where: { $0.name == dmgName + ".sha256" }) else {
            return .missingPackage(version)
        }
        let package = UpdatePackage(version: version, dmgName: dmgName, dmgURL: dmg.downloadURL, checksumURL: checksum.downloadURL)
        return .available(package, notes: (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum CPUArchitecture {
    /// 与 package-dmg.sh 中 `uname -m` 的取值一致。
    static var current: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path macos --filter 'AppVersionTests|ReleaseInfoTests'`
Expected: PASS，13 项测试全部通过。

- [ ] **Step 5: Record the spec deviations**

在 `docs/superpowers/specs/2026-10-16-in-app-update-design.md` 中：
- 把第 2 节第 3 步的 `hdiutil attach -nobrowse -readonly -noautoopen -mountrandom <临时目录>` 改为 `hdiutil attach -nobrowse -readonly -noautoopen -mountpoint <临时目录>`。
- 把第 2 节第 6 步改为：「app 启动时读取结果文件 `~/Library/Caches/QuadrantTodo/Updates/last-result.json`，以 `NSAlert` 显示「已升级到 x.y.z」或「升级失败，已保留旧版本」及备份位置，随后删除结果文件。（启动时面板收起，短暂的面板 notice 用户看不到，因此使用弹窗。）」
- 第 3 节「现有文件改动」中 `App.swift` 一行的「显示 notice」改为「弹出 NSAlert」。

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/QuadrantTodo/Core/Update/AppVersion.swift macos/Sources/QuadrantTodo/Core/Update/ReleaseInfo.swift \
  macos/Tests/QuadrantTodoTests/AppVersionTests.swift macos/Tests/QuadrantTodoTests/ReleaseInfoTests.swift \
  docs/superpowers/specs/2026-10-16-in-app-update-design.md
git diff --cached --check
git commit -m "feat: compare app versions and pick the matching release package

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 升级预检

**Files:**
- Create: `macos/Sources/QuadrantTodo/Core/Update/UpdatePreflight.swift`
- Test: `macos/Tests/QuadrantTodoTests/UpdatePreflightTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum UpdatePreflightProblem: Equatable { case editing, unsavedDrafts, notInstalled, notWritable(String); var message: String }`
  - `struct UpdatePreflightInput: Equatable { var isEditing: Bool; var hasDrafts: Bool; var appURL: URL; var isOnReadOnlyVolume: Bool; var isParentWritable: Bool }`
  - `enum UpdatePreflight { static func check(_ input: UpdatePreflightInput) -> UpdatePreflightProblem?; static func input(appURL: URL, isEditing: Bool, drafts: [String]) -> UpdatePreflightInput }`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/QuadrantTodoTests/UpdatePreflightTests.swift`:

```swift
import XCTest
@testable import QuadrantTodo

final class UpdatePreflightTests: XCTestCase {
    private func input(
        isEditing: Bool = false,
        hasDrafts: Bool = false,
        path: String = "/Users/me/Applications/QuadrantTodo.app",
        readOnly: Bool = false,
        writable: Bool = true
    ) -> UpdatePreflightInput {
        UpdatePreflightInput(
            isEditing: isEditing,
            hasDrafts: hasDrafts,
            appURL: URL(fileURLWithPath: path),
            isOnReadOnlyVolume: readOnly,
            isParentWritable: writable
        )
    }

    func testInstalledWritableIdleAppPasses() {
        XCTAssertNil(UpdatePreflight.check(input()))
    }

    func testOpenEditorBlocksFirst() {
        XCTAssertEqual(UpdatePreflight.check(input(isEditing: true, hasDrafts: true, writable: false)), .editing)
    }

    func testDraftsBlock() {
        XCTAssertEqual(UpdatePreflight.check(input(hasDrafts: true)), .unsavedDrafts)
    }

    func testRunningFromDiskImageOrTranslocationIsNotInstalled() {
        XCTAssertEqual(UpdatePreflight.check(input(path: "/Volumes/QuadrantTodo/QuadrantTodo.app", readOnly: true)), .notInstalled)
        XCTAssertEqual(
            UpdatePreflight.check(input(path: "/private/var/folders/x/AppTranslocation/ABC/d/QuadrantTodo.app")),
            .notInstalled
        )
    }

    func testBareExecutableIsNotInstalled() {
        XCTAssertEqual(UpdatePreflight.check(input(path: "/repo/macos/.build/debug")), .notInstalled)
    }

    func testUnwritableParentIsReportedWithDirectory() {
        XCTAssertEqual(
            UpdatePreflight.check(input(path: "/Applications/QuadrantTodo.app", writable: false)),
            .notWritable("/Applications")
        )
    }

    func testInputTreatsWhitespaceDraftsAsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("preflight-\(UUID().uuidString)")
        let app = dir.appendingPathComponent("QuadrantTodo.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let blank = UpdatePreflight.input(appURL: app, isEditing: false, drafts: ["", "  \n"])
        XCTAssertFalse(blank.hasDrafts)
        XCTAssertTrue(blank.isParentWritable)
        XCTAssertFalse(blank.isOnReadOnlyVolume)
        XCTAssertTrue(UpdatePreflight.input(appURL: app, isEditing: false, drafts: ["买牛奶"]).hasDrafts)
    }

    func testMessagesAreUserFacing() {
        XCTAssertTrue(UpdatePreflightProblem.notWritable("/Applications").message.contains("/Applications"))
        XCTAssertTrue(UpdatePreflightProblem.notInstalled.message.contains("应用程序"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path macos --filter UpdatePreflightTests`
Expected: 编译失败，`cannot find 'UpdatePreflightInput' in scope`。

- [ ] **Step 3: Write the implementation**

`macos/Sources/QuadrantTodo/Core/Update/UpdatePreflight.swift`:

```swift
import Foundation

/// 开始下载前必须满足的条件；任何一项不满足都不改动应用与数据。
enum UpdatePreflightProblem: Equatable {
    case editing
    case unsavedDrafts
    case notInstalled
    case notWritable(String)

    var message: String {
        switch self {
        case .editing:
            return "请先保存或关闭正在编辑的事项，再升级。"
        case .unsavedDrafts:
            return "请先提交或清空输入框中的草稿，再升级。"
        case .notInstalled:
            return "请先把应用拖到「应用程序」或 ~/Applications，从那里打开后再升级。"
        case .notWritable(let directory):
            return "没有写入权限：\(directory)。不会索要管理员密码，可将应用安装到 ~/Applications 后再升级。"
        }
    }
}

struct UpdatePreflightInput: Equatable {
    var isEditing: Bool
    var hasDrafts: Bool
    var appURL: URL
    var isOnReadOnlyVolume: Bool
    var isParentWritable: Bool
}

enum UpdatePreflight {
    static func check(_ input: UpdatePreflightInput) -> UpdatePreflightProblem? {
        if input.isEditing { return .editing }
        if input.hasDrafts { return .unsavedDrafts }
        if input.appURL.pathExtension != "app"
            || input.appURL.path.contains("/AppTranslocation/")
            || input.isOnReadOnlyVolume {
            return .notInstalled
        }
        if !input.isParentWritable { return .notWritable(input.appURL.deletingLastPathComponent().path) }
        return nil
    }

    /// 从文件系统收集与当前应用位置有关的条件。
    static func input(appURL: URL, isEditing: Bool, drafts: [String]) -> UpdatePreflightInput {
        let values = try? appURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return UpdatePreflightInput(
            isEditing: isEditing,
            hasDrafts: drafts.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            appURL: appURL,
            isOnReadOnlyVolume: values?.volumeIsReadOnly ?? false,
            isParentWritable: FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path macos --filter UpdatePreflightTests`
Expected: PASS，8 项测试全部通过。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/QuadrantTodo/Core/Update/UpdatePreflight.swift macos/Tests/QuadrantTodoTests/UpdatePreflightTests.swift
git diff --cached --check
git commit -m "feat: refuse updates while editing or when the app cannot be replaced

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 下载、校验、暂存、备份与助手脚本

**Files:**
- Create: `macos/Sources/QuadrantTodo/Core/Update/UpdateSupport.swift`
- Create: `macos/Sources/QuadrantTodo/Core/Update/UpdateHelperScript.swift`
- Create: `macos/Sources/QuadrantTodo/Core/Update/UpdateInstaller.swift`
- Test: `macos/Tests/QuadrantTodoTests/UpdateChecksumTests.swift`
- Test: `macos/Tests/QuadrantTodoTests/UpdateInstallerTests.swift`
- Test: `macos/Tests/QuadrantTodoTests/UpdateHelperScriptTests.swift`

**Interfaces:**
- Consumes: `AppVersion`、`ReleaseInfo`（Task 1）；`PersistenceController.storeURL()`（现有，`nonisolated static`）
- Produces:
  - `enum UpdateError: Error, Equatable { case network(String), rateLimited, badResponse, unrecognizedVersion, invalidChecksumFile, checksumMismatch, command(String, String), invalidBundle(String), backupFailed(String), cancelled; var message: String }`
  - `enum UpdatePaths { static let bundleIdentifier: String; static let defaultFeedURL: URL; static var feedURL: URL; static var cacheDirectory: URL; static var downloadsDirectory: URL; static var resultFile: URL; static var backupRoot: URL; static var dataDirectory: URL }`
  - `protocol CommandRunning: Sendable { @discardableResult func run(_ executable: String, _ arguments: [String]) throws -> String }`、`struct ProcessCommandRunner: CommandRunning`
  - `enum UpdateChecksum { static func expectedHash(in text: String, fileName: String) -> String?; static func sha256Hex(of url: URL) throws -> String }`
  - `struct UpdateResult: Codable, Equatable { let status: String; let version: String; let backup: String; var succeeded: Bool; var title: String; var detail: String; static func consume(at url: URL) -> UpdateResult? }`
  - `enum UpdateHelperScript { static let source: String; static func write(to directory: URL) throws -> URL }`
  - `struct StagedApp: Equatable { let appURL: URL; let stagingDirectory: URL }`
  - `struct UpdateInstaller: Sendable { init(runner: CommandRunning = ProcessCommandRunner(), session: URLSession = .shared); func fetchRelease(from url: URL) async throws -> ReleaseInfo; func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws; func verifyChecksum(file: URL, checksumFile: URL, fileName: String) throws; func stage(dmg: URL, nextTo target: URL, expectedVersion: AppVersion) throws -> StagedApp; func backup(dataDirectory: URL, backupRoot: URL, defaultsDomain: String, now: Date = Date()) throws -> URL; func launchHelper(staged: StagedApp, target: URL, backup: URL, version: AppVersion, resultFile: URL = UpdatePaths.resultFile, pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws; static func validateBundle(at app: URL, expectedVersion: AppVersion) throws }`

- [ ] **Step 1: Write the failing checksum and result tests**

`macos/Tests/QuadrantTodoTests/UpdateChecksumTests.swift`:

```swift
import XCTest
@testable import QuadrantTodo

final class UpdateChecksumTests: XCTestCase {
    private let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private let name = "QuadrantTodo_0.0.2_arm64.dmg"

    func testParsesShasumOutputVariants() {
        XCTAssertEqual(UpdateChecksum.expectedHash(in: "\(hash)  \(name)\n", fileName: name), hash)
        XCTAssertEqual(UpdateChecksum.expectedHash(in: "\(hash.uppercased())  \(name)", fileName: name), hash)
        XCTAssertEqual(UpdateChecksum.expectedHash(in: "\(hash) *\(name)", fileName: name), hash)
        XCTAssertEqual(UpdateChecksum.expectedHash(in: "\(hash)\n", fileName: name), hash)
    }

    func testRejectsWrongNameOrMalformedHash() {
        XCTAssertNil(UpdateChecksum.expectedHash(in: "\(hash)  Other.dmg", fileName: name))
        XCTAssertNil(UpdateChecksum.expectedHash(in: "abc123  \(name)", fileName: name))
        XCTAssertNil(UpdateChecksum.expectedHash(in: "", fileName: name))
        XCTAssertNil(UpdateChecksum.expectedHash(in: String(repeating: "z", count: 64), fileName: name))
    }

    func testSHA256OfFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try UpdateChecksum.sha256Hex(of: url), hash)
    }

    func testResultIsConsumedOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("result-\(UUID().uuidString).json")
        try Data(#"{"status":"success","version":"0.0.2","backup":"/tmp/b 中文"}"#.utf8).write(to: url)

        let result = UpdateResult.consume(at: url)
        XCTAssertEqual(result, UpdateResult(status: "success", version: "0.0.2", backup: "/tmp/b 中文"))
        XCTAssertEqual(result?.succeeded, true)
        XCTAssertEqual(result?.title, "已升级到 0.0.2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(UpdateResult.consume(at: url))
    }

    func testCorruptResultIsDiscarded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("result-\(UUID().uuidString).json")
        try Data("garbage".utf8).write(to: url)
        XCTAssertNil(UpdateResult.consume(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFailureResultsExplainThatDataIsUntouched() {
        XCTAssertFalse(UpdateResult(status: "restored", version: "0.0.2", backup: "/b").succeeded)
        XCTAssertTrue(UpdateResult(status: "restored", version: "0.0.2", backup: "/b").detail.contains("/b"))
        XCTAssertEqual(UpdateResult(status: "timeout", version: "0.0.2", backup: "/b").title, "升级未完成")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path macos --filter UpdateChecksumTests`
Expected: 编译失败，`cannot find 'UpdateChecksum' in scope`。

- [ ] **Step 3: Implement `UpdateSupport.swift`**

`macos/Sources/QuadrantTodo/Core/Update/UpdateSupport.swift`:

```swift
import CryptoKit
import Foundation

enum UpdateError: Error, Equatable {
    case network(String)
    case rateLimited
    case badResponse
    case unrecognizedVersion
    case invalidChecksumFile
    case checksumMismatch
    case command(String, String)
    case invalidBundle(String)
    case backupFailed(String)
    case cancelled

    var message: String {
        switch self {
        case .network(let detail): return "无法连接 GitHub：\(detail)"
        case .rateLimited: return "请求过于频繁，请稍后再试。"
        case .badResponse: return "无法解析发布信息。"
        case .unrecognizedVersion: return "无法识别版本号。"
        case .invalidChecksumFile: return "校验文件格式不正确，未进行升级。"
        case .checksumMismatch: return "下载的安装包校验失败，已丢弃，请稍后重试。"
        case .command(let name, let output): return "\(name) 执行失败：\(output)"
        case .invalidBundle(let reason): return "安装包无效：\(reason)"
        case .backupFailed(let reason): return "备份数据失败，未进行升级：\(reason)"
        case .cancelled: return "已取消。"
        }
    }
}

/// 更新流程用到的固定位置。数据目录沿用持久化层的定义，自动遵循 `QT_DATA_DIR`。
enum UpdatePaths {
    static let bundleIdentifier = "com.cutey.quadranttodo"
    static let defaultFeedURL = URL(string: "https://api.github.com/repos/cutey-none/bobo-todolist/releases/latest")!

    /// 开发时可用 `QT_UPDATE_FEED_URL` 指向本地的假 Release（支持 file://）。
    static var feedURL: URL {
        ProcessInfo.processInfo.environment["QT_UPDATE_FEED_URL"].flatMap(URL.init(string:)) ?? defaultFeedURL
    }

    static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("QuadrantTodo/Updates", isDirectory: true)
    }

    static var downloadsDirectory: URL { cacheDirectory.appendingPathComponent("Downloads", isDirectory: true) }
    static var resultFile: URL { cacheDirectory.appendingPathComponent("last-result.json") }

    /// 与 macos/upgrade.sh 相同的备份位置，`QT_BACKUP_DIR` 可覆盖。
    static var backupRoot: URL {
        if let custom = ProcessInfo.processInfo.environment["QT_BACKUP_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("QuadrantTodoBackups", isDirectory: true)
    }

    static var dataDirectory: URL { PersistenceController.storeURL().deletingLastPathComponent() }
}

protocol CommandRunning: Sendable {
    @discardableResult
    func run(_ executable: String, _ arguments: [String]) throws -> String
}

/// 同步执行系统命令；非零退出码抛出带输出的错误。
struct ProcessCommandRunner: CommandRunning {
    @discardableResult
    func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw UpdateError.command(
                URL(fileURLWithPath: executable).lastPathComponent,
                output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }
}

enum UpdateChecksum {
    /// 解析 `shasum -a 256` 的输出：`<hash>  <文件名>`；文件名可省略，存在时必须一致。
    static func expectedHash(in text: String, fileName: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline).first else { return nil }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let hash = fields.first?.lowercased(), hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        if fields.count > 1 {
            var name = String(fields[1])
            if name.hasPrefix("*") { name.removeFirst() }
            guard name == fileName else { return nil }
        }
        return hash
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// 助手脚本写下的升级结果，新版启动时读取一次后删除。
struct UpdateResult: Codable, Equatable {
    let status: String
    let version: String
    let backup: String

    var succeeded: Bool { status == "success" }

    var title: String {
        switch status {
        case "success": return "已升级到 \(version)"
        case "timeout": return "升级未完成"
        default: return "升级失败，已保留旧版本"
        }
    }

    var detail: String {
        switch status {
        case "success": return "待办数据没有被替换。升级前的数据与旧版本备份在：\n\(backup)"
        case "timeout": return "旧版本未能及时退出，应用没有被替换，数据未改动。可以重新检查更新再试。"
        default: return "应用没有被替换，数据未改动。数据备份在：\n\(backup)"
        }
    }

    static func consume(at url: URL) -> UpdateResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return try? JSONDecoder().decode(UpdateResult.self, from: data)
    }
}
```

- [ ] **Step 4: Run checksum tests to verify they pass**

Run: `swift test --package-path macos --filter UpdateChecksumTests`
Expected: PASS，6 项测试全部通过。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/QuadrantTodo/Core/Update/UpdateSupport.swift macos/Tests/QuadrantTodoTests/UpdateChecksumTests.swift
git diff --cached --check
git commit -m "feat: add update paths, errors, checksum parsing and result records

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Write the failing helper script tests**

`macos/Tests/QuadrantTodoTests/UpdateHelperScriptTests.swift`:

```swift
import XCTest
@testable import QuadrantTodo

final class UpdateHelperScriptTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("helper-\(UUID().uuidString)/My Apps 中文")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func makeApp(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent("Contents/marker"))
    }

    private func marker(_ app: URL) -> String? {
        (try? Data(contentsOf: app.appendingPathComponent("Contents/marker"))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func startSleeper(_ seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    /// 运行助手脚本并等待结束，返回退出码。
    private func runHelper(pid: Int32, staged: URL, target: URL, backup: URL, result: URL, wait: String = "5") throws -> Int32 {
        let script = try UpdateHelperScript.write(to: root.deletingLastPathComponent())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, String(pid), staged.path, target.path, backup.path, result.path, "0.0.2"]
        var env = ProcessInfo.processInfo.environment
        env["QT_UPDATE_OPEN_CMD"] = "/usr/bin/true"
        env["QT_UPDATE_WAIT_SECONDS"] = wait
        process.environment = env
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func readResult(_ url: URL) throws -> UpdateResult {
        try JSONDecoder().decode(UpdateResult.self, from: Data(contentsOf: url))
    }

    func testHelperReplacesAppAtPathWithSpaces() throws {
        let target = root.appendingPathComponent("QuadrantTodo.app")
        let staging = root.appendingPathComponent(".quadrant-update.test")
        let staged = staging.appendingPathComponent("QuadrantTodo.app")
        let backup = root.appendingPathComponent("备份 dir")
        let result = root.appendingPathComponent("result.json")
        try makeApp(at: target, marker: "old")
        try makeApp(at: staged, marker: "new")

        let sleeper = try startSleeper("0.3")
        let status = try runHelper(pid: sleeper.processIdentifier, staged: staged, target: target, backup: backup, result: result)

        XCTAssertEqual(status, 0)
        XCTAssertEqual(marker(target), "new")
        XCTAssertEqual(marker(backup.appendingPathComponent("Previous.app")), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try readResult(result), UpdateResult(status: "success", version: "0.0.2", backup: backup.path))
    }

    func testHelperGivesUpWhenOldProcessDoesNotExit() throws {
        let target = root.appendingPathComponent("QuadrantTodo.app")
        let staging = root.appendingPathComponent(".quadrant-update.test")
        let staged = staging.appendingPathComponent("QuadrantTodo.app")
        let backup = root.appendingPathComponent("backup")
        let result = root.appendingPathComponent("result.json")
        try makeApp(at: target, marker: "old")
        try makeApp(at: staged, marker: "new")

        let sleeper = try startSleeper("10")
        defer { sleeper.terminate() }
        let status = try runHelper(pid: sleeper.processIdentifier, staged: staged, target: target, backup: backup, result: result, wait: "1")

        XCTAssertEqual(status, 1)
        XCTAssertEqual(marker(target), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try readResult(result).status, "timeout")
    }

    func testHelperRestoresOldAppWhenPlacementFails() throws {
        let target = root.appendingPathComponent("QuadrantTodo.app")
        let staging = root.appendingPathComponent(".quadrant-update.test")
        let missingStaged = staging.appendingPathComponent("QuadrantTodo.app")
        let backup = root.appendingPathComponent("backup")
        let result = root.appendingPathComponent("result.json")
        try makeApp(at: target, marker: "old")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let sleeper = try startSleeper("0.1")
        let status = try runHelper(pid: sleeper.processIdentifier, staged: missingStaged, target: target, backup: backup, result: result)

        XCTAssertEqual(status, 1)
        XCTAssertEqual(marker(target), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Previous.app").path))
        XCTAssertEqual(try readResult(result).status, "restored")
    }
}
```

- [ ] **Step 7: Run to verify failure**

Run: `swift test --package-path macos --filter UpdateHelperScriptTests`
Expected: 编译失败，`cannot find 'UpdateHelperScript' in scope`。

- [ ] **Step 8: Implement `UpdateHelperScript.swift`**

`macos/Sources/QuadrantTodo/Core/Update/UpdateHelperScript.swift`:

```swift
import Foundation

/// 升级助手：应用退出后由它替换 .app，失败时还原，并写下结果供新版启动时提示。
/// 参数：<旧进程 pid> <暂存 app> <目标 app> <备份目录> <结果文件> <版本>
enum UpdateHelperScript {
    static let source = #"""
    #!/bin/zsh
    # 由四象限待办在升级时启动：等待旧进程退出后替换 .app，失败则还原旧版本。
    set -u
    PID=$1 STAGED=$2 TARGET=$3 BACKUP=$4 RESULT=$5 VERSION=$6
    WAIT_SECONDS=${QT_UPDATE_WAIT_SECONDS:-30}
    OPEN_CMD=${QT_UPDATE_OPEN_CMD:-/usr/bin/open}
    STAGING_DIR=${STAGED:h}

    json_escape() { local s=${1//\\/\\\\}; print -rn -- "${s//\"/\\\"}" }

    finish() {
        mkdir -p -- "${RESULT:h}"
        print -r -- "{\"status\":\"$1\",\"version\":\"$(json_escape "$VERSION")\",\"backup\":\"$(json_escape "$BACKUP")\"}" > "$RESULT.tmp" \
            && mv -f -- "$RESULT.tmp" "$RESULT"
        # 只清理应用自己创建的暂存目录。
        [[ ${STAGING_DIR:t} == .quadrant-update.* ]] && rm -rf -- "$STAGING_DIR"
        # 超时说明旧版本仍在运行，不再重复打开。
        [[ $1 == timeout ]] || "$OPEN_CMD" "$TARGET"
        exit $2
    }

    ticks=0
    while kill -0 "$PID" 2>/dev/null; do
        (( ticks >= WAIT_SECONDS * 10 )) && finish timeout 1
        sleep 0.1
        (( ticks++ ))
    done

    mkdir -p -- "$BACKUP" || finish failed 1
    if [[ -e $TARGET ]]; then
        mv -- "$TARGET" "$BACKUP/Previous.app" || finish failed 1
    fi
    if mv -- "$STAGED" "$TARGET"; then
        finish success 0
    fi
    [[ -e $BACKUP/Previous.app ]] && mv -- "$BACKUP/Previous.app" "$TARGET"
    finish restored 1
    """#

    static func write(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("quadrant-update-helper-\(UUID().uuidString).zsh")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
```

- [ ] **Step 9: Run helper tests to verify they pass**

Run: `swift test --package-path macos --filter UpdateHelperScriptTests`
Expected: PASS，3 项测试全部通过（超时用例约 1 秒）。

- [ ] **Step 10: Commit**

```bash
git add macos/Sources/QuadrantTodo/Core/Update/UpdateHelperScript.swift macos/Tests/QuadrantTodoTests/UpdateHelperScriptTests.swift
git diff --cached --check
git commit -m "feat: replace the app after it quits and restore it on failure

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 11: Write the failing installer tests**

`macos/Tests/QuadrantTodoTests/UpdateInstallerTests.swift`:

```swift
import XCTest
@testable import QuadrantTodo

/// 真实执行 hdiutil / ditto，仅替换 codesign 的结果（测试用的假应用包没有可执行文件，无法真实签名）。
private struct CodesignStubRunner: CommandRunning {
    var codesignFails = false

    func run(_ executable: String, _ arguments: [String]) throws -> String {
        if executable.hasSuffix("/codesign") {
            if codesignFails { throw UpdateError.command("codesign", "invalid signature") }
            return ""
        }
        return try ProcessCommandRunner().run(executable, arguments)
    }
}

final class UpdateInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 生成与 package-dmg.sh 结构相同的 DMG：根目录下一个 QuadrantTodo.app。
    private func makeDMG(version: String, bundleID: String = "com.cutey.quadranttodo") throws -> URL {
        let source = root.appendingPathComponent("image-\(UUID().uuidString)")
        let contents = source.appendingPathComponent("QuadrantTodo.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let dmg = root.appendingPathComponent("QuadrantTodo_\(version)_test.dmg")
        try ProcessCommandRunner().run("/usr/bin/hdiutil", [
            "create", "-volname", "QuadrantTodo", "-srcfolder", source.path, "-format", "UDZO", "-fs", "HFS+", dmg.path
        ])
        return dmg
    }

    private func stagingLeftovers(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".quadrant-update.") }
    }

    func testFetchReleaseReadsFileFeed() async throws {
        let feed = root.appendingPathComponent("latest.json")
        try Data(#"{"tag_name":"v0.0.2","body":"","assets":[]}"#.utf8).write(to: feed)
        let info = try await UpdateInstaller().fetchRelease(from: feed)
        XCTAssertEqual(info.tagName, "v0.0.2")
    }

    func testFetchReleaseRejectsGarbage() async throws {
        let feed = root.appendingPathComponent("latest.json")
        try Data("<html>".utf8).write(to: feed)
        do {
            _ = try await UpdateInstaller().fetchRelease(from: feed)
            XCTFail("应抛出错误")
        } catch {
            XCTAssertEqual(error as? UpdateError, .badResponse)
        }
    }

    func testDownloadCopiesFileURLAndReportsCompletion() async throws {
        let source = root.appendingPathComponent("src.bin")
        try Data("payload".utf8).write(to: source)
        let destination = root.appendingPathComponent("Downloads/out.bin")
        let reported = LockedBox<Double>(0)

        try await UpdateInstaller().download(source, to: destination) { reported.value = $0 }

        XCTAssertEqual(try Data(contentsOf: destination), Data("payload".utf8))
        XCTAssertEqual(reported.value, 1)
    }

    func testVerifyChecksumAcceptsMatchAndRejectsMismatch() throws {
        let file = root.appendingPathComponent("a.dmg")
        try Data("abc".utf8).write(to: file)
        let good = root.appendingPathComponent("good.sha256")
        try Data("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  a.dmg\n".utf8).write(to: good)
        let bad = root.appendingPathComponent("bad.sha256")
        try Data("\(String(repeating: "0", count: 64))  a.dmg\n".utf8).write(to: bad)
        let installer = UpdateInstaller()

        XCTAssertNoThrow(try installer.verifyChecksum(file: file, checksumFile: good, fileName: "a.dmg"))
        XCTAssertThrowsError(try installer.verifyChecksum(file: file, checksumFile: bad, fileName: "a.dmg")) {
            XCTAssertEqual($0 as? UpdateError, .checksumMismatch)
        }
    }

    func testStageCopiesAppNextToTarget() throws {
        let dmg = try makeDMG(version: "0.0.2")
        let apps = root.appendingPathComponent("Apps")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let target = apps.appendingPathComponent("QuadrantTodo.app")

        let staged = try UpdateInstaller(runner: CodesignStubRunner())
            .stage(dmg: dmg, nextTo: target, expectedVersion: AppVersion("0.0.2")!)

        XCTAssertEqual(staged.stagingDirectory.deletingLastPathComponent().standardizedFileURL, apps.standardizedFileURL)
        XCTAssertTrue(staged.stagingDirectory.lastPathComponent.hasPrefix(".quadrant-update."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.appURL.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "暂存不应触碰目标应用")
    }

    func testStageRejectsVersionMismatchAndCleansUp() throws {
        let dmg = try makeDMG(version: "0.0.3")
        let target = root.appendingPathComponent("QuadrantTodo.app")

        XCTAssertThrowsError(
            try UpdateInstaller(runner: CodesignStubRunner()).stage(dmg: dmg, nextTo: target, expectedVersion: AppVersion("0.0.2")!)
        ) { error in
            guard case .invalidBundle = error as? UpdateError else { return XCTFail("应为 invalidBundle：\(error)") }
        }
        XCTAssertEqual(try stagingLeftovers(in: root), [])
    }

    func testStageRejectsForeignBundleIdentifier() throws {
        let dmg = try makeDMG(version: "0.0.2", bundleID: "com.example.other")
        let target = root.appendingPathComponent("QuadrantTodo.app")

        XCTAssertThrowsError(
            try UpdateInstaller(runner: CodesignStubRunner()).stage(dmg: dmg, nextTo: target, expectedVersion: AppVersion("0.0.2")!)
        )
        XCTAssertEqual(try stagingLeftovers(in: root), [])
    }

    func testStageRejectsInvalidSignatureAndCleansUp() throws {
        let dmg = try makeDMG(version: "0.0.2")
        let target = root.appendingPathComponent("QuadrantTodo.app")

        XCTAssertThrowsError(
            try UpdateInstaller(runner: CodesignStubRunner(codesignFails: true))
                .stage(dmg: dmg, nextTo: target, expectedVersion: AppVersion("0.0.2")!)
        )
        XCTAssertEqual(try stagingLeftovers(in: root), [])
    }

    func testBackupCopiesDataDirectoryWithSpacesAndChinese() throws {
        let data = root.appendingPathComponent("数据 目录")
        try FileManager.default.createDirectory(at: data.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try Data("store".utf8).write(to: data.appendingPathComponent("Tasks.store"))
        try Data("png".utf8).write(to: data.appendingPathComponent("Attachments/a.png"))
        let backupRoot = root.appendingPathComponent("Backups")

        let backup = try UpdateInstaller().backup(
            dataDirectory: data, backupRoot: backupRoot, defaultsDomain: "com.cutey.quadranttodo.tests.absent"
        )

        XCTAssertTrue(backup.lastPathComponent.hasPrefix("update-"))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Data/Tasks.store")), Data("store".utf8))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Data/Attachments/a.png")), Data("png".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Settings.plist").path))
        XCTAssertEqual(try Data(contentsOf: data.appendingPathComponent("Tasks.store")), Data("store".utf8), "原数据不变")
    }

    func testBackupWithoutDataDirectoryStillCreatesFolder() throws {
        let backup = try UpdateInstaller().backup(
            dataDirectory: root.appendingPathComponent("missing"),
            backupRoot: root.appendingPathComponent("Backups"),
            defaultsDomain: "com.cutey.quadranttodo.tests.absent"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Data").path))
    }
}

/// 供 @Sendable 进度回调写入的线程安全盒子。
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
```

- [ ] **Step 12: Run to verify failure**

Run: `swift test --package-path macos --filter UpdateInstallerTests`
Expected: 编译失败，`cannot find 'UpdateInstaller' in scope`。

- [ ] **Step 13: Implement `UpdateInstaller.swift`**

`macos/Sources/QuadrantTodo/Core/Update/UpdateInstaller.swift`:

```swift
import Darwin
import Foundation

/// 已复制到目标应用同目录下、通过校验、等待替换的新版应用。
struct StagedApp: Equatable {
    let appURL: URL
    let stagingDirectory: URL
}

/// 更新流程中有副作用的各步。替换之前的任何步骤都不触碰现有应用和数据目录。
struct UpdateInstaller: Sendable {
    var runner: CommandRunning = ProcessCommandRunner()
    var session: URLSession = .shared

    init(runner: CommandRunning = ProcessCommandRunner(), session: URLSession = .shared) {
        self.runner = runner
        self.session = session
    }

    func fetchRelease(from url: URL) async throws -> ReleaseInfo {
        let data: Data
        if url.isFileURL {
            do { data = try Data(contentsOf: url) } catch { throw UpdateError.network(error.localizedDescription) }
        } else {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let body: Data
            let response: URLResponse
            do {
                (body, response) = try await session.data(for: request)
            } catch {
                throw UpdateError.network(error.localizedDescription)
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 403 || http.statusCode == 429 { throw UpdateError.rateLimited }
                guard (200..<300).contains(http.statusCode) else { throw UpdateError.network("HTTP \(http.statusCode)") }
            }
            data = body
        }
        do { return try ReleaseInfo.decode(data) } catch { throw UpdateError.badResponse }
    }

    /// 下载到指定位置，按已接收字节报告 0...1 的进度；取消时抛出 `.cancelled` 并删除半成品。
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)

        if url.isFileURL {
            try fm.copyItem(at: url, to: destination)
            progress(1)
            return
        }

        do {
            let (bytes, response) = try await session.bytes(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw UpdateError.network("HTTP \(http.statusCode)")
            }
            fm.createFile(atPath: destination.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            let expected = response.expectedContentLength
            var buffer = Data()
            buffer.reserveCapacity(1 << 16)
            var received: Int64 = 0
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 16 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expected > 0 { progress(min(1, Double(received) / Double(expected))) }
                }
            }
            try handle.write(contentsOf: buffer)
            progress(1)
        } catch {
            try? fm.removeItem(at: destination)
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw UpdateError.cancelled }
            if let updateError = error as? UpdateError { throw updateError }
            throw UpdateError.network(error.localizedDescription)
        }
    }

    func verifyChecksum(file: URL, checksumFile: URL, fileName: String) throws {
        guard let text = try? String(contentsOf: checksumFile, encoding: .utf8),
              let expected = UpdateChecksum.expectedHash(in: text, fileName: fileName) else {
            throw UpdateError.invalidChecksumFile
        }
        guard try UpdateChecksum.sha256Hex(of: file) == expected else { throw UpdateError.checksumMismatch }
    }

    /// 挂载 DMG，把其中的应用复制到目标应用同目录下的隐藏暂存目录（同卷，保证替换时 mv 原子），并验证签名与版本。
    func stage(dmg: URL, nextTo target: URL, expectedVersion: AppVersion) throws -> StagedApp {
        let fm = FileManager.default
        let mountPoint = fm.temporaryDirectory.appendingPathComponent("quadrant-update-mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        // rmdir 只删除空目录，卸载失败时不会误删镜像内容。
        defer { rmdir(mountPoint.path) }
        try runner.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path, dmg.path])
        defer { _ = try? runner.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let source = mountPoint.appendingPathComponent("QuadrantTodo.app")
        guard fm.fileExists(atPath: source.path) else { throw UpdateError.invalidBundle("安装包内没有 QuadrantTodo.app") }

        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".quadrant-update.\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        let staged = staging.appendingPathComponent("QuadrantTodo.app")
        do {
            try runner.run("/usr/bin/ditto", [source.path, staged.path])
            try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
            try Self.validateBundle(at: staged, expectedVersion: expectedVersion)
            // 只对已通过校验和与签名验证的暂存应用移除隔离属性，避免替换后被 Gatekeeper 拦截。
            if (try? runner.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", staged.path])) != nil {
                try runner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        return StagedApp(appURL: staged, stagingDirectory: staging)
    }

    static func validateBundle(at app: URL, expectedVersion: AppVersion) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            throw UpdateError.invalidBundle("无法读取安装包信息")
        }
        guard plist["CFBundleIdentifier"] as? String == UpdatePaths.bundleIdentifier else {
            throw UpdateError.invalidBundle("应用标识不匹配")
        }
        guard let version = (plist["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              version == expectedVersion else {
            throw UpdateError.invalidBundle("安装包版本与发布版本不一致")
        }
    }

    /// 与 upgrade.sh 相同的布局：`update-<时间>/Data` 与 `Settings.plist`。只读取，不改动原数据。
    func backup(dataDirectory: URL, backupRoot: URL, defaultsDomain: String, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = backupRoot.appendingPathComponent(
            "update-\(formatter.string(from: now))-\(UUID().uuidString.prefix(6))", isDirectory: true
        )
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dataDirectory.path) {
                try runner.run("/usr/bin/ditto", [dataDirectory.path, directory.appendingPathComponent("Data").path])
            }
            if (try? runner.run("/usr/bin/defaults", ["read", defaultsDomain])) != nil {
                try runner.run("/usr/bin/defaults", ["export", defaultsDomain, directory.appendingPathComponent("Settings.plist").path])
            }
        } catch {
            throw UpdateError.backupFailed((error as? UpdateError)?.message ?? error.localizedDescription)
        }
        return directory
    }

    /// 启动独立运行的助手脚本；调用方随后退出应用，由助手完成替换并重新打开。
    func launchHelper(
        staged: StagedApp,
        target: URL,
        backup: URL,
        version: AppVersion,
        resultFile: URL = UpdatePaths.resultFile,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        let script = try UpdateHelperScript.write(to: FileManager.default.temporaryDirectory)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            script.path, String(pid), staged.appURL.path, target.path, backup.path, resultFile.path, version.description
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
```

- [ ] **Step 14: Run installer tests to verify they pass**

Run: `swift test --package-path macos --filter UpdateInstallerTests`
Expected: PASS，11 项测试全部通过（DMG 用例每个约 1–3 秒）。若 `hdiutil create` 报 `Resource busy`，重跑一次确认不是偶发；仍失败则检查是否有遗留挂载 `hdiutil info`。

- [ ] **Step 15: Run the full test suite**

Run: `swift test --package-path macos`
Expected: 全部通过（原有 40 项 + 本任务新增）。

- [ ] **Step 16: Commit**

```bash
git add macos/Sources/QuadrantTodo/Core/Update/UpdateInstaller.swift macos/Tests/QuadrantTodoTests/UpdateInstallerTests.swift
git diff --cached --check
git commit -m "feat: download, verify, stage and back up before replacing the app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 更新控制器与设置页「关于与更新」区

**Files:**
- Create: `macos/Sources/QuadrantTodo/Core/Update/UpdateController.swift`
- Create: `macos/Sources/QuadrantTodo/Views/UpdateStatusView.swift`
- Modify: `macos/Sources/QuadrantTodo/Views/SettingsView.swift`（加 `updater` 属性、新 section、窗口高度 560 → 700）
- Modify: `macos/Sources/QuadrantTodo/App.swift:12`（`SettingsView` 构造参数）
- Test: `macos/Tests/QuadrantTodoTests/UpdateControllerTests.swift`

**Interfaces:**
- Consumes: Task 1–3 的全部类型；`AppState.editing: TaskItem?`、`AppState.drafts: [Quadrant: String]`（现有）
- Produces:
  - `@MainActor final class UpdateController: ObservableObject { enum Phase: Equatable { case idle, checking, upToDate, available(version: String, notes: String), unavailableForArch(version: String), downloading(Double), preparing, relaunching, failed(String) }; static let shared: UpdateController; @Published private(set) var phase: Phase; weak var appState: AppState?; let currentVersion: AppVersion?; var isBusy: Bool; init(installer:feedURL:currentVersion:architecture:appURL:); func check(); func install(); func cancel(); func waitForCurrentTask() async }`
  - `struct UpdateStatusView: View { @ObservedObject var updater: UpdateController }`
  - `SettingsView(settings:updater:onRevealData:)`

- [ ] **Step 1: Write the failing controller tests**

`macos/Tests/QuadrantTodoTests/UpdateControllerTests.swift`:

```swift
import XCTest
@testable import QuadrantTodo

@MainActor
final class UpdateControllerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("controller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func controller(feed json: String?, current: String? = "0.0.1", arch: String = "arm64") throws -> UpdateController {
        let feed = root.appendingPathComponent("latest.json")
        if let json { try Data(json.utf8).write(to: feed) }
        return UpdateController(
            installer: UpdateInstaller(),
            feedURL: feed,
            currentVersion: current.flatMap(AppVersion.init),
            architecture: arch,
            appURL: root.appendingPathComponent("QuadrantTodo.app")
        )
    }

    private let release002 = #"""
    {"tag_name":"v0.0.2","body":"新增应用内更新","assets":[
      {"name":"QuadrantTodo_0.0.2_arm64.dmg","browser_download_url":"https://example.com/a.dmg"},
      {"name":"QuadrantTodo_0.0.2_arm64.dmg.sha256","browser_download_url":"https://example.com/a.dmg.sha256"}]}
    """#

    func testNewerReleaseBecomesAvailable() async throws {
        let updater = try controller(feed: release002)
        updater.check()
        XCTAssertEqual(updater.phase, .checking)
        await updater.waitForCurrentTask()
        XCTAssertEqual(updater.phase, .available(version: "0.0.2", notes: "新增应用内更新"))
    }

    func testSameVersionIsUpToDate() async throws {
        let updater = try controller(feed: release002, current: "0.0.2")
        updater.check()
        await updater.waitForCurrentTask()
        XCTAssertEqual(updater.phase, .upToDate)
    }

    func testMissingArchitectureIsReported() async throws {
        let updater = try controller(feed: release002, arch: "x86_64")
        updater.check()
        await updater.waitForCurrentTask()
        XCTAssertEqual(updater.phase, .unavailableForArch(version: "0.0.2"))
    }

    func testUnrecognizedTagFails() async throws {
        let updater = try controller(feed: #"{"tag_name":"nightly","body":null,"assets":[]}"#)
        updater.check()
        await updater.waitForCurrentTask()
        XCTAssertEqual(updater.phase, .failed(UpdateError.unrecognizedVersion.message))
    }

    func testUnreadableFeedFails() async throws {
        let updater = try controller(feed: nil)
        updater.check()
        await updater.waitForCurrentTask()
        guard case .failed = updater.phase else { return XCTFail("应为 failed：\(updater.phase)") }
    }

    func testUnknownCurrentVersionFailsWithoutNetwork() throws {
        let updater = try controller(feed: release002, current: nil)
        updater.check()
        XCTAssertEqual(updater.phase, .failed(UpdateError.unrecognizedVersion.message))
    }

    func testInstallWithoutAvailableReleaseDoesNothing() throws {
        let updater = try controller(feed: release002)
        updater.install()
        XCTAssertEqual(updater.phase, .idle)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path macos --filter UpdateControllerTests`
Expected: 编译失败，`cannot find 'UpdateController' in scope`。

- [ ] **Step 3: Implement `UpdateController.swift`**

`macos/Sources/QuadrantTodo/Core/Update/UpdateController.swift`:

```swift
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
```

- [ ] **Step 4: Run controller tests to verify they pass**

Run: `swift test --package-path macos --filter UpdateControllerTests`
Expected: PASS，7 项测试全部通过。

- [ ] **Step 5: Implement `UpdateStatusView.swift`**

`macos/Sources/QuadrantTodo/Views/UpdateStatusView.swift`:

```swift
import SwiftUI

/// 设置页「关于与更新」区中随更新状态变化的部分。
struct UpdateStatusView: View {
    @ObservedObject var updater: UpdateController
    @State private var showsAllNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch updater.phase {
            case .idle:
                checkButton
            case .checking:
                busy("正在检查更新…")
            case .upToDate:
                HStack {
                    caption("已是最新版本")
                    Spacer(minLength: 8)
                    checkButton
                }
            case .unavailableForArch(let version):
                caption("新版本 \(version) 暂无适用于本机芯片的安装包。")
                checkButton
            case .available(let version, let notes):
                HStack {
                    Text("发现新版本 \(version)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 8)
                    Button("升级到 \(version)") { updater.install() }
                        .controlSize(.small)
                        .font(.system(size: 11))
                }
                if !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(showsAllNotes ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Button(showsAllNotes ? "收起说明" : "展开说明") { showsAllNotes.toggle() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
                caption("升级会退出并重新打开应用。待办数据不会被替换，并会先自动备份。")
            case .downloading(let progress):
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .controlSize(.small)
                    Button("取消") { updater.cancel() }
                        .controlSize(.small)
                        .font(.system(size: 11))
                }
                caption("正在下载 \(Int(progress * 100))%")
            case .preparing:
                busy("正在校验安装包并备份数据…")
            case .relaunching:
                busy("即将重新打开应用…")
            case .failed(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                checkButton
            }
        }
    }

    private var checkButton: some View {
        Button("检查更新") { updater.check() }
            .controlSize(.small)
            .font(.system(size: 11))
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            caption(text)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
```

- [ ] **Step 6: Add the section to `SettingsView`**

在 `macos/Sources/QuadrantTodo/Views/SettingsView.swift`：

1. 属性改为：

```swift
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updater: UpdateController
    let onRevealData: () -> Void
```

2. 在 `section("数据") { … }` 之后、`Spacer(minLength: 0)` 之前插入：

```swift
            section("关于与更新") {
                row("当前版本") {
                    Text(updater.currentVersion?.description ?? "未知")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
                UpdateStatusView(updater: updater)
            }
```

3. 把 `.frame(width: 380, height: 560, alignment: .topLeading)` 改为 `.frame(width: 380, height: 700, alignment: .topLeading)`。

在 `macos/Sources/QuadrantTodo/App.swift` 第 12 行，改为：

```swift
            SettingsView(settings: SettingsStore.shared, updater: UpdateController.shared) {
```

- [ ] **Step 7: Build and run the full suite**

Run: `swift build --package-path macos && swift test --package-path macos`
Expected: 编译成功；全部测试通过。

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/QuadrantTodo/Core/Update/UpdateController.swift macos/Sources/QuadrantTodo/Views/UpdateStatusView.swift \
  macos/Sources/QuadrantTodo/Views/SettingsView.swift macos/Sources/QuadrantTodo/App.swift \
  macos/Tests/QuadrantTodoTests/UpdateControllerTests.swift
git diff --cached --check
git commit -m "feat: check for and install updates from the settings window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 菜单入口与升级结果提示

**Files:**
- Modify: `macos/Sources/QuadrantTodo/Core/StatusItemController.swift`
- Modify: `macos/Sources/QuadrantTodo/App.swift`

**Interfaces:**
- Consumes: `UpdateController.shared`、`.appState`、`.check()`（Task 4）；`UpdateResult.consume(at:)`、`UpdatePaths.resultFile`（Task 3）
- Produces: `StatusItemController.init(state:settings:controller:openSettings:checkForUpdates:)`

- [ ] **Step 1: Add the menu item**

在 `StatusItemController.swift`：

1. 新增属性 `private let checkForUpdates: () -> Void`，`init` 签名改为
   `init(state: AppState, settings: SettingsStore, controller: PanelController, openSettings: @escaping () -> Void, checkForUpdates: @escaping () -> Void)`，并在 `self.openSettings = openSettings` 之后加 `self.checkForUpdates = checkForUpdates`。
2. `showMenu()` 中把

```swift
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
```

改为

```swift
        menu.addItem(.separator())
        menu.addItem(withTitle: "检查更新…", action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
```

3. 在 `@objc private func showSettings()` 下方加：

```swift
    @objc private func checkUpdates() { checkForUpdates() }
```

4. 文件顶部注释改为 `/// 菜单栏入口：展开 / 收起、钉住、检查更新、设置与退出（PRD 4.3 / 4.4）。`

- [ ] **Step 2: Wire it in `App.swift` and present the result**

在 `applicationDidFinishLaunching` 中：

1. `StatusItemController(` 调用改为：

```swift
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
```

2. 在 `#if DEBUG` 之前加：

```swift
        // 助手脚本替换完成后会重新打开应用，这里告知升级结果。
        DispatchQueue.main.async { AppDelegate.presentUpdateResultIfNeeded() }
```

3. 在 `static func openSettingsWindow()` 之后加：

```swift
    static func presentUpdateResultIfNeeded() {
        guard let result = UpdateResult.consume(at: UpdatePaths.resultFile) else { return }
        let alert = NSAlert()
        alert.alertStyle = result.succeeded ? .informational : .warning
        alert.messageText = result.title
        alert.informativeText = result.detail
        NSApp.activate()
        alert.runModal()
    }
```

- [ ] **Step 3: Build and run the full suite**

Run: `swift build --package-path macos && swift test --package-path macos`
Expected: 编译成功；全部测试通过。

- [ ] **Step 4: Manual smoke check of the result alert**

```bash
mkdir -p ~/Library/Caches/QuadrantTodo/Updates
printf '%s' '{"status":"success","version":"0.0.2","backup":"/tmp/示例 备份"}' > ~/Library/Caches/QuadrantTodo/Updates/last-result.json
./macos/build.sh debug
QT_DATA_DIR="$(mktemp -d)" ./macos/build/QuadrantTodo.app/Contents/MacOS/QuadrantTodo &
```

Expected: 启动后弹出「已升级到 0.0.2」，说明中含 `/tmp/示例 备份`；点「好」后 `last-result.json` 已被删除（`ls ~/Library/Caches/QuadrantTodo/Updates/`）。确认后从菜单栏退出该实例。右键菜单栏图标确认「检查更新…」位于「设置…」上方，点击后设置窗口打开并进入「正在检查更新…」。

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/QuadrantTodo/Core/StatusItemController.swift macos/Sources/QuadrantTodo/App.swift
git diff --cached --check
git commit -m "feat: add a menu bar update entry and report the result after relaunch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 文档

**Files:**
- Modify: `macos/README.md`
- Modify: `docs/prd/quadrant-todo-ui-prd.md`

- [ ] **Step 1: Update `macos/README.md`**

1. 第 3 行 `贴边悬浮的四象限待办工具，SwiftUI + SwiftData 实现，无网络、无账号、数据只存本机。` 改为：
   `贴边悬浮的四象限待办工具，SwiftUI + SwiftData 实现，无账号、数据只存本机；仅在手动「检查更新」时访问 GitHub。`
2. 在 `### 用 DMG 更新或卸载` 小节**之前**插入新小节：

```markdown
### 在应用内更新

菜单栏图标右键 →「检查更新…」，或在设置窗口的「关于与更新」区点「检查更新」。应用只在这时访问 GitHub Releases，平时不联网。

发现新版本后点「升级到 x.y.z」，应用会依次：

1. 检查没有正在编辑的事项和未提交的输入草稿；应用须位于「应用程序」或 `~/Applications` 等可写目录（不会索要管理员密码）。
2. 下载本机架构的 DMG，并用发布附带的 `.sha256` 校验；挂载后复制到同目录下的隐藏暂存位置，验证签名、应用标识和版本号。
3. 把整个数据目录和设置备份到 `~/Library/Application Support/QuadrantTodoBackups/update-<时间>/`。
4. 退出应用，由助手脚本替换 `.app` 并重新打开；旧版本保留为备份目录中的 `Previous.app`。替换失败时自动还原旧版本。

重新打开后会弹窗告知结果。整个过程只替换应用包，不写入 `~/Library/Application Support/QuadrantTodo/` 和设置。下载或校验失败时，现有应用与数据都不会改动。如需手动回滚，退出应用后把备份目录里的 `Previous.app` 拖回原位置即可。

开发验证可用 `QT_UPDATE_FEED_URL` 指向本地的 `releases/latest` 格式 JSON（支持 `file://`）。
```

3. 在 `### 打包 DMG` 小节末尾（`发布时一并提供 DMG 与 .sha256 文件。…` 这一段之后）追加：

```markdown
**应用内更新依赖的发版约定**：Release 的 tag 必须是 `v<版本>`，并与 `Resources/Info.plist` 的 `CFBundleShortVersionString` 一致（例如 `v0.0.2` 对应 `0.0.2`）；附件保持脚本生成的原名 `QuadrantTodo_<版本>_<arch>.dmg` 与 `.dmg.sha256`，不要改名；该 Release 必须是最新的正式版（预发布不会被 `releases/latest` 返回）。缺少某个架构的附件时，该架构的用户会看到「暂无适用于本机芯片的安装包」。
```

4. 在 `## 结构` 的代码块中 `Core/` 下方加一行：
   `      Update/                  应用内更新：版本比较、Release 解析、下载校验、备份与替换助手`

- [ ] **Step 2: Update the PRD**

在 `docs/prd/quadrant-todo-ui-prd.md` 末尾追加：

```markdown
## 14. 应用内更新（2026-10-16，用户确认）

- **入口**：设置窗口新增「关于与更新」区（当前版本、检查更新）；菜单栏右键菜单在「设置…」上方新增「检查更新…」，点击后打开设置窗口并立即检查。主面板不增加入口。
- **只在手动点击时联网**：不在启动时或后台自动检查。
- **状态**：检查中 → 已是最新 / 发现新版本（显示版本号与 Release 说明，默认 3 行，可展开）/ 暂无适用于本机芯片的安装包 / 失败（红字原因，可重新检查）。
- **升级**：点「升级到 x.y.z」后显示下载进度（可取消）→「正在校验安装包并备份数据…」→「即将重新打开应用…」，随后应用退出并自动重新打开，弹窗告知「已升级到 x.y.z」或「升级失败，已保留旧版本」及备份位置。
- **阻止升级的情况**：编辑浮层打开、任一象限输入行有草稿、应用不在可写的安装目录（如直接从 DMG 运行）。均以红字说明原因，不做任何改动。
- **数据**：只替换应用包，不写入待办数据目录与设置；替换前自动备份。
```

- [ ] **Step 3: Commit**

```bash
git add macos/README.md docs/prd/quadrant-todo-ui-prd.md
git diff --cached --check
git commit -m "docs: explain in-app updates and the release naming they rely on

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 端到端运行验证与截图

**Files:**
- Create: `docs/verify/83-update-up-to-date.png`、`84-update-available.png`、`85-update-downloading.png`、`86-update-checksum-failed.png`、`87-update-relaunched.png`
- Modify: `docs/verify/README.md`

所有临时文件放在会话 scratchpad（下文记为 `$S`），不要写进仓库。

- [ ] **Step 1: Build the "new" 0.0.2 package**

```bash
S=<scratchpad 目录>
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.2' macos/Resources/Info.plist
./macos/package-dmg.sh
mkdir -p "$S/feed"
cp macos/build/QuadrantTodo_0.0.2_arm64.dmg macos/build/QuadrantTodo_0.0.2_arm64.dmg.sha256 "$S/feed/"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.1' macos/Resources/Info.plist
git diff --exit-code macos/Resources/Info.plist
```

Expected: 最后一条无输出（Info.plist 已恢复为 0.0.1）。

- [ ] **Step 2: Write the fake feeds**

```bash
cat > "$S/feed/latest.json" <<EOF
{"tag_name":"v0.0.2","body":"新增应用内更新。\n- 设置页可检查更新\n- 一键升级并保留数据","assets":[
 {"name":"QuadrantTodo_0.0.2_arm64.dmg","browser_download_url":"file://$S/feed/QuadrantTodo_0.0.2_arm64.dmg"},
 {"name":"QuadrantTodo_0.0.2_arm64.dmg.sha256","browser_download_url":"file://$S/feed/QuadrantTodo_0.0.2_arm64.dmg.sha256"}]}
EOF
printf '%s\n' '{"tag_name":"v0.0.1","body":"","assets":[]}' > "$S/feed/same.json"
printf '%064d  QuadrantTodo_0.0.2_arm64.dmg\n' 0 > "$S/feed/bad.sha256"
sed "s#QuadrantTodo_0.0.2_arm64.dmg.sha256\"}#bad.sha256\"}#" "$S/feed/latest.json" > "$S/feed/bad.json"
```

`$S` 若含空格，`file://` URL 需要百分号编码；scratchpad 路径不含空格时可直接使用。

- [ ] **Step 3: Install 0.0.1 and prepare isolated data**

```bash
./macos/build.sh
mkdir -p "$S/Apps" "$S/data" "$S/backups"
ditto macos/build/QuadrantTodo.app "$S/Apps/QuadrantTodo.app"
QT_DATA_DIR="$S/data" QT_START_EXPANDED=1 "$S/Apps/QuadrantTodo.app/Contents/MacOS/QuadrantTodo" &
```

在面板中添加 2 条事项，给其中一条写描述并粘贴一张图片后保存；从菜单栏退出。然后记录数据哈希：

```bash
(cd "$S/data" && find . -type f ! -name '*-shm' -print0 | sort -z | xargs -0 shasum -a 256) > "$S/before.txt"
```

- [ ] **Step 4: Capture the up-to-date and checksum-failure states**

用一个辅助脚本按窗口截图（`$S/shot.swift`）：

```swift
import CoreGraphics
import Foundation
// 用法：swift shot.swift <输出路径>；截取 QuadrantTodo 进程最前面的标准窗口（设置窗口）。
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
guard let window = windows.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "QuadrantTodo" && ($0[kCGWindowLayer as String] as? Int) == 0 }),
      let id = window[kCGWindowNumber as String] as? Int else { fatalError("找不到设置窗口") }
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
task.arguments = ["-o", "-l", String(id), CommandLine.arguments[1]]
try task.run(); task.waitUntilExit()
```

依次：

1. `QT_DATA_DIR="$S/data" QT_BACKUP_DIR="$S/backups" QT_UPDATE_FEED_URL="file://$S/feed/same.json" "$S/Apps/QuadrantTodo.app/Contents/MacOS/QuadrantTodo" &` → 菜单栏右键「检查更新…」→ 出现「已是最新版本」→ `swift "$S/shot.swift" docs/verify/83-update-up-to-date.png` → 退出。
2. 同样启动，但 `QT_UPDATE_FEED_URL="file://$S/feed/bad.json"` → 「检查更新」→「升级到 0.0.2」→ 出现红字「下载的安装包校验失败…」→ 截图 `86-update-checksum-failed.png`。确认 `ls -a "$S/Apps"` 只有 `QuadrantTodo.app`（无 `.quadrant-update.*`），`ls "$S/backups"` 为空 → 退出。

Expected: 两张截图分别显示对应状态；失败后应用目录与备份目录无残留。

- [ ] **Step 5: Capture available + downloading, then upgrade**

```bash
QT_DATA_DIR="$S/data" QT_BACKUP_DIR="$S/backups" QT_UPDATE_FEED_URL="file://$S/feed/latest.json" \
  "$S/Apps/QuadrantTodo.app/Contents/MacOS/QuadrantTodo" &
```

1. 打开设置 →「检查更新」→ 出现「发现新版本 0.0.2」及说明 → 截图 `84-update-available.png`。
2. `file://` 下载瞬间完成，截不到进度。为截图 `85-update-downloading.png`，用限速的本地 HTTP 服务器提供 DMG，并生成指向它的 `slow.json`：

```bash
cat > "$S/slow_server.py" <<'EOF'
import http.server, sys, time, os
class Slow(http.server.SimpleHTTPRequestHandler):
    def copyfile(self, src, dst):
        while chunk := src.read(64 * 1024):
            dst.write(chunk); dst.flush(); time.sleep(0.05)
os.chdir(sys.argv[1])
http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Slow).serve_forever()
EOF
python3 -I "$S/slow_server.py" "$S/feed" &
sed "s#file://$S/feed/QuadrantTodo_0.0.2_arm64.dmg\"#http://127.0.0.1:8765/QuadrantTodo_0.0.2_arm64.dmg\"#" "$S/feed/latest.json" > "$S/feed/slow.json"
```

   以 `QT_UPDATE_FEED_URL="file://$S/feed/slow.json"` 重新启动，检查后点「升级到 0.0.2」，进度条推进时截图 `85-update-downloading.png`；点「取消」确认回到「发现新版本 0.0.2」。
3. 助手用 `open` 重新打开新版，新实例不会继承终端里的 `QT_*` 变量，会读写用户的真实数据目录。**必须**先执行：

```bash
launchctl setenv QT_DATA_DIR "$S/data"
launchctl setenv QT_BACKUP_DIR "$S/backups"
```

   然后再次点「升级到 0.0.2」并让它完成。Expected：应用退出后自动重新打开，弹窗「已升级到 0.0.2」；截图 `87-update-relaunched.png`，从菜单栏退出，并立即执行：

```bash
launchctl unsetenv QT_DATA_DIR
launchctl unsetenv QT_BACKUP_DIR
```

- [ ] **Step 6: Verify the outcome**

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$S/Apps/QuadrantTodo.app/Contents/Info.plist"   # 0.0.2
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$S"/backups/update-*/Previous.app/Contents/Info.plist  # 0.0.1
ls "$S"/backups/update-*/Data                                   # Tasks.store、Attachments
codesign --verify --deep --strict "$S/Apps/QuadrantTodo.app" && echo signed-ok
xattr -p com.apple.quarantine "$S/Apps/QuadrantTodo.app" 2>&1    # 应报 No such xattr
ls -a "$S/Apps"                                                  # 只有 . .. QuadrantTodo.app
(cd "$S/data" && find . -type f ! -name '*-shm' -print0 | sort -z | xargs -0 shasum -a 256) > "$S/after.txt"
diff "$S/before.txt" "$S/after.txt" && echo data-unchanged
```

Expected: 依次为 `0.0.2`、`0.0.1`、备份数据存在、`signed-ok`、无隔离属性、无暂存残留、`data-unchanged`。

若助手脚本在应用退出时被一并终止（表现为应用退出后没有重新打开、`$S/Apps/QuadrantTodo.app` 仍是 0.0.1、`~/Library/Caches/QuadrantTodo/Updates/last-result.json` 不存在），停止并回报：需要改为通过 `launchctl submit` 启动助手，这是对 Task 3 `launchHelper` 的修改，须重新走 Task 3 的测试与提交。

- [ ] **Step 7: Record verification**

在 `docs/verify/README.md` 末尾追加：

```markdown
## 应用内更新（2026-10-16）

在 scratchpad 中安装 0.0.1 到独立的 `Apps/` 目录，使用独立 `QT_DATA_DIR` 与 `QT_BACKUP_DIR`，以 `QT_UPDATE_FEED_URL` 指向本地 `releases/latest` 格式 JSON；新版本 DMG 由 `macos/package-dmg.sh` 以 0.0.2 版本号真实打包（打包后 Info.plist 已恢复为 0.0.1）。

- 升级后应用为 0.0.2，备份目录含 0.0.1 的 `Previous.app` 与 `Data/`；严格验签通过，没有 `com.apple.quarantine` 属性，应用目录无 `.quadrant-update.*` 残留。
- 数据目录升级前后逐文件 SHA-256 一致（排除 SQLite `-shm` 共享内存文件）。
- 篡改 `.sha256` 后升级在校验阶段停止，应用与数据未改动，没有建立备份。
- 下载中点「取消」回到「发现新版本」。

| 截图 | 证明 |
| --- | --- |
| [83-update-up-to-date.png](83-update-up-to-date.png) | 远端版本与本机相同时显示「已是最新版本」。 |
| [84-update-available.png](84-update-available.png) | 发现 0.0.2，显示 Release 说明与「升级到 0.0.2」。 |
| [85-update-downloading.png](85-update-downloading.png) | 限速本地服务器下载时显示进度条与「取消」。 |
| [86-update-checksum-failed.png](86-update-checksum-failed.png) | 校验和不符时红字提示，未进行替换。 |
| [87-update-relaunched.png](87-update-relaunched.png) | 助手替换后自动重新打开，弹窗「已升级到 0.0.2」并给出备份位置。 |

未在真实 GitHub Release 上端到端运行（需要发布 0.0.2 后再验证），也未在 Intel Mac 上运行。
```

把实际观察到的结果与上文不符之处如实改写（例如某项未通过就写明）。

- [ ] **Step 8: Commit**

```bash
git add docs/verify/83-update-up-to-date.png docs/verify/84-update-available.png docs/verify/85-update-downloading.png \
  docs/verify/86-update-checksum-failed.png docs/verify/87-update-relaunched.png docs/verify/README.md
git status
git diff --cached --check
git commit -m "docs: record in-app update runtime verification

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Final rebuild**

Run: `./macos/build.sh`
Expected: 输出 `已生成：…/macos/build/QuadrantTodo.app`，严格验签通过。在最终回复中报告构建结果（含既有 `withAnimation` 警告）。

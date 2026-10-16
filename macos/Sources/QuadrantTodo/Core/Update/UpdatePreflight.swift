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

import Foundation

/// 事项标题规则（UI PRD 3 / 4.2）：单行、去首尾空白后非空、最多 200 个字符。
enum TaskTitle {
    static let maxLength = 200

    enum Problem: Error, Equatable {
        case empty
        case tooLong

        var message: String {
            switch self {
            case .empty: return "请输入待办内容"
            case .tooLong: return "标题最多 \(TaskTitle.maxLength) 个字"
            }
        }
    }

    /// 粘贴进来的换行统一换成空格，保证标题始终是单行。
    static func singleLine(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// 返回可保存的标题；超长时明确报错，不静默截断。
    static func validate(_ raw: String) -> Result<String, Problem> {
        let title = singleLine(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return .failure(.empty) }
        if title.count > maxLength { return .failure(.tooLong) }
        return .success(title)
    }
}

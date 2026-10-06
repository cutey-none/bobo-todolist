import SwiftUI

/// 四象限定义，位置与语义色固定（PRD 4.1）。
enum Quadrant: String, CaseIterable, Identifiable, Codable {
    case importantUrgent
    case importantNotUrgent
    case notImportantUrgent
    case notImportantNotUrgent

    var id: String { rawValue }

    var name: String {
        switch self {
        case .importantUrgent: return "重要且紧急"
        case .importantNotUrgent: return "重要不紧急"
        case .notImportantUrgent: return "不重要但紧急"
        case .notImportantNotUrgent: return "不重要不紧急"
        }
    }

    var hint: String {
        switch self {
        case .importantUrgent: return "立即处理"
        case .importantNotUrgent: return "安排时间"
        case .notImportantUrgent: return "尽快完成"
        case .notImportantNotUrgent: return "有空再做"
        }
    }

    var color: Color {
        switch self {
        case .importantUrgent: return Theme.red
        case .importantNotUrgent: return Theme.blue
        case .notImportantUrgent: return Theme.orange
        case .notImportantNotUrgent: return Theme.gray
        }
    }

    /// 快速添加使用的 `!1`–`!4` 前缀。
    var shortcutNumber: Int {
        switch self {
        case .importantUrgent: return 1
        case .importantNotUrgent: return 2
        case .notImportantUrgent: return 3
        case .notImportantNotUrgent: return 4
        }
    }

    static func from(shortcutNumber: Int) -> Quadrant? {
        allCases.first { $0.shortcutNumber == shortcutNumber }
    }

    /// 面板内 Tab 循环切换顺序：左上 → 右上 → 左下 → 右下。
    var next: Quadrant {
        let all = Quadrant.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

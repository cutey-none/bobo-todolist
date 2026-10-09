import SwiftUI

/// 四象限排布（UI PRD 4.2）：两列时为 2×2，每行高度取该行较高的象限；一列时纵向依次排列。
/// 用同一个 Layout 切换列数，子视图身份不变，跨断点时输入草稿、焦点和展开状态都会保留。
struct MatrixLayout: Layout {
    var columns: Int
    var columnFraction: CGFloat = 0.5
    var topRowFraction: CGFloat = 0.5
    var minimumHeight: CGFloat = 0

    static func leftWidth(total: CGFloat, fraction: CGFloat) -> CGFloat {
        let minimum = min(210, total / 2)
        return min(max(total * fraction, minimum), total - minimum)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = rowHeights(width: width, subviews: subviews).reduce(0, +)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let leftWidth = Self.leftWidth(total: bounds.width, fraction: columnFraction)
        var y = bounds.minY
        for (row, height) in rowHeights(width: bounds.width, subviews: subviews).enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                let columnWidth = columns == 1 ? bounds.width : (column == 0 ? leftWidth : bounds.width - leftWidth)
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + (column == 0 ? 0 : leftWidth), y: y),
                    proposal: ProposedViewSize(width: columnWidth, height: height)
                )
            }
            y += height
        }
    }

    private func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let count = max(columns, 1)
        let leftWidth = Self.leftWidth(total: width, fraction: columnFraction)
        var heights: [CGFloat] = stride(from: 0, to: subviews.count, by: count).map { start in
            subviews[start..<min(start + count, subviews.count)]
                .enumerated().map { column, view in
                    let columnWidth = columns == 1 ? width : (column == 0 ? leftWidth : width - leftWidth)
                    return view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
                }
                .max() ?? 0
        }
        if columns == 2, heights.count == 2 {
            let total = max(minimumHeight, heights.reduce(0, +))
            let top = min(max(total * topRowFraction, heights[0]), total - heights[1])
            heights = [top, total - top]
        }
        return heights
    }
}

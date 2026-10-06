import SwiftUI

/// 四象限排布（UI PRD 4.2）：两列时为 2×2，每行高度取该行较高的象限；一列时纵向依次排列。
/// 用同一个 Layout 切换列数，子视图身份不变，跨断点时输入草稿、焦点和展开状态都会保留。
struct MatrixLayout: Layout {
    var columns: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = rowHeights(width: width, subviews: subviews).reduce(0, +)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = bounds.width / CGFloat(max(columns, 1))
        var y = bounds.minY
        for (row, height) in rowHeights(width: bounds.width, subviews: subviews).enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * columnWidth, y: y),
                    proposal: ProposedViewSize(width: columnWidth, height: height)
                )
            }
            y += height
        }
    }

    private func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let count = max(columns, 1)
        let columnWidth = width / CGFloat(count)
        return stride(from: 0, to: subviews.count, by: count).map { start in
            subviews[start..<min(start + count, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }
}

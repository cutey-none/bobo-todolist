import SwiftUI

/// 象限尾部常驻的单行输入（UI PRD 6）：点击整行即可输入，Enter 提交。
struct QuadrantInputRow: View {
    let quadrant: Quadrant
    let text: String
    let problem: String?
    var focus: FocusState<Quadrant?>.Binding
    let onChange: (String) -> Void
    let onSubmit: () -> Void

    private var isFocused: Bool { focus.wrappedValue == quadrant }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
                TextField("输入新待办…", text: Binding(get: { text }, set: onChange))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused(focus, equals: quadrant)
                    // 输入法候选确认阶段的 Enter 由输入法消化，不会触发提交。
                    .onSubmit(onSubmit)
                    .accessibilityLabel("在\(quadrant.name)新增待办")
                if isFocused {
                    Text("↵ 回车添加")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Theme.subtleFill)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isFocused ? Color.primary.opacity(0.45) : Theme.divider)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            // 点击输入行任意位置都获得焦点，不需要先点「+」。
            .onTapGesture { focus.wrappedValue = quadrant }

            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.red)
                    .padding(.leading, 2)
            }
        }
        .padding(.top, 8)
    }
}

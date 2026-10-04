import SwiftUI

/// 快速添加输入区（PRD F5 / 4.5）。
struct ComposerView: View {
    @ObservedObject var state: AppState
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                TextField("想做点什么？", text: $state.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(onSubmit)
                Text("↵")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 6) {
                ForEach(Quadrant.allCases) { quadrant in
                    Button {
                        state.selectedQuadrant = quadrant
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(quadrant.color).frame(width: 6, height: 6)
                            Text("!\(quadrant.shortcutNumber)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(state.selectedQuadrant == quadrant
                                ? quadrant.color.opacity(0.16)
                                : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                state.selectedQuadrant == quadrant ? quadrant.color.opacity(0.6) : .clear,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(quadrant.name)
                }
                Spacer()
                Text(state.selectedQuadrant.name)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(CardBackground(cornerRadius: 10))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: state.focusRequest) { _, _ in focused = true }
    }
}

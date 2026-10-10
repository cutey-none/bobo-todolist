import SwiftUI

/// Shared system material for floating chrome. Content keeps its own reading surface.
private struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let tint: Color?
    let interactive: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.panelBackground, in: shape)
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1).allowsHitTesting(false))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(VisualEffectView(material: .popover).clipShape(shape))
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5).allowsHitTesting(false))
        }
    }
}

extension View {
    func liquidGlass<S: InsettableShape>(
        in shape: S, tint: Color? = nil, interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

/// Native glass buttons supply system hover, press and keyboard-focus feedback.
private struct LiquidGlassButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var prominent: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            if prominent {
                content.buttonStyle(.glassProminent).tint(Theme.accent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).tint(Theme.accent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func liquidGlassButton(prominent: Bool = false) -> some View {
        modifier(LiquidGlassButtonModifier(prominent: prominent))
    }
}

/// A quiet surface behind task text, with stronger contrast for accessibility.
struct MatrixReadingSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.panelBackground.opacity(reduceTransparency || contrast == .increased ? 1 : 0.72))
    }
}

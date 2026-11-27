import SwiftUI

/// Centralized motion curves that honor macOS Reduce Motion accessibility settings.
enum MotionTokens {
    static func snappy(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.04)
    }

    static func smooth(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    static func panelTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .offset(y: 4))
    }
}

/// Interactive list/card button style with subtle hover tint and press scale.
struct InteractiveSurfaceButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    var isSelected: Bool = false

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                isSelected || isHovered ? CompanionTheme.hairlineBorder : .clear,
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.985 : 1.0)
            .animation(MotionTokens.smooth(reduceMotion: reduceMotion), value: isHovered)
            .animation(MotionTokens.snappy(reduceMotion: reduceMotion), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isSelected { return CompanionTheme.accentTint }
        if isPressed { return CompanionTheme.glassHigh }
        if isHovered { return CompanionTheme.glassMid }
        return CompanionTheme.glassLow
    }
}

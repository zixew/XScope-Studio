import SwiftUI
import DevCompanionCore

@MainActor
@Observable
final class ThemeAppearanceModel {
    static let shared = ThemeAppearanceModel()

    var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: "xscope.theme.accentHex") }
    }
    var cornerRadius: Double {
        didSet { UserDefaults.standard.set(cornerRadius, forKey: "xscope.theme.cornerRadius") }
    }
    var surfaceOpacity: Double {
        didSet { UserDefaults.standard.set(surfaceOpacity, forKey: "xscope.theme.surfaceOpacity") }
    }
    var menuBarConfig: MenuBarLayoutConfig {
        didSet { menuBarStore.save(menuBarConfig) }
    }

    private let menuBarStore = MenuBarLayoutStore()

    private init() {
        self.accentHex = UserDefaults.standard.string(forKey: "xscope.theme.accentHex") ?? "#38BDF8"
        let savedRadius = UserDefaults.standard.object(forKey: "xscope.theme.cornerRadius") as? Double
        self.cornerRadius = savedRadius ?? 10.0
        let savedOpacity = UserDefaults.standard.object(forKey: "xscope.theme.surfaceOpacity") as? Double
        self.surfaceOpacity = savedOpacity ?? 0.05
        self.menuBarConfig = menuBarStore.load()
    }

    var accentColor: Color {
        Color(hexString: accentHex) ?? Color(red: 0.220, green: 0.741, blue: 0.973)
    }
}

private extension Color {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let int = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

enum AppThemePreset: String, CaseIterable, Identifiable {
    case dark = "Dark (Xcode)"
    case light = "Light (Xcode)"
    case midnight = "Midnight"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: AppStrings.Background.themeDark
        case .light: AppStrings.Background.themeLight
        case .midnight: AppStrings.Background.themeMidnight
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark, .midnight: .dark
        case .light: .light
        }
    }

    var isLight: Bool { self == .light }
}

/// Simple, Monochrome-First, Aesthetic tokens adapting to Dark, Light, and Midnight themes.
enum CompanionTheme {
    static let windowBackground = Color(red: 0.043, green: 0.047, blue: 0.063) // #0B0C10
    static let glassLow = Color.primary.opacity(0.05)
    static let glassMid = Color.primary.opacity(0.09)
    static let glassHigh = Color.primary.opacity(0.15)
    static let hairlineBorder = Color.primary.opacity(0.10)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textMuted = Color.secondary.opacity(0.65)

    // Primary Accent (Dynamic from ThemeAppearanceModel) & Icon/Button Surface Tint
    @MainActor
    static var accent: Color { ThemeAppearanceModel.shared.accentColor }
    @MainActor
    static var accentTint: Color { ThemeAppearanceModel.shared.accentColor.opacity(0.18) }

    // Restrained semantic indicators (used only for tiny 6px status dots / subtle text)
    static let mint = Color(red: 0.204, green: 0.827, blue: 0.600) // #34D399
    @MainActor static var teal: Color { accent }
    static let amber = Color(red: 0.984, green: 0.749, blue: 0.141) // #FBBF24
    static let coral = Color(red: 0.973, green: 0.443, blue: 0.443) // #F87171
    @MainActor static var violet: Color { accent }
    @MainActor static var magenta: Color { accent }
}

struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let appearance = ThemeAppearanceModel.shared
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(appearance.surfaceOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
                            .stroke(CompanionTheme.hairlineBorder, lineWidth: 1)
                    )
            )
    }
}

struct GradientBadgeIcon: View {
    let systemName: String
    let colors: [Color]
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.52, weight: .medium))
            .foregroundStyle(CompanionTheme.textPrimary.opacity(0.85))
            .frame(width: size, height: size)
    }
}

/// Swiss-precision brand mark for XScope Studio (Matte Graphite + Scope Reticle + X + Focal Plane).
struct XScopeLogoMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.114, green: 0.125, blue: 0.153), Color(red: 0.071, green: 0.078, blue: 0.098)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                )

            // Corner scope reticle brackets
            Path { p in
                let minC = size * 0.22
                let maxC = size * 0.78
                let arm = size * 0.13
                p.move(to: CGPoint(x: minC, y: minC + arm))
                p.addLine(to: CGPoint(x: minC, y: minC))
                p.addLine(to: CGPoint(x: minC + arm, y: minC))

                p.move(to: CGPoint(x: maxC - arm, y: minC))
                p.addLine(to: CGPoint(x: maxC, y: minC))
                p.addLine(to: CGPoint(x: maxC, y: minC + arm))

                p.move(to: CGPoint(x: minC, y: maxC - arm))
                p.addLine(to: CGPoint(x: minC, y: maxC))
                p.addLine(to: CGPoint(x: minC + arm, y: maxC))

                p.move(to: CGPoint(x: maxC - arm, y: maxC))
                p.addLine(to: CGPoint(x: maxC, y: maxC))
                p.addLine(to: CGPoint(x: maxC, y: maxC - arm))
            }
            .stroke(Color(red: 0.580, green: 0.639, blue: 0.722), style: StrokeStyle(lineWidth: max(1.0, size * 0.055), lineCap: .round, lineJoin: .round))

            // Precision X mark
            Path { p in
                let a = size * 0.34
                let b = size * 0.66
                p.move(to: CGPoint(x: a, y: a))
                p.addLine(to: CGPoint(x: b, y: b))
                p.move(to: CGPoint(x: a, y: b))
                p.addLine(to: CGPoint(x: b, y: a))
            }
            .stroke(Color(red: 0.945, green: 0.961, blue: 0.976), style: StrokeStyle(lineWidth: max(1.5, size * 0.095), lineCap: .round))

            // Single focal inspection line
            Path { p in
                p.move(to: CGPoint(x: size * 0.26, y: size * 0.50))
                p.addLine(to: CGPoint(x: size * 0.74, y: size * 0.50))
            }
            .stroke(CompanionTheme.accent, style: StrokeStyle(lineWidth: max(1.2, size * 0.065), lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

import SwiftUI
import DevCompanionCore

private final class HighlightCacheBox: NSObject {
    let attributed: AttributedString
    init(_ attributed: AttributedString) {
        self.attributed = attributed
    }
}

@MainActor
private enum XcodeCodeHighlightCache {
    static let cache: NSCache<NSString, HighlightCacheBox> = {
        let c = NSCache<NSString, HighlightCacheBox>()
        c.countLimit = 128
        return c
    }()
}

/// Renders Swift source code using a calm, eye-friendly syntax palette with bounded caching.
struct XcodeCodeText: View {
    @Environment(\.colorScheme) private var colorScheme
    let code: String
    var fontSize: CGFloat = 12

    var body: some View {
        Text(attributedCode)
            .font(.system(size: fontSize, design: .monospaced))
            .lineSpacing(3.5)
            .textSelection(.enabled)
    }

    private var attributedCode: AttributedString {
        let schemeTag = colorScheme == .light ? "L" : "D"
        let cacheKey = "\(schemeTag):\(code.hashValue):\(code.count)" as NSString
        if let cached = XcodeCodeHighlightCache.cache.object(forKey: cacheKey) {
            return cached.attributed
        }

        let tokens = SwiftSyntaxHighlighter().tokenize(code)
        var result = AttributedString()
        for token in tokens {
            var part = AttributedString(token.text)
            part.foregroundColor = color(for: token.kind)
            result.append(part)
        }
        XcodeCodeHighlightCache.cache.setObject(HighlightCacheBox(result), forKey: cacheKey)
        return result
    }

    private func color(for kind: SwiftTokenKind) -> Color {
        if colorScheme == .light {
            switch kind {
            case .keyword, .attribute: Color(red: 0.608, green: 0.137, blue: 0.576) // #9B2393
            case .string:              Color(red: 0.769, green: 0.102, blue: 0.086) // #C41A16
            case .comment:             Color(red: 0.365, green: 0.424, blue: 0.475) // #5D6C79
            case .number:              Color(red: 0.110, green: 0.000, blue: 0.812) // #1C00CF
            case .type:                Color(red: 0.059, green: 0.408, blue: 0.627) // #0F68A0
            case .plain:               Color(red: 0.110, green: 0.114, blue: 0.125) // #1C1D20
            }
        } else {
            switch kind {
            case .keyword, .attribute: Color(red: 0.957, green: 0.447, blue: 0.714) // #F472B6 (Calm Rose)
            case .string:              Color(red: 0.992, green: 0.643, blue: 0.686) // #FDA4AF (Warm Peach)
            case .comment:             Color(red: 0.545, green: 0.580, blue: 0.620) // #8B949E (Muted Slate)
            case .number:              Color(red: 0.910, green: 0.808, blue: 0.514) // #E8CE83 (Soft Sand)
            case .type:                Color(red: 0.490, green: 0.827, blue: 0.988) // #7DD3FC (Soft Sky)
            case .plain:               Color(red: 0.902, green: 0.929, blue: 0.953) // #E6EDF3 (Soft Off-White)
            }
        }
    }
}

/// High-opacity calm code container that blocks busy background wallpapers from bleeding through code text.
struct CodeSurfaceContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        colorScheme == .light
                            ? Color(white: 0.98).opacity(0.94)
                            : Color(red: 0.055, green: 0.075, blue: 0.115).opacity(0.90)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        colorScheme == .light
                            ? Color.black.opacity(0.08)
                            : Color.white.opacity(0.09),
                        lineWidth: 1
                    )
            )
    }
}

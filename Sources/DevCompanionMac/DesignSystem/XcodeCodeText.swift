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

/// Renders Swift source code using Xcode Default (Dark or Light) syntax highlighting colors with bounded caching.
struct XcodeCodeText: View {
    @Environment(\.colorScheme) private var colorScheme
    let code: String
    var fontSize: CGFloat = 11

    var body: some View {
        Text(attributedCode)
            .font(.system(size: fontSize, design: .monospaced))
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
            case .keyword, .attribute: Color(red: 0.988, green: 0.373, blue: 0.639) // #FC5FA3
            case .string:              Color(red: 0.988, green: 0.416, blue: 0.365) // #FC6A5D
            case .comment:             Color(red: 0.424, green: 0.475, blue: 0.525) // #6C7986
            case .number:              Color(red: 0.816, green: 0.749, blue: 0.412) // #D0BF69
            case .type:                Color(red: 0.365, green: 0.847, blue: 1.000) // #5DD8FF
            case .plain:               Color(red: 0.875, green: 0.875, blue: 0.878) // #DFDFE0
            }
        }
    }
}

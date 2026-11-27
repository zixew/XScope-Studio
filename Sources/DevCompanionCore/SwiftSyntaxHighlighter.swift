import Foundation

public enum SwiftTokenKind: Sendable, Equatable {
    case keyword
    case attribute
    case string
    case comment
    case number
    case type
    case plain
}

public struct SwiftCodeToken: Sendable, Equatable {
    public let text: String
    public let kind: SwiftTokenKind

    public init(text: String, kind: SwiftTokenKind) {
        self.text = text
        self.kind = kind
    }
}

/// Lightweight tokenizer mapping Swift source code to Xcode Default (Dark) syntax token kinds.
public struct SwiftSyntaxHighlighter: Sendable {
    private static let keywords: Set<String> = [
        "import", "struct", "class", "final", "enum", "protocol", "extension",
        "func", "let", "var", "if", "else", "guard", "return", "throw", "throws",
        "async", "await", "try", "do", "catch", "for", "in", "while", "switch",
        "case", "default", "self", "Self", "true", "false", "nil", "weak",
        "unowned", "private", "public", "internal", "fileprivate", "static", "override"
    ]

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var tokenCache: [String: [SwiftCodeToken]] = [:]
    private static let maxCacheEntries = 512

    public init() {}

    public func tokenize(_ source: String) -> [SwiftCodeToken] {
        Self.cacheLock.lock()
        if let cached = Self.tokenCache[source] {
            Self.cacheLock.unlock()
            return cached
        }
        Self.cacheLock.unlock()

        var tokens: [SwiftCodeToken] = []
        let chars = Array(source)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            // Line comment // ...
            if ch == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                let start = i
                while i < chars.count, chars[i] != "\n" { i += 1 }
                tokens.append(SwiftCodeToken(text: String(chars[start..<i]), kind: .comment))
                continue
            }

            // String literal "..."
            if ch == "\"" {
                let start = i
                i += 1
                while i < chars.count {
                    if chars[i] == "\\", i + 1 < chars.count {
                        i += 2
                        continue
                    }
                    if chars[i] == "\"" {
                        i += 1
                        break
                    }
                    if chars[i] == "\n" { break }
                    i += 1
                }
                tokens.append(SwiftCodeToken(text: String(chars[start..<i]), kind: .string))
                continue
            }

            // Attributes & macros (@Test, @Suite, @testable, #expect)
            if ch == "@" || ch == "#" {
                let start = i
                i += 1
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                    i += 1
                }
                tokens.append(SwiftCodeToken(text: String(chars[start..<i]), kind: .attribute))
                continue
            }

            // Numbers
            if ch.isNumber {
                let start = i
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    i += 1
                }
                tokens.append(SwiftCodeToken(text: String(chars[start..<i]), kind: .number))
                continue
            }

            // Identifiers / Keywords / Types
            if ch.isLetter || ch == "_" {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                    i += 1
                }
                let word = String(chars[start..<i])
                let kind: SwiftTokenKind = if Self.keywords.contains(word) {
                    .keyword
                } else if word.first?.isUppercase == true {
                    .type
                } else {
                    .plain
                }
                tokens.append(SwiftCodeToken(text: word, kind: kind))
                continue
            }

            // Whitespace & punctuation
            let start = i
            i += 1
            while i < chars.count {
                let next = chars[i]
                if next.isLetter || next.isNumber || next == "_" || next == "\"" || next == "@" || next == "#" || next == "/" {
                    break
                }
                i += 1
            }
            tokens.append(SwiftCodeToken(text: String(chars[start..<i]), kind: .plain))
        }

        if source.count <= 4096 {
            Self.cacheLock.lock()
            if Self.tokenCache.count >= Self.maxCacheEntries {
                Self.tokenCache.removeAll(keepingCapacity: true)
            }
            Self.tokenCache[source] = tokens
            Self.cacheLock.unlock()
        }

        return tokens
    }
}

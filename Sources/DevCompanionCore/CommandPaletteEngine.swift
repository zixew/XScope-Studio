import Foundation

public enum CommandPaletteCategory: String, Sendable, CaseIterable {
    case module = "Modules"
    case action = "Quick Actions"
    case target = "Targets & Devices"
}

public struct CommandPaletteItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let shortcutHint: String?
    public let category: CommandPaletteCategory
    public let keywords: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        shortcutHint: String? = nil,
        category: CommandPaletteCategory,
        keywords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcutHint = shortcutHint
        self.category = category
        self.keywords = keywords
    }
}

public enum CommandPaletteMatcher {
    /// Filters and ranks palette items using lightweight prefix, substring, and subsequence scoring.
    public static func filter(items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return items }

        let scored: [(item: CommandPaletteItem, score: Int)] = items.compactMap { item in
            let score = bestScore(for: item, query: trimmed)
            guard score > 0 else { return nil }
            return (item, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.item.title < rhs.item.title
            }
            .map(\.item)
    }

    private static func bestScore(for item: CommandPaletteItem, query: String) -> Int {
        let candidates = [item.title, item.subtitle] + item.keywords
        var maxScore = 0
        for candidate in candidates {
            let lowered = candidate.lowercased()
            if lowered == query {
                maxScore = max(maxScore, 1000)
            } else if lowered.hasPrefix(query) {
                maxScore = max(maxScore, 800)
            } else if lowered.contains(query) {
                maxScore = max(maxScore, 500)
            } else if isSubsequence(query, of: lowered) {
                maxScore = max(maxScore, 250)
            }
        }
        return maxScore
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var needleIdx = needle.startIndex
        var haystackIdx = haystack.startIndex
        while needleIdx < needle.endIndex, haystackIdx < haystack.endIndex {
            if needle[needleIdx] == haystack[haystackIdx] {
                needleIdx = needle.index(after: needleIdx)
            }
            haystackIdx = haystack.index(after: haystackIdx)
        }
        return needleIdx == needle.endIndex
    }
}

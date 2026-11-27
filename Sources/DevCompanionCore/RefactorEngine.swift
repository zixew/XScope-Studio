import Foundation

public enum RefactorRuleKind: String, CaseIterable, Sendable, Identifiable {
    case longFunction = "Long Function"
    case deepNesting = "Deep Nesting"
    case massiveType = "Massive Type"
    case missingFinal = "Missing final"
    case dispatchQueueToAsync = "GCD → async/await"
    case forceUnwrap = "Force Unwrap"

    public var id: String { rawValue }
}

public enum RefactorSeverity: String, Sendable, Comparable {
    case high = "P0"
    case medium = "P1"
    case low = "P2"

    private var rank: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    public static func < (lhs: RefactorSeverity, rhs: RefactorSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct TokenBudgetEstimate: Sendable, Equatable {
    public let compactTokens: Int
    public let verboseTokens: Int
    public let savedTokens: Int
    public let savedPercent: Int

    public init(compactTokens: Int, verboseTokens: Int) {
        self.compactTokens = max(1, compactTokens)
        self.verboseTokens = max(self.compactTokens, verboseTokens)
        self.savedTokens = max(0, self.verboseTokens - self.compactTokens)
        self.savedPercent = self.verboseTokens > 0
            ? Int((Double(self.savedTokens) / Double(self.verboseTokens) * 100.0).rounded())
            : 0
    }
}

public struct RefactorOpportunity: Identifiable, Sendable, Equatable {
    public let id: String
    public let rule: RefactorRuleKind
    public let severity: RefactorSeverity
    public let filePath: String
    public let fileName: String
    public let moduleName: String
    public let symbolName: String
    public let startLine: Int
    public let endLine: Int
    public let metricSummary: String
    public let codeSlice: String
    public let fullFileLineCount: Int
    public let hasLocalFix: Bool
    public let localOldSnippet: String?
    public let localNewSnippet: String?
    public let localFixTitle: String?

    public init(
        rule: RefactorRuleKind,
        severity: RefactorSeverity,
        filePath: String,
        fileName: String,
        moduleName: String,
        symbolName: String,
        startLine: Int,
        endLine: Int,
        metricSummary: String,
        codeSlice: String,
        fullFileLineCount: Int,
        hasLocalFix: Bool = false,
        localOldSnippet: String? = nil,
        localNewSnippet: String? = nil,
        localFixTitle: String? = nil
    ) {
        self.id = "\(rule.rawValue)::\(filePath):\(startLine):\(symbolName)"
        self.rule = rule
        self.severity = severity
        self.filePath = filePath
        self.fileName = fileName
        self.moduleName = moduleName
        self.symbolName = symbolName
        self.startLine = startLine
        self.endLine = endLine
        self.metricSummary = metricSummary
        self.codeSlice = codeSlice
        self.fullFileLineCount = fullFileLineCount
        self.hasLocalFix = hasLocalFix
        self.localOldSnippet = localOldSnippet
        self.localNewSnippet = localNewSnippet
        self.localFixTitle = localFixTitle
    }
}

public struct RefactorEngine: Sendable {
    private static let excludedDirs: Set<String> = [
        ".build", ".git", "Pods", "Carthage", "DerivedData", "node_modules", ".swiftpm"
    ]

    public init() {}

    public func analyze(directoryURL: URL, moduleFilter: String? = nil) -> [RefactorOpportunity] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [RefactorOpportunity] = []
        let rootPath = directoryURL.path

        while let item = enumerator.nextObject() as? URL {
            let name = item.lastPathComponent
            if Self.excludedDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            guard item.pathExtension == "swift" else { continue }
            if let filter = moduleFilter, !filter.isEmpty {
                let rel = item.path.replacingOccurrences(of: rootPath + "/", with: "")
                if !rel.localizedCaseInsensitiveContains(filter) {
                    continue
                }
            }
            results.append(contentsOf: analyzeFile(url: item, projectRoot: directoryURL))
        }

        return results.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            if lhs.hasLocalFix != rhs.hasLocalFix { return lhs.hasLocalFix && !rhs.hasLocalFix }
            return lhs.fileName < rhs.fileName
        }
    }

    public func analyzeFile(url: URL, projectRoot: URL? = nil) -> [RefactorOpportunity] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }

        let fileName = url.lastPathComponent
        let moduleName = Self.resolveModuleName(url: url, projectRoot: projectRoot)
        var opportunities: [RefactorOpportunity] = []

        var braceDepth = 0
        var activeFunc: (name: String, startLine: Int, baseDepth: Int, maxDepth: Int)?
        var activeType: (name: String, startLine: Int, baseDepth: Int)?

        for (idx, rawLine) in lines.enumerated() {
            let lineNo = idx + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let isComment = trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*")

            if !isComment {
                // 1. Missing `final` on non-open, non-final class declarations
                if trimmed.range(of: #"^(public\s+|internal\s+|private\s+|fileprivate\s+)?class\s+[A-Za-z_][A-Za-z0-9_]*"#, options: .regularExpression) != nil,
                   !trimmed.contains("final class "),
                   !trimmed.contains("open class ") {
                    let className = Self.extractIdentifier(after: "class ", in: trimmed) ?? "Class"
                    let newLine = rawLine.replacingOccurrences(of: "class ", with: "final class ")
                    opportunities.append(
                        RefactorOpportunity(
                            rule: .missingFinal,
                            severity: .low,
                            filePath: url.path,
                            fileName: fileName,
                            moduleName: moduleName,
                            symbolName: className,
                            startLine: lineNo,
                            endLine: min(lines.count, lineNo + 2),
                            metricSummary: "Class can be marked final (static dispatch)",
                            codeSlice: Self.slice(lines: lines, start: lineNo, end: min(lines.count, lineNo + 3)),
                            fullFileLineCount: lines.count,
                            hasLocalFix: true,
                            localOldSnippet: rawLine,
                            localNewSnippet: newLine,
                            localFixTitle: "Mark `\(className)` as `final class` (0 AI tokens)"
                        )
                    )
                }

                // 2. Massive type tracking
                if activeType == nil,
                   trimmed.range(of: #"\b(class|struct|actor)\s+[A-Za-z_][A-Za-z0-9_]*"#, options: .regularExpression) != nil,
                   trimmed.contains("{") {
                    let typeName = Self.extractTypeName(in: trimmed) ?? fileName
                    activeType = (typeName, lineNo, braceDepth)
                }

                // 3. Function start tracking
                if activeFunc == nil,
                   trimmed.range(of: #"\bfunc\s+[A-Za-z_][A-Za-z0-9_]*"#, options: .regularExpression) != nil,
                   trimmed.contains("{") {
                    let funcName = Self.extractIdentifier(after: "func ", in: trimmed) ?? "func"
                    activeFunc = (funcName, lineNo, braceDepth, braceDepth)
                }

                // 4. Legacy DispatchQueue -> async/await
                if trimmed.contains("DispatchQueue.global(") || trimmed.contains("DispatchQueue.main.asyncAfter(") {
                    let end = min(lines.count, lineNo + 6)
                    opportunities.append(
                        RefactorOpportunity(
                            rule: .dispatchQueueToAsync,
                            severity: .medium,
                            filePath: url.path,
                            fileName: fileName,
                            moduleName: moduleName,
                            symbolName: activeFunc?.name ?? fileName,
                            startLine: max(1, lineNo - 1),
                            endLine: end,
                            metricSummary: "Legacy GCD dispatch block",
                            codeSlice: Self.slice(lines: lines, start: max(1, lineNo - 1), end: end),
                            fullFileLineCount: lines.count
                        )
                    )
                }

                // 5. Force unwrap check (ignoring !=, !flag, strings)
                if trimmed.range(of: #"[A-Za-z0-9_\)\]]!\s*($|\.|,|;|\))"#, options: .regularExpression) != nil,
                   !trimmed.contains("!=") {
                    let end = min(lines.count, lineNo + 2)
                    opportunities.append(
                        RefactorOpportunity(
                            rule: .forceUnwrap,
                            severity: .medium,
                            filePath: url.path,
                            fileName: fileName,
                            moduleName: moduleName,
                            symbolName: activeFunc?.name ?? fileName,
                            startLine: max(1, lineNo - 1),
                            endLine: end,
                            metricSummary: "Force unwrap (!) can crash at runtime",
                            codeSlice: Self.slice(lines: lines, start: max(1, lineNo - 1), end: end),
                            fullFileLineCount: lines.count
                        )
                    )
                }
            }

            let openCount = isComment ? 0 : rawLine.filter { $0 == "{" }.count
            let closeCount = isComment ? 0 : rawLine.filter { $0 == "}" }.count
            braceDepth = max(0, braceDepth + openCount - closeCount)

            if var fn = activeFunc {
                if braceDepth > fn.maxDepth {
                    fn.maxDepth = braceDepth
                    activeFunc = fn
                }
                if braceDepth <= fn.baseDepth {
                    let fnLength = lineNo - fn.startLine + 1
                    let nesting = max(0, fn.maxDepth - fn.baseDepth - 1)
                    if fnLength > 40 {
                        opportunities.append(
                            RefactorOpportunity(
                                rule: .longFunction,
                                severity: fnLength > 80 ? .high : .medium,
                                filePath: url.path,
                                fileName: fileName,
                                moduleName: moduleName,
                                symbolName: fn.name,
                                startLine: fn.startLine,
                                endLine: lineNo,
                                metricSummary: "\(fnLength) lines (extract smaller helpers)",
                                codeSlice: Self.slice(lines: lines, start: fn.startLine, end: min(lineNo, fn.startLine + 65)),
                                fullFileLineCount: lines.count
                            )
                        )
                    }
                    if nesting >= 3 {
                        opportunities.append(
                            RefactorOpportunity(
                                rule: .deepNesting,
                                severity: nesting >= 4 ? .high : .medium,
                                filePath: url.path,
                                fileName: fileName,
                                moduleName: moduleName,
                                symbolName: fn.name,
                                startLine: fn.startLine,
                                endLine: lineNo,
                                metricSummary: "Nesting depth \(nesting) (use guard / early return)",
                                codeSlice: Self.slice(lines: lines, start: fn.startLine, end: min(lineNo, fn.startLine + 65)),
                                fullFileLineCount: lines.count
                            )
                        )
                    }
                    activeFunc = nil
                }
            }

            if let tp = activeType, braceDepth <= tp.baseDepth {
                let typeLength = lineNo - tp.startLine + 1
                if typeLength > 300 {
                    opportunities.append(
                        RefactorOpportunity(
                            rule: .massiveType,
                            severity: .high,
                            filePath: url.path,
                            fileName: fileName,
                            moduleName: moduleName,
                            symbolName: tp.name,
                            startLine: tp.startLine,
                            endLine: lineNo,
                            metricSummary: "\(typeLength) lines (split responsibilities)",
                            codeSlice: Self.slice(lines: lines, start: tp.startLine, end: min(lineNo, tp.startLine + 40)),
                            fullFileLineCount: lines.count
                        )
                    )
                }
                activeType = nil
            }
        }

        return opportunities
    }

    public func buildCompactRefactorPrompt(
        opportunity: RefactorOpportunity,
        goal: String? = nil
    ) -> (prompt: String, budget: TokenBudgetEstimate) {
        let strippedSlice = opportunity.codeSlice
            .components(separatedBy: .newlines)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("//")
            }
            .joined(separator: "\n")

        let goalText = (goal?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultGoal(for: opportunity.rule)

        let compactPrompt = """
        Refactor \(opportunity.fileName):\(opportunity.startLine)-\(opportunity.endLine) (\(opportunity.symbolName), \(opportunity.rule.rawValue)).
        Goal: \(goalText). Keep behavior identical. Output unified diff only.
        ```swift
        \(strippedSlice)
        ```
        """

        // Verbose baseline: sending full file + prose explanation
        let estimatedFullFileChars = max(opportunity.codeSlice.count * 2, opportunity.fullFileLineCount * 42) + 260
        let compactTokens = max(1, (compactPrompt.count + 3) / 4)
        let verboseTokens = max(compactTokens, (estimatedFullFileChars + 3) / 4)
        return (compactPrompt, TokenBudgetEstimate(compactTokens: compactTokens, verboseTokens: verboseTokens))
    }

    private func defaultGoal(for rule: RefactorRuleKind) -> String {
        switch rule {
        case .longFunction: "Extract cohesive helper functions"
        case .deepNesting: "Flatten nesting with guard/early returns"
        case .massiveType: "Split responsibilities into focused extensions/types"
        case .missingFinal: "Mark non-subclassed class as final"
        case .dispatchQueueToAsync: "Migrate GCD block to Swift Concurrency async/await"
        case .forceUnwrap: "Replace ! with safe guard-let or nil-coalescing"
        }
    }

    private static func slice(lines: [String], start: Int, end: Int) -> String {
        let s = max(1, start) - 1
        let e = min(lines.count, end) - 1
        guard s <= e else { return "" }
        return lines[s...e].joined(separator: "\n")
    }

    private static func extractIdentifier(after prefix: String, in line: String) -> String? {
        guard let range = line.range(of: prefix) else { return nil }
        let rest = line[range.upperBound...]
        let chars = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return chars.isEmpty ? nil : String(chars)
    }

    private static func extractTypeName(in line: String) -> String? {
        for kw in ["class ", "struct ", "actor "] {
            if let name = extractIdentifier(after: kw, in: line) {
                return name
            }
        }
        return nil
    }

    private static func resolveModuleName(url: URL, projectRoot: URL?) -> String {
        guard let root = projectRoot else {
            return url.deletingLastPathComponent().lastPathComponent
        }
        let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
        let parts = rel.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : root.lastPathComponent
    }
}

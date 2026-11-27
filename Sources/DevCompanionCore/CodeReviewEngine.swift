import Foundation

public struct CodeReviewFinding: Identifiable, Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, CaseIterable, Codable {
        case critical = "Critical"
        case warning = "Warning"
        case suggestion = "Suggestion"

        public var priorityRank: Int {
            switch self {
            case .critical: return 0
            case .warning: return 1
            case .suggestion: return 2
            }
        }

        public var priorityBadge: String {
            switch self {
            case .critical: return "P0"
            case .warning: return "P1"
            case .suggestion: return "P2"
            }
        }
    }

    public enum Category: String, Sendable, CaseIterable, Codable, Identifiable {
        case memoryLeak = "Memory / Retain Cycle"
        case mainThread = "Main Thread / Freeze"
        case safety = "Type Safety"
        case codeHygiene = "Code Hygiene"
        case security = "Security & Secrets"
        case swiftUI = "SwiftUI Performance"
        case uiKit = "UIKit Best Practice"

        public var id: String { rawValue }
    }

    public let id: String
    public let fileName: String
    public let lineNumber: Int
    public let severity: Severity
    public let category: Category
    public let title: String
    public let detail: String
    public let codeSnippet: String
    public var detectedAt: Date
    public var isNew: Bool

    public var formattedDateString: String {
        if detectedAt.timeIntervalSince1970 <= 0 {
            return ""
        }
        return Self.dateFormatter.string(from: detectedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    public init(
        id: String? = nil,
        fileName: String,
        lineNumber: Int,
        severity: Severity,
        category: Category,
        title: String,
        detail: String,
        codeSnippet: String,
        detectedAt: Date = Date(timeIntervalSince1970: 0),
        isNew: Bool = false
    ) {
        self.id = id ?? "\(fileName):\(lineNumber):\(category.rawValue)"
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.severity = severity
        self.category = category
        self.title = title
        self.detail = detail
        self.codeSnippet = codeSnippet
        self.detectedAt = detectedAt
        self.isNew = isNew
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, lineNumber, severity, category, title, detail, codeSnippet, detectedAt, isNew
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fileName = try c.decode(String.self, forKey: .fileName)
        lineNumber = try c.decode(Int.self, forKey: .lineNumber)
        severity = try c.decode(Severity.self, forKey: .severity)
        category = try c.decode(Category.self, forKey: .category)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decode(String.self, forKey: .detail)
        codeSnippet = try c.decode(String.self, forKey: .codeSnippet)
        detectedAt = (try? c.decode(Date.self, forKey: .detectedAt)) ?? Date(timeIntervalSince1970: 0)
        isNew = (try? c.decode(Bool.self, forKey: .isNew)) ?? false
    }
}

public enum CodeReviewScopeMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case branchDiff = "Pull Request (Branch Diff)"
    case moduleFolder = "Per-Module / Folder"
    case allProject = "All Project"

    public var id: String { rawValue }
}

public enum GitBranchFilterKind: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case local = "Local"
    case remote = "Remote"
    case common = "Common"

    public var id: String { rawValue }
}

public struct CodeReviewFileGroup: Identifiable, Sendable, Equatable {
    public let id: String
    public let fileName: String
    public let findings: [CodeReviewFinding]
    public let criticalCount: Int
    public let warningCount: Int
    public let suggestionCount: Int
    public let hasNew: Bool
    public let latestDetectedAt: Date

    public init(fileName: String, findings: [CodeReviewFinding]) {
        self.id = fileName
        self.fileName = fileName
        self.findings = findings
        self.criticalCount = findings.filter { $0.severity == .critical }.count
        self.warningCount = findings.filter { $0.severity == .warning }.count
        self.suggestionCount = findings.filter { $0.severity == .suggestion }.count
        self.hasNew = findings.contains(where: \.isNew)
        self.latestDetectedAt = findings.map(\.detectedAt).max() ?? Date(timeIntervalSince1970: 0)
    }
}

public struct GitBranchComparisonSummary: Sendable, Equatable {
    public let sourceBranch: String
    public let targetBranch: String
    public let commits: [String]
    public let changedSwiftFiles: [String]
    public let changedLinesByFile: [String: Set<Int>]

    public init(
        sourceBranch: String,
        targetBranch: String,
        commits: [String] = [],
        changedSwiftFiles: [String] = [],
        changedLinesByFile: [String: Set<Int>] = [:]
    ) {
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.commits = commits
        self.changedSwiftFiles = changedSwiftFiles
        self.changedLinesByFile = changedLinesByFile
    }
}

/// Local static analyzer tailored for UIKit & SwiftUI anti-patterns, Git branch PR diffs, and per-module audits.
public struct CodeReviewEngine: Sendable {
    private let runner: any CommandExecuting

    public init(runner: any CommandExecuting = ProcessRunner()) {
        self.runner = runner
    }

    public func analyze(
        source: String,
        fileName: String = "Untitled.swift",
        allowedLines: Set<Int>? = nil
    ) -> [CodeReviewFinding] {
        let lines = source.components(separatedBy: .newlines)
        var findings: [CodeReviewFinding] = []

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            if let allowedLines, !allowedLines.contains(lineNumber) {
                continue
            }
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                // Check for unresolved TODO / FIXME in comments for PR hygiene
                if trimmed.localizedCaseInsensitiveContains("TODO:") || trimmed.localizedCaseInsensitiveContains("FIXME:") {
                    findings.append(
                        CodeReviewFinding(
                            fileName: fileName,
                            lineNumber: lineNumber,
                            severity: .suggestion,
                            category: .codeHygiene,
                            title: "Unresolved TODO / FIXME Comment",
                            detail: "Selesaikan atau pindahkan catatan `TODO`/`FIXME` ke tiket backlog sebelum merge Pull Request.",
                            codeSnippet: trimmed
                        )
                    )
                }
                continue
            }

            // 1. Potential Retain Cycle in UIKit / escaping closures / timers / observers
            if (trimmed.contains("DispatchQueue") || trimmed.contains("sink {") || trimmed.contains("Task {") || trimmed.contains("completion") || trimmed.contains("UIView.animate") || trimmed.contains("addObserver") || trimmed.contains("scheduledTimer")) &&
                trimmed.contains("{") && !trimmed.contains("[weak self]") && !trimmed.contains("[unowned self]") {
                let nextBlock = lines.dropFirst(index).prefix(5).joined(separator: " ")
                if nextBlock.contains("self.") {
                    findings.append(
                        CodeReviewFinding(
                            fileName: fileName,
                            lineNumber: lineNumber,
                            severity: .critical,
                            category: .memoryLeak,
                            title: "Potensi Retain Cycle (Missing [weak self])",
                            detail: "Closure mereferensikan `self` tanpa `[weak self]`. Di UIViewController/ViewModel ini sering menyebabkan memory leak.",
                            codeSnippet: trimmed
                        )
                    )
                }
            }

            // 2. Synchronous Data(contentsOf:) or heavy blocking on potential main thread
            if trimmed.contains("Data(contentsOf:") || trimmed.contains("Thread.sleep") || trimmed.contains("DispatchSemaphore") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .critical,
                        category: .mainThread,
                        title: "Potensi Freeze / Main-Thread Blocking",
                        detail: "Operasi sinkron (`Data(contentsOf:)`, `sleep`, atau `DispatchSemaphore`) dapat membekukan UI jika terpanggil di main thread.",
                        codeSnippet: trimmed
                    )
                )
            }

            // 3. SwiftUI: @ObservedObject initialized inline
            if trimmed.contains("@ObservedObject") && trimmed.contains("=") && trimmed.contains("()") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .warning,
                        category: .swiftUI,
                        title: "@ObservedObject diinisialisasi langsung",
                        detail: "Gunakan `@StateObject` (atau `@State` untuk `@Observable`) agar instance tidak dibuat ulang setiap kali View di-redraw.",
                        codeSnippet: trimmed
                    )
                )
            }

            // 4. SwiftUI: DateFormatter / JSONDecoder created inside body
            if (trimmed.contains("DateFormatter()") || trimmed.contains("NumberFormatter()")) && !trimmed.contains("static") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .warning,
                        category: .swiftUI,
                        title: "Alokasi Formatter berulang",
                        detail: "Membuat `DateFormatter()`/`NumberFormatter()` berulang kali (terutama di `body` atau `cellForRowAt`) sangat mahal. Jadikan `static let`.",
                        codeSnippet: trimmed
                    )
                )
            }

            // 5. UIKit: Strong delegate / dataSource property
            if (trimmed.contains("var delegate:") || trimmed.contains("var dataSource:")) && !trimmed.contains("weak ") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .critical,
                        category: .uiKit,
                        title: "Delegate UIKit tidak `weak`",
                        detail: "Deklarasikan `weak var delegate` untuk mencegah retain cycle antar `UIViewController` / `UIView`.",
                        codeSnippet: trimmed
                    )
                )
            }

            // 6. Force unwrap / try! / as!
            if trimmed.contains("try!") || trimmed.contains("as!") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .suggestion,
                        category: .safety,
                        title: "Hindari `try!` / `as!`",
                        detail: "Gunakan `do/catch` atau `as?` dengan `guard` agar aplikasi tidak crash saat runtime.",
                        codeSnippet: trimmed
                    )
                )
            }

            // 7. Fatal Crash: fatalError / preconditionFailure or forced property chaining (!.)
            if (trimmed.contains("fatalError(") || trimmed.contains("preconditionFailure(")) && !trimmed.contains("init(coder:") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .critical,
                        category: .safety,
                        title: "Potensi Force Crash (`fatalError` / `preconditionFailure`)",
                        detail: "Hindari `fatalError` di jalur eksekusi runtime; gunakan error handling atau early `return`.",
                        codeSnippet: trimmed
                    )
                )
            } else if (trimmed.contains("?.") == false && trimmed.range(of: #"[A-Za-z0-9_\)\]]!\.[A-Za-z_]"#, options: .regularExpression) != nil)
                        || trimmed.contains(".first!") || trimmed.contains(".last!") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .warning,
                        category: .safety,
                        title: "Potensi Crash Force Unwrap (`!`)",
                        detail: "Akses properti dengan force-unwrap (`!.` / `.first!`) akan menyebabkan crash `EXC_BREAKPOINT` jika bernilai `nil`.",
                        codeSnippet: trimmed
                    )
                )
            }

            // 8. Code Hygiene: Leftover debug print / NSLog
            if trimmed.hasPrefix("print(") || trimmed.hasPrefix("debugPrint(") || trimmed.hasPrefix("NSLog(") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .suggestion,
                        category: .codeHygiene,
                        title: "Leftover Debug Print (`print` / `NSLog`)",
                        detail: "Hapus `print` debug atau ganti dengan structured logger (`os.Logger`) sebelum merge PR.",
                        codeSnippet: trimmed
                    )
                )
            }

            // 9. Security: Insecure HTTP URL or hardcoded secret/token
            if trimmed.contains("\"http://") && !trimmed.contains("localhost") && !trimmed.contains("127.0.0.1") {
                findings.append(
                    CodeReviewFinding(
                        fileName: fileName,
                        lineNumber: lineNumber,
                        severity: .warning,
                        category: .security,
                        title: "Insecure HTTP URL (Non-HTTPS)",
                        detail: "Gunakan `https://` agar komunikasi jaringan terenkripsi dan lolos App Transport Security (ATS).",
                        codeSnippet: trimmed
                    )
                )
            }
        }

        return findings
    }

    public static func sortFindings(_ findings: [CodeReviewFinding]) -> [CodeReviewFinding] {
        findings.sorted { lhs, rhs in
            if lhs.severity.priorityRank != rhs.severity.priorityRank {
                return lhs.severity.priorityRank < rhs.severity.priorityRank
            }
            if lhs.isNew != rhs.isNew {
                return lhs.isNew && !rhs.isNew
            }
            if lhs.detectedAt != rhs.detectedAt {
                return lhs.detectedAt > rhs.detectedAt
            }
            if lhs.fileName != rhs.fileName {
                return lhs.fileName < rhs.fileName
            }
            return lhs.lineNumber < rhs.lineNumber
        }
    }

    public func analyzeDirectory(
        at url: URL,
        maxFiles: Int = 500,
        previousFindingIDs: Set<String> = []
    ) -> [CodeReviewFinding] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let skippedDirectories: Set<String> = [".build", "Pods", "DerivedData", ".git"]
        var allFindings: [CodeReviewFinding] = []
        var fileModDates: [String: Date] = [:]
        var scanned = 0
        for case let fileURL as URL in enumerator {
            guard scanned < maxFiles else { break }
            if skippedDirectories.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard fileURL.pathExtension == "swift" else { continue }

            if let source = try? String(contentsOf: fileURL, encoding: .utf8) {
                let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(timeIntervalSince1970: 0)
                let fileName = fileURL.lastPathComponent
                let fileFindings = analyze(source: source, fileName: fileName).map { item -> CodeReviewFinding in
                    var copy = item
                    copy.detectedAt = mtime
                    if !previousFindingIDs.isEmpty {
                        copy.isNew = !previousFindingIDs.contains(item.id)
                    }
                    return copy
                }
                if !fileFindings.isEmpty {
                    fileModDates[fileName] = mtime
                    allFindings.append(contentsOf: fileFindings)
                }
                scanned += 1
            }
        }

        if previousFindingIDs.isEmpty && !fileModDates.isEmpty {
            let newestFiles = Set(
                fileModDates
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .filter { $0.value > Date(timeIntervalSince1970: 0) }
                    .map(\.key)
            )
            if !newestFiles.isEmpty {
                allFindings = allFindings.map { item in
                    var copy = item
                    if newestFiles.contains(item.fileName) {
                        copy.isNew = true
                    }
                    return copy
                }
            }
        }

        return Self.sortFindings(allFindings)
    }

    // MARK: - Git Branch PR Comparison & Per-Module Discovery

    public func listGitBranches(in projectURL: URL) async -> (current: String, branches: [String]) {
        let headOut = try? await runner.run("/usr/bin/git", arguments: ["rev-parse", "--abbrev-ref", "HEAD"], workingDirectory: projectURL)
        let current = headOut?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "main"
        let branchOut = try? await runner.run("/usr/bin/git", arguments: ["branch", "-a", "--format=%(refname:short)"], workingDirectory: projectURL)
        return Self.parseGitBranches(from: branchOut?.stdout ?? "", currentBranch: current)
    }

    public static func parseGitBranches(from stdout: String, currentBranch: String) -> (current: String, branches: [String]) {
        var seen = Set<String>()
        var list: [String] = []
        let cleanCurrent = currentBranch.isEmpty ? "main" : currentBranch
        if seen.insert(cleanCurrent).inserted {
            list.append(cleanCurrent)
        }
        for raw in stdout.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.contains("HEAD"),
                  trimmed != "origin"
            else { continue }
            if seen.insert(trimmed).inserted {
                list.append(trimmed)
            }
        }
        for fallback in ["main", "develop", "master"] where seen.insert(fallback).inserted {
            list.append(fallback)
        }
        return (cleanCurrent, list)
    }

    public static func filterBranches(
        _ branches: [String],
        kind: GitBranchFilterKind,
        query: String,
        currentBranch: String
    ) -> [String] {
        let commonNames: Set<String> = ["main", "master", "develop", "development", "staging", "production", "origin/main", "origin/develop", "origin/master"]
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let byKind = branches.filter { branch in
            let isRemote = branch.hasPrefix("origin/") || branch.hasPrefix("remotes/")
            switch kind {
            case .all:
                return true
            case .local:
                return !isRemote
            case .remote:
                return isRemote
            case .common:
                let lower = branch.lowercased()
                return branch == currentBranch
                    || commonNames.contains(lower)
                    || lower.hasPrefix("release/")
                    || lower.hasPrefix("origin/release/")
            }
        }

        let byQuery: [String] = if q.isEmpty {
            byKind
        } else {
            byKind.filter { SmartSearchMatcher.matches([$0], query: q) }
        }

        return byQuery.sorted { lhs, rhs in
            if (lhs == currentBranch) != (rhs == currentBranch) {
                return lhs == currentBranch
            }
            let lhsCommon = commonNames.contains(lhs.lowercased())
            let rhsCommon = commonNames.contains(rhs.lowercased())
            if lhsCommon != rhsCommon {
                return lhsCommon
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    public static func groupFindingsByFile(_ findings: [CodeReviewFinding]) -> [CodeReviewFileGroup] {
        let grouped = Dictionary(grouping: findings, by: \.fileName)
        let groups = grouped.map { fileName, items in
            let sortedItems = items.sorted {
                if $0.severity.priorityRank != $1.severity.priorityRank {
                    return $0.severity.priorityRank < $1.severity.priorityRank
                }
                return $0.lineNumber < $1.lineNumber
            }
            return CodeReviewFileGroup(fileName: fileName, findings: sortedItems)
        }
        return groups.sorted { lhs, rhs in
            if (lhs.criticalCount > 0) != (rhs.criticalCount > 0) {
                return lhs.criticalCount > 0
            }
            if lhs.hasNew != rhs.hasNew {
                return lhs.hasNew && !rhs.hasNew
            }
            if lhs.criticalCount != rhs.criticalCount {
                return lhs.criticalCount > rhs.criticalCount
            }
            if lhs.latestDetectedAt != rhs.latestDetectedAt {
                return lhs.latestDetectedAt > rhs.latestDetectedAt
            }
            return lhs.fileName < rhs.fileName
        }
    }

    public static func splitModuleDisplay(_ modulePath: String) -> (leafName: String, parentPath: String?) {
        let trimmed = modulePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return (modulePath, nil) }
        let ns = trimmed as NSString
        let leaf = ns.lastPathComponent
        let parent = ns.deletingLastPathComponent
        return (leaf.isEmpty ? trimmed : leaf, parent.isEmpty ? nil : parent)
    }

    public static func filterModules(_ modules: [String], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return modules }
        let leafQuery = q.lowercased()
        return modules
            .filter { SmartSearchMatcher.matches([$0, ($0 as NSString).lastPathComponent], query: q) }
            .sorted { lhs, rhs in
                let lhsScore = moduleMatchScore(lhs, lowerQuery: leafQuery)
                let rhsScore = moduleMatchScore(rhs, lowerQuery: leafQuery)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                let lhsDepth = lhs.split(separator: "/").count
                let rhsDepth = rhs.split(separator: "/").count
                if lhsDepth != rhsDepth {
                    return lhsDepth < rhsDepth
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    private static func moduleMatchScore(_ modulePath: String, lowerQuery: String) -> Int {
        let leaf = (modulePath as NSString).lastPathComponent.lowercased()
        if leaf == lowerQuery {
            return 1000
        } else if leaf.hasPrefix(lowerQuery) {
            return 800
        } else if leaf.contains(lowerQuery) {
            return 600
        }
        return 300
    }

    public func listProjectModules(in projectURL: URL) -> [String] {
        let skippedDirs: Set<String> = [".build", "Pods", "DerivedData", ".git", ".swiftpm", "build", "dist", "Carthage", "node_modules"]
        let skippedExtensions: Set<String> = ["xcodeproj", "xcworkspace", "xcassets", "lproj", "bundle", "framework", "xcframework", "app"]
        let fm = FileManager.default
        let standardizedRoot = projectURL.standardizedFileURL
        let rootPathPrefix = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : (standardizedRoot.path + "/")

        guard let enumerator = fm.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var modules: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            if skippedDirs.contains(name) || skippedExtensions.contains(ext) {
                enumerator.skipDescendants()
                continue
            }
            let fullPath = url.standardizedFileURL.path
            if fullPath.hasPrefix(rootPathPrefix) {
                let rel = String(fullPath.dropFirst(rootPathPrefix.count))
                if !rel.isEmpty {
                    modules.append(rel)
                }
            }
        }
        return modules.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func directoryContainsSwiftFiles(at url: URL, maxDepth: Int) -> Bool {
        let baseComponents = url.pathComponents.count
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let fileURL as URL in enumerator {
            let depth = fileURL.pathComponents.count - baseComponents
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if fileURL.pathExtension == "swift" {
                return true
            }
        }
        return false
    }

    public func compareBranches(
        source: String,
        target: String,
        in projectURL: URL
    ) async -> GitBranchComparisonSummary {
        let range = (source == target) ? "HEAD" : "\(target)...\(source)"
        let logRange = (source == target) ? "-n 10" : "\(target)..\(source)"

        let logArgs = (source == target)
            ? ["log", "-n", "10", "--oneline"]
            : ["log", logRange, "--oneline", "-n", "30"]
        let logOut = try? await runner.run("/usr/bin/git", arguments: logArgs, workingDirectory: projectURL)
        let commits = (logOut?.stdout ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let diffOut = try? await runner.run(
            "/usr/bin/git",
            arguments: ["diff", "-U0", "--diff-filter=ACMR", range, "--", "*.swift"],
            workingDirectory: projectURL
        )
        var rawDiff = diffOut?.stdout ?? ""
        if rawDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Fallback to working tree + staged changes against HEAD
            let wtOut = try? await runner.run(
                "/usr/bin/git",
                arguments: ["diff", "-U0", "HEAD", "--", "*.swift"],
                workingDirectory: projectURL
            )
            rawDiff = wtOut?.stdout ?? ""
        }

        let changedMap = Self.parseUnifiedDiffChangedLines(from: rawDiff)
        let changedFiles = changedMap.keys.sorted()

        return GitBranchComparisonSummary(
            sourceBranch: source,
            targetBranch: target,
            commits: commits,
            changedSwiftFiles: changedFiles,
            changedLinesByFile: changedMap
        )
    }

    public static func parseUnifiedDiffChangedLines(from diffOutput: String) -> [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        var currentFile: String?
        let hunkRegex = try? NSRegularExpression(pattern: #"^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,(\d+))?\s+@@"#)

        for rawLine in diffOutput.components(separatedBy: .newlines) {
            if rawLine.hasPrefix("+++ b/") {
                let path = String(rawLine.dropFirst("+++ b/".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if path.hasSuffix(".swift") {
                    currentFile = path
                    if result[path] == nil {
                        result[path] = []
                    }
                } else {
                    currentFile = nil
                }
                continue
            }
            guard let file = currentFile, rawLine.hasPrefix("@@") else { continue }
            let ns = rawLine as NSString
            if let match = hunkRegex?.firstMatch(in: rawLine, range: NSRange(location: 0, length: ns.length)),
               let startLine = Int(ns.substring(with: match.range(at: 1))) {
                let count: Int = if match.range(at: 2).location != NSNotFound {
                    Int(ns.substring(with: match.range(at: 2))) ?? 1
                } else {
                    1
                }
                if count > 0 {
                    var set = result[file] ?? []
                    for line in startLine..<(startLine + count) {
                        set.insert(line)
                    }
                    result[file] = set
                }
            }
        }
        return result
    }

    public func analyzeBranchDiff(
        source: String,
        target: String,
        changedLinesOnly: Bool,
        in projectURL: URL,
        previousFindingIDs: Set<String> = []
    ) async -> (summary: GitBranchComparisonSummary, findings: [CodeReviewFinding]) {
        let summary = await compareBranches(source: source, target: target, in: projectURL)
        var findings: [CodeReviewFinding] = []
        let now = Date()

        for relPath in summary.changedSwiftFiles {
            let fileURL = projectURL.appendingPathComponent(relPath)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            let allowed = changedLinesOnly ? summary.changedLinesByFile[relPath] : nil
            let fileFindings = analyze(source: content, fileName: fileURL.lastPathComponent, allowedLines: allowed).map { item -> CodeReviewFinding in
                var copy = item
                copy.detectedAt = mtime
                copy.isNew = previousFindingIDs.isEmpty || !previousFindingIDs.contains(item.id)
                return copy
            }
            findings.append(contentsOf: fileFindings)
        }

        return (summary, Self.sortFindings(findings))
    }

    public func formatMarkdownPRReport(
        scopeTitle: String,
        summary: GitBranchComparisonSummary?,
        findings: [CodeReviewFinding]
    ) -> String {
        let p0 = findings.filter { $0.severity == .critical }.count
        let p1 = findings.filter { $0.severity == .warning }.count
        let p2 = findings.filter { $0.severity == .suggestion }.count
        let status = p0 == 0 ? "READY TO MERGE (No P0 Blockers)" : "CHANGES REQUESTED (\(p0) P0 Blocker(s))"

        var lines: [String] = [
            "## DevCompanion Code Review Report",
            "- **Scope**: \(scopeTitle)",
            "- **Status**: **\(status)**",
            "- **Summary**: `\(p0) P0 Critical` | `\(p1) P1 Warning` | `\(p2) P2 Hygiene/Suggestion`"
        ]
        if let summary {
            lines.append("- **Branch Comparison**: `\(summary.sourceBranch)` -> `\(summary.targetBranch)` (\(summary.commits.count) commit(s), \(summary.changedSwiftFiles.count) Swift file(s) changed)")
        }
        lines.append("")
        if findings.isEmpty {
            lines.append("No issues detected in this review scope.")
        } else {
            lines.append("### Findings")
            for item in findings.prefix(40) {
                lines.append("- **[\(item.severity.priorityBadge) \(item.category.rawValue)]** `\(item.fileName):\(item.lineNumber)` - \(item.title)")
                lines.append("  - `\(item.codeSnippet)`")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum SmartSearchMatcher {
    /// Returns true if every whitespace-separated token in `query` matches (case-insensitive `contains`) across `fields`.
    public static func matches(_ fields: [String], query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
        guard !tokens.isEmpty else { return true }
        let haystack = fields.joined(separator: " ").lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

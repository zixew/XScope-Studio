import Foundation

public enum AgentProviderKind: String, CaseIterable, Sendable, Identifiable {
    case offlineRules = "Offline Rules"
    case ollamaLocal = "Ollama (Local)"
    case geminiCloud = "Gemini (BYOK)"
    case antigravityPrompt = "Antigravity Prompt"

    public var id: String { rawValue }
}

public struct TokenEfficiencyStats: Sendable, Equatable {
    public let compactTokens: Int
    public let verboseTokens: Int
    public let savedTokens: Int
    public let savedPercent: Int
    public let deduplicatedCount: Int
    public let localFixCount: Int

    public init(
        compactTokens: Int,
        verboseTokens: Int,
        deduplicatedCount: Int = 0,
        localFixCount: Int = 0
    ) {
        self.compactTokens = max(1, compactTokens)
        self.verboseTokens = max(self.compactTokens, verboseTokens)
        self.savedTokens = max(0, self.verboseTokens - self.compactTokens)
        self.savedPercent = self.verboseTokens > 0
            ? Int((Double(self.savedTokens) / Double(self.verboseTokens) * 100.0).rounded())
            : 0
        self.deduplicatedCount = deduplicatedCount
        self.localFixCount = localFixCount
    }
}

public struct AgentFixProposal: Sendable, Equatable {
    public let diagnosis: String
    public let manualSteps: [String]
    public let oldSnippet: String
    public let newSnippet: String
    public let filePath: String?
    public let lineNumber: Int

    public init(
        diagnosis: String,
        manualSteps: [String],
        oldSnippet: String,
        newSnippet: String,
        filePath: String?,
        lineNumber: Int
    ) {
        self.diagnosis = diagnosis
        self.manualSteps = manualSteps
        self.oldSnippet = oldSnippet
        self.newSnippet = newSnippet
        self.filePath = filePath
        self.lineNumber = lineNumber
    }
}

public struct PlannedFileOperation: Identifiable, Sendable, Equatable {
    public enum ActionKind: String, Sendable {
        case newFile = "NEW FILE"
        case updateFile = "UPDATE"
    }

    public let id: String
    public let action: ActionKind
    public var relativePath: String
    public let summary: String

    public init(action: ActionKind, relativePath: String, summary: String) {
        self.id = "\(action.rawValue)::\(relativePath)"
        self.action = action
        self.relativePath = relativePath
        self.summary = summary
    }
}

public struct PatchRevertRecord: Sendable, Equatable {
    public let fileURL: URL
    public let originalContent: String

    public init(fileURL: URL, originalContent: String) {
        self.fileURL = fileURL
        self.originalContent = originalContent
    }
}

public struct UnitTestPlacementPlan: Sendable, Equatable {
    public var targetName: String
    public var operations: [PlannedFileOperation]
    public var generatedCode: String

    public init(targetName: String, operations: [PlannedFileOperation], generatedCode: String) {
        self.targetName = targetName
        self.operations = operations
        self.generatedCode = generatedCode
    }
}

public enum XcodeProjectContainerKind: String, Sendable, Equatable {
    case xcworkspace = "CocoaPods / Workspace (.xcworkspace)"
    case xcodeproj = "Xcode Project (.xcodeproj)"
    case swiftPackage = "Swift Package (Package.swift)"
    case directory = "Project Folder"
}

public struct XcodeProjectContainer: Sendable, Equatable {
    public let url: URL
    public let kind: XcodeProjectContainerKind

    public init(url: URL, kind: XcodeProjectContainerKind) {
        self.url = url
        self.kind = kind
    }
}

/// Provides Xcode jump-to-line (`xed`), Dual-Mode Agent diagnosis/patching, and 3-Step Unit Test Placement Plans.
public struct AgentService: Sendable {
    private let runner: any CommandExecuting

    public init(runner: any CommandExecuting = ProcessRunner()) {
        self.runner = runner
    }

    /// Resolves the best Xcode project container in `projectURL` by priority:
    /// 1. `.xcworkspace` (CocoaPods / Workspace, excluding internal `.xcodeproj/project.xcworkspace`)
    /// 2. `.xcodeproj` (Standard Xcode Project)
    /// 3. `Package.swift` (Default SwiftPM Project)
    /// 4. Fallback to `projectURL` directory.
    public static func resolveXcodeContainer(in projectURL: URL) -> XcodeProjectContainer {
        let fm = FileManager.default
        let skippedDirs: Set<String> = ["Pods", ".build", "DerivedData", ".git", ".swiftpm"]

        func scanEntries(in dir: URL) -> (workspaces: [URL], projects: [URL], packageSwift: URL?) {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return ([], [], nil) }

            let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
            let workspaces = sorted.filter {
                $0.pathExtension == "xcworkspace"
                    && $0.lastPathComponent != "project.xcworkspace"
                    && !$0.path.contains(".xcodeproj/")
            }
            let projects = sorted.filter { $0.pathExtension == "xcodeproj" }
            let pkg = sorted.first { $0.lastPathComponent == "Package.swift" }
            return (workspaces, projects, pkg)
        }

        let rootScan = scanEntries(in: projectURL)
        if let ws = rootScan.workspaces.first {
            return XcodeProjectContainer(url: ws, kind: .xcworkspace)
        }
        if let proj = rootScan.projects.first {
            return XcodeProjectContainer(url: proj, kind: .xcodeproj)
        }
        if let pkg = rootScan.packageSwift {
            return XcodeProjectContainer(url: pkg, kind: .swiftPackage)
        }

        // Shallow 1st-level subdirectory check if root is a wrapper folder
        if let subDirs = try? fm.contentsOfDirectory(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            var subWorkspaces: [URL] = []
            var subProjects: [URL] = []
            var subPackages: [URL] = []

            for sub in subDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !skippedDirs.contains(sub.lastPathComponent),
                      (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { continue }
                let scan = scanEntries(in: sub)
                subWorkspaces.append(contentsOf: scan.workspaces)
                subProjects.append(contentsOf: scan.projects)
                if let pkg = scan.packageSwift { subPackages.append(pkg) }
            }

            if let ws = subWorkspaces.first {
                return XcodeProjectContainer(url: ws, kind: .xcworkspace)
            }
            if let proj = subProjects.first {
                return XcodeProjectContainer(url: proj, kind: .xcodeproj)
            }
            if let pkg = subPackages.first {
                return XcodeProjectContainer(url: pkg, kind: .swiftPackage)
            }
        }

        return XcodeProjectContainer(url: projectURL, kind: .directory)
    }

    /// Checks whether Xcode is currently running AND already has `container` / `projectURL` open.
    public func isXcodeWorkspaceOpen(for container: XcodeProjectContainer, projectURL: URL) async -> Bool {
        guard let pgrepOut = try? await runner.run("/usr/bin/pgrep", arguments: ["-x", "Xcode"], workingDirectory: nil),
              pgrepOut.isSuccess,
              !pgrepOut.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        let targetApp = (await resolveXcodeAppPath()) ?? "Xcode"
        let escapedApp = targetApp.replacingOccurrences(of: "\"", with: "\\\"")
        guard let osaOut = try? await runner.run(
            "/usr/bin/osascript",
            arguments: ["-e", "tell application \"\(escapedApp)\" to get path of workspace documents"],
            workingDirectory: nil
        ),
        osaOut.isSuccess
        else { return false }

        let openPaths = osaOut.stdout.lowercased()
        let containerPath = container.url.path.lowercased()
        let projectPath = projectURL.path.lowercased()
        let containerStem = container.url.deletingPathExtension().lastPathComponent.lowercased()

        return openPaths.contains(containerPath)
            || openPaths.contains(projectPath)
            || (!containerStem.isEmpty && containerStem != "package" && openPaths.contains(containerStem))
    }

    public func openInXcode(
        filePath: String,
        line: Int,
        projectURL: URL? = nil,
        waitBeforeFileJumpMs: Int = 1200
    ) async throws -> CommandOutput {
        if let projectURL {
            let container = Self.resolveXcodeContainer(in: projectURL)
            let alreadyOpen = await isXcodeWorkspaceOpen(for: container, projectURL: projectURL)
            if !alreadyOpen {
                let targetPath = (container.kind == .swiftPackage)
                    ? container.url.deletingLastPathComponent().path
                    : container.url.path
                let containerOut = try? await runner.run("/usr/bin/xed", arguments: [targetPath], workingDirectory: projectURL)
                if containerOut?.isSuccess != true {
                    if let appPath = await resolveXcodeAppPath(),
                       let osaContainer = await openViaAppleScript(appPath: appPath, targetPath: targetPath, line: nil, workingDirectory: projectURL),
                       osaContainer.isSuccess {
                        // Opened via AppleScript
                    } else {
                        let bundleOpen = try? await runner.run("/usr/bin/open", arguments: ["-b", "com.apple.dt.Xcode", targetPath], workingDirectory: projectURL)
                        if bundleOpen?.isSuccess != true, let appPath = await resolveXcodeAppPath() {
                            _ = try? await runner.run("/usr/bin/open", arguments: ["-a", appPath, targetPath], workingDirectory: projectURL)
                        }
                    }
                }
                if waitBeforeFileJumpMs > 0 {
                    try? await Task.sleep(for: .milliseconds(waitBeforeFileJumpMs))
                }
            }
        }
        let targetLine = max(1, line)
        let xedOut = try await runner.run("/usr/bin/xed", arguments: ["--line", "\(targetLine)", filePath], workingDirectory: projectURL)
        if xedOut.isSuccess {
            let activateOut = try? await runner.run("/usr/bin/open", arguments: ["-b", "com.apple.dt.Xcode"], workingDirectory: nil)
            if activateOut?.isSuccess != true, let appPath = await resolveXcodeAppPath() {
                let appActivate = try? await runner.run("/usr/bin/open", arguments: ["-a", appPath], workingDirectory: nil)
                if appActivate?.isSuccess != true {
                    _ = try? await runner.run("/usr/bin/osascript", arguments: ["-e", "tell application \"\(appPath)\" to activate"], workingDirectory: nil)
                }
            }
            return xedOut
        }
        // When xed fails (e.g. Xcodes.app / Xcode-26.2.0.app), prefer AppleScript FIRST so IDEScriptingHack jumps to targetLine!
        if let appPath = await resolveXcodeAppPath(),
           let osaOut = await openViaAppleScript(appPath: appPath, targetPath: filePath, line: targetLine, workingDirectory: projectURL),
           osaOut.isSuccess {
            return osaOut
        }
        let bundleOut = try await runner.run("/usr/bin/open", arguments: ["-b", "com.apple.dt.Xcode", filePath], workingDirectory: projectURL)
        if !bundleOut.isSuccess, let appPath = await resolveXcodeAppPath() {
            return try await runner.run("/usr/bin/open", arguments: ["-a", appPath, filePath], workingDirectory: projectURL)
        }
        return bundleOut
    }

    private func openViaAppleScript(appPath: String, targetPath: String, line: Int?, workingDirectory: URL?) async -> CommandOutput? {
        let escapedApp = appPath.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTarget = targetPath.replacingOccurrences(of: "\"", with: "\\\"")
        guard let targetLine = line, targetLine > 0 else {
            return try? await runner.run(
                "/usr/bin/osascript",
                arguments: [
                    "-e", "tell application \"\(escapedApp)\" to activate",
                    "-e", "tell application \"\(escapedApp)\" to open POSIX file \"\(escapedTarget)\""
                ],
                workingDirectory: workingDirectory
            )
        }

        let script = """
        tell application "\(escapedApp)"
            set targetPath to "\(escapedTarget)"
            open POSIX file targetPath
            activate
            repeat 15 times
                try
                    set docList to (every source document whose path is targetPath)
                    if (count of docList) > 0 then
                        set targetDoc to item 1 of docList
                        hack document targetDoc start \(targetLine) stop \(targetLine)
                        set selected paragraph range of targetDoc to {\(targetLine), \(targetLine)}
                        return
                    end if
                end try
                delay 0.1
            end repeat
            try
                tell front source document
                    hack document it start \(targetLine) stop \(targetLine)
                    set selected paragraph range to {\(targetLine), \(targetLine)}
                end tell
            end try
        end tell
        """
        return try? await runner.run(
            "/usr/bin/osascript",
            arguments: ["-e", script],
            workingDirectory: workingDirectory
        )
    }

    private func resolveXcodeAppPath() async -> String? {
        if let devOut = try? await runner.run("/usr/bin/xcode-select", arguments: ["-p"], workingDirectory: nil),
           devOut.isSuccess {
            let devPath = devOut.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if devPath.hasSuffix("/Contents/Developer") {
                let appPath = String(devPath.dropLast("/Contents/Developer".count))
                if FileManager.default.fileExists(atPath: appPath) {
                    return appPath
                }
            }
        }
        if let apps = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") {
            if let match = apps.sorted().first(where: { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }) {
                return "/Applications/\(match)"
            }
        }
        return nil
    }

    public func proposeFix(
        for finding: CodeReviewFinding,
        filePath: String? = nil,
        provider: AgentProviderKind = .offlineRules,
        apiKey: String = "",
        ollamaModel: String = "qwen2.5-coder:7b"
    ) async -> AgentFixProposal {
        if provider == .antigravityPrompt {
            let deterministic = deterministicFix(for: finding, filePath: filePath)
            let prompt = buildAntigravityPrompt(for: finding, filePath: filePath)
            return AgentFixProposal(
                diagnosis: deterministic.diagnosis,
                manualSteps: [prompt],
                oldSnippet: deterministic.oldSnippet,
                newSnippet: deterministic.newSnippet,
                filePath: filePath,
                lineNumber: finding.lineNumber
            )
        } else if provider == .ollamaLocal {
            if let aiText = await queryOllama(
                prompt: "Fix this Swift UIKit/SwiftUI issue concisely and provide the replacement line only:\n\(finding.title)\n\(finding.codeSnippet)",
                model: ollamaModel
            ) {
                let cleaned = Self.stripMarkdownFences(aiText)
                return AgentFixProposal(
                    diagnosis: finding.detail,
                    manualSteps: deterministicFix(for: finding, filePath: filePath).manualSteps,
                    oldSnippet: finding.codeSnippet,
                    newSnippet: cleaned,
                    filePath: filePath,
                    lineNumber: finding.lineNumber
                )
            }
        } else if provider == .geminiCloud, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let aiText = await queryGemini(
                prompt: "Fix this Swift UIKit/SwiftUI issue concisely and provide the replacement line only:\n\(finding.title)\n\(finding.codeSnippet)",
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            ) {
                let cleaned = Self.stripMarkdownFences(aiText)
                return AgentFixProposal(
                    diagnosis: finding.detail,
                    manualSteps: deterministicFix(for: finding, filePath: filePath).manualSteps,
                    oldSnippet: finding.codeSnippet,
                    newSnippet: cleaned,
                    filePath: filePath,
                    lineNumber: finding.lineNumber
                )
            }
        }

        return deterministicFix(for: finding, filePath: filePath)
    }

    public func proposeCrashFix(
        for crash: CrashAnalysisReport,
        snippet: CrashSourceSnippet? = nil
    ) -> AgentFixProposal {
        let lineNum = snippet?.lineNumber ?? crash.sourceLineNumber ?? 1
        let filePath = snippet?.filePath
        let oldLine = crash.offendingLineCode?.trimmingCharacters(in: .whitespaces)
            ?? Self.extractArrowLine(from: snippet?.snippet)
            ?? "// \(crash.culpritSymbol)"

        let newLine: String
        let steps: [String]
        if oldLine.contains("try!") {
            newLine = oldLine.replacingOccurrences(of: "try!", with: "try?")
            steps = [
                "Ganti `try!` dengan `try?` atau blok `do/catch` agar error runtime tidak menyebabkan force-close.",
                "Tangani nilai `nil` atau fallback secara aman sebelum melanjutkan alur UI."
            ]
        } else if oldLine.contains("as!") {
            newLine = oldLine.replacingOccurrences(of: "as!", with: "as?")
            steps = [
                "Ganti forced cast `as!` dengan conditional cast `guard let ... = ... as? ... else { return }`.",
                "Pastikan tipe data sesuai sebelum mengakses properti subclass."
            ]
        } else if oldLine.contains("Data(contentsOf:") {
            newLine = "// Move synchronous I/O off the main thread:\nTask.detached { \(oldLine) }"
            steps = [
                "Pindahkan `Data(contentsOf:)` atau I/O sinkron ke `Task.detached` / `URLSession.shared.data(from:)`.",
                "Update UI kembali di `@MainActor` setelah data selesai diunduh."
            ]
        } else if oldLine.contains("fatalError(") || oldLine.contains("preconditionFailure(") {
            newLine = "assertionFailure(\"Handled recoverable state safely\"); return"
            steps = [
                "Hindari `fatalError` di jalur produksi; gunakan `assertionFailure` dan early `return`.",
                "Log state error untuk observabilitas tanpa mematikan aplikasi."
            ]
        } else if oldLine.contains("!") && !oldLine.contains("!=") {
            newLine = oldLine.replacingOccurrences(of: "!", with: "?")
            steps = [
                "Ganti force-unwrap (`!`) dengan optional chaining (`?`) atau `guard let`.",
                "Pastikan referensi objek/IBOutlet sudah terinisialisasi saat fungsi dipanggil."
            ]
        } else {
            newLine = "// Safe guard around crash site:\n\(oldLine)"
            steps = [
                "Periksa validitas state dan nil-safety pada `\(crash.sourceFileName ?? crash.processName):\(lineNum)`.",
                "Tambahkan `guard` check sebelum memanggil `\(crash.culpritSymbol)`."
            ]
        }

        return AgentFixProposal(
            diagnosis: "\(crash.humanExplanation). \(crash.whenAction).",
            manualSteps: steps,
            oldSnippet: oldLine,
            newSnippet: newLine,
            filePath: filePath,
            lineNumber: lineNum
        )
    }

    private static func extractArrowLine(from formattedSnippet: String?) -> String? {
        guard let formattedSnippet else { return nil }
        for line in formattedSnippet.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("→"), let pipe = trimmed.range(of: "|") {
                return trimmed[pipe.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    public func buildAntigravityPrompt(for finding: CodeReviewFinding, filePath: String?) -> String {
        let location = filePath ?? finding.fileName
        return """
        Fix \(finding.category.rawValue) (\(finding.severity.rawValue)) in `\(location):\(finding.lineNumber)`:
        - Issue: \(finding.title)
        - Detail: \(finding.detail)
        - Offending code:
        ```swift
        \(finding.codeSnippet)
        ```
        Please provide a minimal, safe fix preserving surrounding behavior.
        """
    }

    public func estimateTokens(_ text: String) -> Int {
        max(1, (text.count + 3) / 4)
    }

    public func buildCompactFindingPrompt(for finding: CodeReviewFinding, filePath: String?) -> String {
        let location = filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? finding.fileName
        let snippet = finding.codeSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Fix \(finding.severity.rawValue) \(finding.category.rawValue) \(location):\(finding.lineNumber) — \(finding.title).
        ```swift
        \(snippet)
        ```
        Unified diff only.
        """
    }

    public func buildCompactRealtimeLeaksSummaryPrompt(
        findings: [CodeReviewFinding],
        freezes: [FreezeLagEvent],
        crash: CrashAnalysisReport?,
        snippet: CrashSourceSnippet?
    ) -> (prompt: String, stats: TokenEfficiencyStats) {
        var localFixCount = 0
        var aiFindings: [CodeReviewFinding] = []
        var seenFindingKeys: Set<String> = []
        var deduplicatedCount = 0

        for f in findings {
            let fix = deterministicFix(for: f, filePath: nil)
            if fix.newSnippet != fix.oldSnippet {
                localFixCount += 1
                continue
            }
            let key = "\(f.fileName)|\(f.title)"
            if seenFindingKeys.insert(key).inserted {
                aiFindings.append(f)
            } else {
                deduplicatedCount += 1
            }
        }

        var uniqueFreezes: [FreezeLagEvent] = []
        var seenFreezeKeys: Set<String> = []
        for ev in freezes {
            let fileLabel = ev.fileName ?? "Unknown"
            let key = "\(fileLabel)|\(ev.culpritSymbol)"
            if seenFreezeKeys.insert(key).inserted {
                uniqueFreezes.append(ev)
            } else {
                deduplicatedCount += 1
            }
        }

        var lines: [String] = [
            "Fix realtime iOS leaks/hangs. Output minimal unified diffs only."
        ]

        for f in aiFindings.prefix(10) {
            let code = f.codeSnippet.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            lines.append("F|\(f.fileName):\(f.lineNumber)|\(f.severity.rawValue)|\(f.title)|\(code.prefix(120))")
        }

        for ev in uniqueFreezes.prefix(5) {
            let dur = String(format: "%.1fs", ev.durationSeconds)
            let loc = ev.fileName.map { "\($0):\(ev.lineNumber ?? 1)" } ?? "runtime"
            lines.append("H|\(loc)|\(dur)|\(Int(ev.peakCPUPercent))%|\(ev.culpritSymbol)")
        }

        if let crash {
            let loc = snippet.map { "\($0.fileName):\($0.lineNumber)" }
                ?? crash.sourceFileName.map { "\($0):\(crash.sourceLineNumber ?? 1)" }
                ?? crash.processName
            lines.append("C|\(loc)|\(crash.exceptionType)|\(crash.culpritSymbol)")
            if let snippet {
                let compactSnippet = snippet.snippet
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .prefix(8)
                    .joined(separator: "\n")
                lines.append("```swift\n\(compactSnippet)\n```")
            }
        }

        let compactPrompt = lines.joined(separator: "\n")

        // Baseline verbose cost if sending each finding + crash separately
        var verboseChars = 0
        for f in findings.prefix(15) {
            verboseChars += buildAntigravityPrompt(for: f, filePath: nil).count
        }
        for ev in freezes.prefix(8) {
            let loc = ev.fileName.map { "\($0):\(ev.lineNumber ?? 1)" } ?? "runtime"
            verboseChars += "Diagnose freeze in \(loc) (\(ev.durationSeconds)s, \(ev.peakCPUPercent)% CPU) symbol \(ev.culpritSymbol). Provide full explanation and fix.\n".count
        }
        if let crash {
            verboseChars += buildAntigravityCrashPrompt(crash: crash, snippet: snippet).count
        }
        if verboseChars == 0 {
            verboseChars = compactPrompt.count
        }

        let compactTokens = estimateTokens(compactPrompt)
        let verboseTokens = max(compactTokens, (verboseChars + 3) / 4)
        let stats = TokenEfficiencyStats(
            compactTokens: compactTokens,
            verboseTokens: verboseTokens,
            deduplicatedCount: deduplicatedCount,
            localFixCount: localFixCount
        )
        return (compactPrompt, stats)
    }

    public func buildAntigravityCrashPrompt(crash: CrashAnalysisReport, snippet: CrashSourceSnippet?) -> String {
        let location = snippet.map { "\($0.filePath):\($0.lineNumber)" }
            ?? crash.sourceFileName.map { "\($0):\(crash.sourceLineNumber ?? 1)" }
            ?? crash.processName
        let codeBlock = snippet.map { "\nOffending source code:\n```swift\n\($0.snippet)\n```" } ?? ""
        return """
        Diagnose and fix force-close crash in `\(location)`:
        - Process: \(crash.processName)
        - Exception: \(crash.exceptionType) (\(crash.crashedThread))
        - Termination: \(crash.terminationReason)
        - Culprit frame: \(crash.culpritSymbol)\(codeBlock)
        Please explain the root cause and apply a safe fix.
        """
    }

    public func buildAntigravityUnitTestPrompt(
        sourceCode: String,
        fileName: String,
        moduleName: String,
        framework: TestFrameworkKind,
        targetPath: String?,
        dependencyContext: String = "",
        targetCoveragePercent: Int = 80
    ) -> String {
        let target = targetPath ?? "Tests/\(moduleName)Tests"
        let depSection = dependencyContext.isEmpty ? "" : """
        - Cross-file dependencies & collaborator functions to mock/stub:
        \(dependencyContext)
        """
        return """
        Write comprehensive \(framework.rawValue) unit tests for `\(fileName)` (module `\(moduleName)`) targeting >= \(targetCoveragePercent)% line coverage:
        - Target path: `\(target)`
        - Cover positive cases, negative/error paths, and edge cases with mock protocols.
        \(depSection)- Source code:
        ```swift
        \(sourceCode)
        ```
        """
    }

    public func buildAntigravityL10nPrompt(missingEntries: [LocalizationMissingEntry], projectName: String?) -> String {
        let proj = projectName ?? "Xcode Project"
        let items = missingEntries.prefix(30).map { "- `\($0.key)`: missing [\($0.missingLanguages.joined(separator: ", "))]" }.joined(separator: "\n")
        return """
        Complete missing `.xcstrings` translations for `\(proj)` (\(missingEntries.count) incomplete keys):
        \(items)
        Please provide accurate, natural translations for each missing language in `Localizable.xcstrings`.
        """
    }

    public func deterministicFix(for finding: CodeReviewFinding, filePath: String?) -> AgentFixProposal {
        let snippet = finding.codeSnippet
        var replacement = snippet
        var steps: [String] = []

        if finding.category == .memoryLeak, snippet.contains("{") {
            replacement = snippet.replacingOccurrences(of: "{", with: "{ [weak self] in\n    guard let self else { return }")
            steps = [
                "Tambahkan capture list `[weak self]` pada pembuka closure.",
                "Unwrap dengan `guard let self else { return }` sebelum mengakses properti atau method `self`.",
                "Verifikasi di Xcode Memory Graph / Instruments bahwa `deinit` terpanggil saat layar ditutup."
            ]
        } else if finding.category == .mainThread {
            steps = [
                "Pindahkan operasi sinkron/berat ke background queue atau Swift Concurrency `Task.detached` / `URLSession.shared.data(from:)`.",
                "Update UI (`UIView` / `@State`) kembali di `@MainActor` atau `DispatchQueue.main.async`.",
                "Uji ulang dengan Time Profiler untuk memastikan main thread tidak tertahan."
            ]
        } else if finding.category == .uiKit, snippet.contains("var delegate:") || snippet.contains("var dataSource:") {
            replacement = snippet
                .replacingOccurrences(of: "var delegate:", with: "weak var delegate:")
                .replacingOccurrences(of: "var dataSource:", with: "weak var dataSource:")
            steps = [
                "Pastikan protocol delegate/dataSource mewarisi `AnyObject` (contoh: `protocol ProfileDelegate: AnyObject`).",
                "Ubah deklarasi properti menjadi `weak var` agar tidak terjadi strong reference cycle."
            ]
        } else if finding.category == .codeHygiene, snippet.hasPrefix("print(") || snippet.hasPrefix("debugPrint(") || snippet.hasPrefix("NSLog(") {
            replacement = "// \(snippet)"
            steps = [
                "Hapus atau komentari `print` / `NSLog` debug sebelum merge Pull Request.",
                "Gunakan `os.Logger` jika log tetap diperlukan di build produksi."
            ]
        } else if finding.category == .security, snippet.contains("http://") {
            replacement = snippet.replacingOccurrences(of: "http://", with: "https://")
            steps = [
                "Ubah skema URL dari `http://` menjadi `https://` agar terenkripsi dengan TLS.",
                "Pastikan endpoint backend mendukung HTTPS sesuai aturan App Transport Security."
            ]
        } else if finding.category == .swiftUI, snippet.contains("@ObservedObject") {
            replacement = snippet.replacingOccurrences(of: "@ObservedObject", with: "@StateObject")
            steps = [
                "Ganti `@ObservedObject` menjadi `@StateObject` (atau `@State` untuk `@Observable`) pada view pemilik instance.",
                "Biarkan child view tetap memakai `@ObservedObject` tanpa inisialisasi langsung."
            ]
        } else if snippet.contains("try!") {
            replacement = snippet.replacingOccurrences(of: "try!", with: "try?")
            steps = [
                "Ganti `try!` dengan blok `do { ... } catch { ... }` atau `try?`.",
                "Tangani state error di UI agar aplikasi tidak crash."
            ]
        } else {
            steps = [
                "Buka file di baris \(finding.lineNumber) menggunakan tombol Open in Xcode.",
                "Terapkan pola aman sesuai kategori \(finding.category.rawValue)."
            ]
        }

        return AgentFixProposal(
            diagnosis: finding.detail,
            manualSteps: steps,
            oldSnippet: snippet,
            newSnippet: replacement,
            filePath: filePath,
            lineNumber: finding.lineNumber
        )
    }

    public func applyPatch(
        to fileURL: URL,
        oldSnippet: String,
        newSnippet: String,
        lineNumber: Int? = nil
    ) throws -> PatchRevertRecord {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        guard oldSnippet != newSnippet else {
            throw CompanionError.patchMismatch(fileName: fileURL.lastPathComponent)
        }

        let updated: String
        if let lineNumber, lineNumber >= 1 {
            guard let targetRange = Self.findRange(of: oldSnippet, in: content, nearLine: lineNumber) else {
                throw CompanionError.patchMismatch(fileName: fileURL.lastPathComponent)
            }
            updated = content.replacingCharacters(in: targetRange, with: newSnippet)
        } else {
            guard content.contains(oldSnippet) else {
                throw CompanionError.patchMismatch(fileName: fileURL.lastPathComponent)
            }
            updated = content.replacingOccurrences(of: oldSnippet, with: newSnippet)
        }

        try updated.write(to: fileURL, atomically: true, encoding: .utf8)
        CompanionLog.agent.info("Applied patch to \(fileURL.lastPathComponent, privacy: .public)")
        return PatchRevertRecord(fileURL: fileURL, originalContent: content)
    }

    public func revertPatch(_ record: PatchRevertRecord) throws {
        try record.originalContent.write(to: record.fileURL, atomically: true, encoding: .utf8)
        CompanionLog.agent.info("Reverted patch on \(record.fileURL.lastPathComponent, privacy: .public)")
    }

    public func buildUnitTestPlan(
        source: String,
        sourceFileName: String = "FeatureViewModel.swift",
        projectURL: URL?,
        moduleName: String,
        framework: TestFrameworkKind
    ) -> UnitTestPlacementPlan {
        let studio = UnitTestStudio()
        let symbols = studio.parseSymbols(from: source)
        let generated = studio.generateTests(from: source, moduleName: moduleName, framework: framework)

        let baseName = sourceFileName.replacingOccurrences(of: ".swift", with: "")
        let targetName = "\(moduleName)Tests"
        let testRelPath = "Tests/\(targetName)/\(baseName)Tests.swift"
        let existsOnDisk = projectURL.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(testRelPath).path) } ?? false

        var ops: [PlannedFileOperation] = [
            PlannedFileOperation(
                action: existsOnDisk ? .updateFile : .newFile,
                relativePath: testRelPath,
                summary: "Target: \(targetName) • \(framework.rawValue) (\(symbols.count) symbol(s))"
            )
        ]

        let protocols = symbols.filter { $0.isProtocol }
        if !protocols.isEmpty {
            ops.append(
                PlannedFileOperation(
                    action: .updateFile,
                    relativePath: "Tests/\(targetName)/Mocks/Mock\(protocols[0].typeName).swift",
                    summary: "Protocol mock stub included in test suite"
                )
            )
        }

        return UnitTestPlacementPlan(targetName: targetName, operations: ops, generatedCode: generated)
    }

    public func writeApprovedTestPlan(_ plan: UnitTestPlacementPlan, projectURL: URL) throws -> URL {
        guard let primary = plan.operations.first else {
            throw CompanionError.fileNotFound(path: projectURL.path)
        }
        let destURL = projectURL.appendingPathComponent(primary.relativePath)
        try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plan.generatedCode.write(to: destURL, atomically: true, encoding: .utf8)

        for operation in plan.operations.dropFirst() {
            let opURL = projectURL.appendingPathComponent(operation.relativePath)
            try FileManager.default.createDirectory(at: opURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: opURL.path) {
                let stub = "// \(operation.summary)\n// Companion file for \(primary.relativePath)\n"
                try stub.write(to: opURL, atomically: true, encoding: .utf8)
            }
        }
        return destURL
    }

    // MARK: - Patch & Text Helpers

    private static func findRange(of snippet: String, in content: String, nearLine lineNumber: Int) -> Range<String.Index>? {
        var lineStart = content.startIndex
        var currentLine = 1
        while currentLine < lineNumber, lineStart < content.endIndex {
            if let newlineRange = content.range(of: "\n", range: lineStart..<content.endIndex) {
                lineStart = newlineRange.upperBound
                currentLine += 1
            } else {
                lineStart = content.endIndex
                break
            }
        }

        // First try searching from the target line (or 1 line before for slight line drift)
        let searchStart: String.Index
        if lineNumber > 1 {
            let prev = content[..<lineStart].lastIndex(of: "\n").map { content.index(after: $0) } ?? content.startIndex
            searchStart = prev
        } else {
            searchStart = lineStart
        }

        if let range = content.range(of: snippet, range: searchStart..<content.endIndex) {
            return range
        }
        return content.range(of: snippet)
    }

    static func stripMarkdownFences(_ text: String) -> String {
        var lines = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
        if let first = lines.first?.trimmingCharacters(in: .whitespaces), first.hasPrefix("```") {
            lines.removeFirst()
        }
        if let last = lines.last?.trimmingCharacters(in: .whitespaces), last == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Dual-Mode LLM Helpers

    private func queryOllama(prompt: String, model: String) async -> String? {
        guard let url = URL(string: "http://localhost:11434/api/generate") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                CompanionLog.agent.error("Ollama request failed with HTTP \(http.statusCode)")
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                CompanionLog.agent.error("Ollama response JSON decode failed")
                return nil
            }
            return json["response"] as? String
        } catch {
            CompanionLog.agent.error("Ollama request error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func queryGemini(prompt: String, apiKey: String) async -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 10
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                CompanionLog.agent.error("Gemini request failed with HTTP \(http.statusCode)")
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]]
            else {
                CompanionLog.agent.error("Gemini response JSON decode failed")
                return nil
            }
            return parts.first?["text"] as? String
        } catch {
            CompanionLog.agent.error("Gemini request error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

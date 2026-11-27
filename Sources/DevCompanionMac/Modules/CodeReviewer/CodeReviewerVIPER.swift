import Foundation
import AppKit
import DevCompanionCore

enum IssuePriorityFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case warning
    case suggestion

    var id: String { rawValue }
}

// MARK: - CodeReviewer VIPER
protocol CodeReviewerInteractorProtocol: Sendable {
    func analyze(source: String, fileName: String) -> [CodeReviewFinding]
    func analyzeDirectory(at url: URL, previousFindingIDs: Set<String>) -> [CodeReviewFinding]
    func listGitBranches(in projectURL: URL) async -> (current: String, branches: [String])
    func listProjectModules(in projectURL: URL) -> [String]
    func analyzeBranchDiff(source: String, target: String, changedLinesOnly: Bool, in projectURL: URL, previousFindingIDs: Set<String>) async -> (summary: GitBranchComparisonSummary, findings: [CodeReviewFinding])
    func formatMarkdownPRReport(scopeTitle: String, summary: GitBranchComparisonSummary?, findings: [CodeReviewFinding]) -> String
    func deterministicFix(for finding: CodeReviewFinding, filePath: String?) -> AgentFixProposal
    func applyPatch(to fileURL: URL, oldSnippet: String, newSnippet: String, lineNumber: Int?) throws -> PatchRevertRecord
    func revertPatch(_ record: PatchRevertRecord) throws
    func buildAntigravityPrompt(for finding: CodeReviewFinding, filePath: String?) -> String
    func buildCompactFindingPrompt(for finding: CodeReviewFinding, filePath: String?) -> String
}

struct CodeReviewerInteractor: CodeReviewerInteractorProtocol {
    private let engine: CodeReviewEngine
    private let agentService: AgentService

    init(engine: CodeReviewEngine, agentService: AgentService = AgentService()) {
        self.engine = engine
        self.agentService = agentService
    }

    func analyze(source: String, fileName: String) -> [CodeReviewFinding] {
        engine.analyze(source: source, fileName: fileName)
    }

    func analyzeDirectory(at url: URL, previousFindingIDs: Set<String>) -> [CodeReviewFinding] {
        engine.analyzeDirectory(at: url, previousFindingIDs: previousFindingIDs)
    }

    func listGitBranches(in projectURL: URL) async -> (current: String, branches: [String]) {
        await engine.listGitBranches(in: projectURL)
    }

    func listProjectModules(in projectURL: URL) -> [String] {
        engine.listProjectModules(in: projectURL)
    }

    func analyzeBranchDiff(
        source: String,
        target: String,
        changedLinesOnly: Bool,
        in projectURL: URL,
        previousFindingIDs: Set<String>
    ) async -> (summary: GitBranchComparisonSummary, findings: [CodeReviewFinding]) {
        await engine.analyzeBranchDiff(
            source: source,
            target: target,
            changedLinesOnly: changedLinesOnly,
            in: projectURL,
            previousFindingIDs: previousFindingIDs
        )
    }

    func formatMarkdownPRReport(
        scopeTitle: String,
        summary: GitBranchComparisonSummary?,
        findings: [CodeReviewFinding]
    ) -> String {
        engine.formatMarkdownPRReport(scopeTitle: scopeTitle, summary: summary, findings: findings)
    }

    func deterministicFix(for finding: CodeReviewFinding, filePath: String?) -> AgentFixProposal {
        agentService.deterministicFix(for: finding, filePath: filePath)
    }

    func applyPatch(to fileURL: URL, oldSnippet: String, newSnippet: String, lineNumber: Int?) throws -> PatchRevertRecord {
        try agentService.applyPatch(to: fileURL, oldSnippet: oldSnippet, newSnippet: newSnippet, lineNumber: lineNumber)
    }

    func revertPatch(_ record: PatchRevertRecord) throws {
        try agentService.revertPatch(record)
    }

    func buildAntigravityPrompt(for finding: CodeReviewFinding, filePath: String?) -> String {
        agentService.buildAntigravityPrompt(for: finding, filePath: filePath)
    }

    func buildCompactFindingPrompt(for finding: CodeReviewFinding, filePath: String?) -> String {
        agentService.buildCompactFindingPrompt(for: finding, filePath: filePath)
    }
}

@MainActor
@Observable
final class CodeReviewerPresenter {
    var findings: [CodeReviewFinding] = [] {
        didSet {
            rebuildCaches()
        }
    }
    var customSwiftCode: String = ""
    var selectedFindingForDetail: CodeReviewFinding?
    var hasAnalyzed = false
    /// Strict gate: remains `false` until the user explicitly chooses a scope/category and triggers Code Review.
    /// Background Smart Scan or session restore populates `findings` for Leaks & Hangs without opening this gate.
    var hasUserInitiatedReview = false
    var isAnalyzing = false
    var selectedPriority: IssuePriorityFilter = .all {
        didSet {
            visibleLimit = ProgressiveListChunker.defaultPageSize
            rebuildFilteredCache()
        }
    }
    var selectedCategory: CodeReviewFinding.Category? {
        didSet {
            visibleLimit = ProgressiveListChunker.defaultPageSize
            rebuildFilteredCache()
        }
    }
    /// Initial state is `nil` so no mode/branch/module is pre-selected or auto-scanned on launch.
    var selectedScopeMode: CodeReviewScopeMode? {
        didSet {
            if oldValue != selectedScopeMode {
                hasUserInitiatedReview = false
                hasAnalyzed = false
                visibleLimit = ProgressiveListChunker.defaultPageSize
            }
        }
    }
    var availableBranches: [String] = []
    var currentGitBranch: String = ""
    var sourceBranch: String = ""
    var targetBranch: String = ""
    var changedLinesOnly: Bool = true
    var branchComparisonSummary: GitBranchComparisonSummary?
    var availableModules: [String] = []
    var selectedModuleFolder: String = ""
    var findingsSearchText: String = "" {
        didSet {
            visibleLimit = ProgressiveListChunker.defaultPageSize
            rebuildFilteredCache()
        }
    }
    var groupByFile: Bool = false {
        didSet {
            visibleLimit = ProgressiveListChunker.defaultPageSize
        }
    }
    var visibleLimit: Int = ProgressiveListChunker.defaultPageSize
    var lastRevertRecord: PatchRevertRecord?
    var onFindingsChanged: (() -> Void)?

    private var cachedSortedFindings: [CodeReviewFinding] = []
    private var cachedFilteredFindings: [CodeReviewFinding] = []
    private var cachedGroupedByFile: [CodeReviewFileGroup] = []
    private var cachedPriorityCounts: [IssuePriorityFilter: Int] = [:]
    private var cachedCategoryCounts: [CodeReviewFinding.Category: Int] = [:]

    private let interactor: any CodeReviewerInteractorProtocol
    private let router: AppRouter
    private let clipboard: any ClipboardManaging
    private let fileWatcher = ProjectFileWatcher()
    private var watchTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var baselineFindingIDs: Set<String> = []

    init(
        interactor: any CodeReviewerInteractorProtocol,
        router: AppRouter,
        clipboard: any ClipboardManaging = MacOSClipboard()
    ) {
        self.interactor = interactor
        self.router = router
        self.clipboard = clipboard
    }

    private func rebuildCaches() {
        cachedSortedFindings = CodeReviewEngine.sortFindings(findings)
        var pCounts: [IssuePriorityFilter: Int] = [.all: findings.count, .critical: 0, .warning: 0, .suggestion: 0]
        var cCounts: [CodeReviewFinding.Category: Int] = [:]
        for item in findings {
            switch item.severity {
            case .critical: pCounts[.critical, default: 0] += 1
            case .warning: pCounts[.warning, default: 0] += 1
            case .suggestion: pCounts[.suggestion, default: 0] += 1
            }
            cCounts[item.category, default: 0] += 1
        }
        cachedPriorityCounts = pCounts
        cachedCategoryCounts = cCounts
        rebuildFilteredCache()
    }

    private func rebuildFilteredCache() {
        let byPriority: [CodeReviewFinding] = switch selectedPriority {
        case .all: cachedSortedFindings
        case .critical: cachedSortedFindings.filter { $0.severity == .critical }
        case .warning: cachedSortedFindings.filter { $0.severity == .warning }
        case .suggestion: cachedSortedFindings.filter { $0.severity == .suggestion }
        }
        let byCat: [CodeReviewFinding] = if let cat = selectedCategory {
            byPriority.filter { $0.category == cat }
        } else {
            byPriority
        }
        let q = findingsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [CodeReviewFinding] = if q.isEmpty {
            byCat
        } else {
            byCat.filter {
                SmartSearchMatcher.matches(
                    [$0.fileName, $0.title, $0.detail, $0.codeSnippet, $0.category.rawValue],
                    query: q
                )
            }
        }
        cachedFilteredFindings = filtered
        cachedGroupedByFile = CodeReviewEngine.groupFindingsByFile(filtered)
    }

    /// True only when the user has explicitly selected a scope (or paste snippet) and triggered review.
    var isResultsGateOpen: Bool {
        if hasProjectURL {
            return selectedScopeMode != nil && hasUserInitiatedReview && hasAnalyzed
        } else {
            return hasUserInitiatedReview && hasAnalyzed
        }
    }

    /// Findings displayed in the Code Review UI. Empty (`[]`) until `isResultsGateOpen == true`.
    var displayedFindings: [CodeReviewFinding] {
        guard isResultsGateOpen else { return [] }
        return cachedFilteredFindings
    }

    /// Progressive lazy-loaded slice of `displayedFindings` (`0 ..< min(visibleLimit, displayedFindings.count)`).
    var visibleDisplayedFindings: ArraySlice<CodeReviewFinding> {
        ProgressiveListChunker.visibleSlice(of: displayedFindings, limit: visibleLimit)
    }

    /// File groups displayed in the Code Review UI. Empty (`[]`) until `isResultsGateOpen == true`.
    var displayedFileGroups: [CodeReviewFileGroup] {
        guard isResultsGateOpen else { return [] }
        return cachedGroupedByFile
    }

    var visibleDisplayedFileGroups: ArraySlice<CodeReviewFileGroup> {
        ProgressiveListChunker.visibleSlice(of: displayedFileGroups, limit: visibleLimit)
    }

    func loadMoreFindingsIfNeeded(currentIndex: Int) {
        let total = groupByFile ? displayedFileGroups.count : displayedFindings.count
        if ProgressiveListChunker.shouldLoadMore(currentIndex: currentIndex, currentLimit: visibleLimit, totalCount: total) {
            visibleLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleLimit, totalCount: total)
        }
    }

    func loadMoreFindings() {
        let total = groupByFile ? displayedFileGroups.count : displayedFindings.count
        visibleLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleLimit, totalCount: total)
    }

    func copyAntigravityPrompt(for finding: CodeReviewFinding, openApp: Bool = true) {
        let path = router.projectURL.flatMap { router.findFile(named: finding.fileName, in: $0)?.path }
        let prompt = interactor.buildCompactFindingPrompt(for: finding, filePath: path)
        clipboard.copyString(prompt)
        router.statusMessage = AppStrings.Performance.antigravityPromptCopied
        if openApp { router.openAntigravity() }
    }

    func detailFixProposal(for finding: CodeReviewFinding) -> AgentFixProposal {
        let path = router.projectURL.flatMap { router.findFile(named: finding.fileName, in: $0)?.path }
        return interactor.deterministicFix(for: finding, filePath: path)
    }

    func detailCompactPrompt(for finding: CodeReviewFinding) -> String {
        let path = router.projectURL.flatMap { router.findFile(named: finding.fileName, in: $0)?.path }
        return interactor.buildCompactFindingPrompt(for: finding, filePath: path)
    }

    func detailSourceContext(for finding: CodeReviewFinding, radius: Int = 8) -> String? {
        guard let root = router.projectURL,
              let fileURL = router.findFile(named: finding.fileName, in: root),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }
        let start = max(1, finding.lineNumber - radius)
        let end = min(lines.count, finding.lineNumber + radius)
        guard start <= end else { return nil }
        return (start...end).map { idx in
            let marker = idx == finding.lineNumber ? "▶" : " "
            return String(format: "%@ %4d | %@", marker, idx, lines[idx - 1])
        }.joined(separator: "\n")
    }

    var hasProjectURL: Bool { router.projectURL != nil }

    var canAnalyze: Bool {
        if !hasProjectURL {
            return !customSwiftCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let mode = selectedScopeMode else { return false }
        switch mode {
        case .branchDiff:
            return !sourceBranch.isEmpty && !targetBranch.isEmpty
        case .moduleFolder:
            return !selectedModuleFolder.isEmpty
        case .allProject:
            return true
        }
    }

    var criticalCount: Int {
        guard isResultsGateOpen else { return 0 }
        return cachedPriorityCounts[.critical] ?? 0
    }

    var isPRReadyToMerge: Bool {
        isResultsGateOpen && criticalCount == 0
    }

    var sortedFindings: [CodeReviewFinding] {
        cachedSortedFindings
    }

    var filteredFindings: [CodeReviewFinding] {
        cachedFilteredFindings
    }

    var groupedFindingsByFile: [CodeReviewFileGroup] {
        cachedGroupedByFile
    }

    func count(for filter: IssuePriorityFilter) -> Int {
        guard isResultsGateOpen else { return 0 }
        return cachedPriorityCounts[filter] ?? 0
    }

    func categoryCount(_ category: CodeReviewFinding.Category) -> Int {
        guard isResultsGateOpen else { return 0 }
        return cachedCategoryCounts[category] ?? 0
    }

    func resetSessionState() {
        stopWatchingProject()
        cancelReview()
        findings = []
        baselineFindingIDs = []
        hasAnalyzed = false
        hasUserInitiatedReview = false
        visibleLimit = ProgressiveListChunker.defaultPageSize
        selectedPriority = .all
        selectedCategory = nil
        selectedScopeMode = nil
        sourceBranch = ""
        targetBranch = ""
        selectedModuleFolder = ""
        findingsSearchText = ""
        branchComparisonSummary = nil
        lastRevertRecord = nil
    }

    func refreshProjectGitAndModules() async {
        guard let projectURL = router.projectURL else { return }
        let interactorRef = interactor
        let (gitInfo, mods) = await Task.detached {
            let g = await interactorRef.listGitBranches(in: projectURL)
            let m = interactorRef.listProjectModules(in: projectURL)
            return (g, m)
        }.value
        currentGitBranch = gitInfo.current
        availableBranches = gitInfo.branches
        availableModules = mods
    }

    func swapBranches() {
        let tmp = sourceBranch
        sourceBranch = targetBranch
        targetBranch = tmp
    }

    func quickFillCurrentToBaseBranches() {
        let cur = currentGitBranch.isEmpty ? (availableBranches.first ?? "main") : currentGitBranch
        sourceBranch = cur
        targetBranch = availableBranches.first(where: { $0 != cur && ($0 == "develop" || $0 == "main" || $0 == "master" || $0 == "origin/develop" || $0 == "origin/main") })
            ?? availableBranches.first(where: { $0 != cur })
            ?? cur
    }

    func pickCustomModuleFolder() {
        guard let projectURL = router.projectURL else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = projectURL
        panel.prompt = AppStrings.CodeReview.modulePickerLabel
        if panel.runModal() == .OK, let picked = panel.url {
            let rel = picked.path.replacingOccurrences(of: projectURL.path + "/", with: "")
            if !availableModules.contains(rel) {
                availableModules.insert(rel, at: 0)
            }
            selectedModuleFolder = rel
            selectedScopeMode = .moduleFolder
        }
    }

    func startWatchingProject(_ url: URL?) {
        stopWatchingProject()
        guard let url else { return }
        watchTask = Task { [weak self] in
            guard let self else { return }
            await self.fileWatcher.reset()
            _ = await self.fileWatcher.detectChanges(in: url)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1800))
                guard !Task.isCancelled else { break }
                let changed = await self.fileWatcher.detectChanges(in: url)
                if !changed.isEmpty, self.hasAnalyzed, self.selectedScopeMode != nil {
                    await self.runScopedReview()
                }
            }
        }
    }

    func stopWatchingProject() {
        watchTask?.cancel()
        watchTask = nil
    }

    func startReview() {
        cancelReview()
        hasUserInitiatedReview = true
        visibleLimit = ProgressiveListChunker.defaultPageSize
        analysisTask = Task { [weak self] in
            await self?.runScopedReview()
        }
    }

    func cancelReview() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }

    func runScopedReview() async {
        guard let projectURL = router.projectURL else {
            _ = runAnalysis()
            return
        }
        guard let mode = selectedScopeMode else { return }
        hasUserInitiatedReview = true
        visibleLimit = ProgressiveListChunker.defaultPageSize
        isAnalyzing = true
        defer { isAnalyzing = false }

        let interactorRef = interactor
        let prevIDs = baselineFindingIDs

        switch mode {
        case .allProject:
            let analyzed = await Task.detached {
                interactorRef.analyzeDirectory(at: projectURL, previousFindingIDs: prevIDs)
            }.value
            guard !Task.isCancelled else { return }
            hasAnalyzed = true
            findings = analyzed
            branchComparisonSummary = nil
            baselineFindingIDs = Set(analyzed.map(\.id))
            router.statusMessage = AppStrings.CodeReview.reviewCompletedProject(projectURL.lastPathComponent, findings.count)
            onFindingsChanged?()

        case .moduleFolder:
            let modFolder = selectedModuleFolder
            let folderURL = modFolder.isEmpty ? projectURL : projectURL.appendingPathComponent(modFolder)
            let analyzed = await Task.detached {
                interactorRef.analyzeDirectory(at: folderURL, previousFindingIDs: prevIDs)
            }.value
            guard !Task.isCancelled else { return }
            hasAnalyzed = true
            findings = analyzed
            branchComparisonSummary = nil
            baselineFindingIDs = Set(analyzed.map(\.id))
            let label = modFolder.isEmpty ? projectURL.lastPathComponent : modFolder
            router.statusMessage = AppStrings.CodeReview.reviewCompletedProject(label, findings.count)
            onFindingsChanged?()

        case .branchDiff:
            let src = sourceBranch
            let dst = targetBranch
            let linesOnly = changedLinesOnly
            let result = await interactorRef.analyzeBranchDiff(
                source: src,
                target: dst,
                changedLinesOnly: linesOnly,
                in: projectURL,
                previousFindingIDs: prevIDs
            )
            guard !Task.isCancelled else { return }
            hasAnalyzed = true
            branchComparisonSummary = result.summary
            findings = result.findings
            baselineFindingIDs = Set(result.findings.map(\.id))
            router.statusMessage = AppStrings.CodeReview.reviewCompletedProject("\(src) -> \(dst)", findings.count)
            onFindingsChanged?()
        }

        if watchTask == nil {
            startWatchingProject(projectURL)
        }
    }

    /// Used by background Overview Smart Scan & Live Reload so `Leak & Hang` telemetry gets updated
    /// without opening the Code Review UI gate before the user selects a scope & runs review.
    @discardableResult
    func runBackgroundProjectScan() -> Int {
        guard let projectURL = router.projectURL else { return 0 }
        let analyzed = interactor.analyzeDirectory(at: projectURL, previousFindingIDs: baselineFindingIDs)
        findings = analyzed
        baselineFindingIDs = Set(analyzed.map(\.id))
        onFindingsChanged?()
        return findings.count
    }

    @discardableResult
    func runAnalysis() -> Int {
        visibleLimit = ProgressiveListChunker.defaultPageSize
        if let projectURL = router.projectURL {
            if selectedScopeMode == nil {
                selectedScopeMode = .allProject
            }
            hasUserInitiatedReview = true
            hasAnalyzed = true
            let targetURL: URL = if selectedScopeMode == .moduleFolder && !selectedModuleFolder.isEmpty {
                projectURL.appendingPathComponent(selectedModuleFolder)
            } else {
                projectURL
            }
            let analyzed = interactor.analyzeDirectory(at: targetURL, previousFindingIDs: baselineFindingIDs)
            findings = analyzed
            branchComparisonSummary = nil
            baselineFindingIDs = Set(analyzed.map(\.id))
            router.statusMessage = AppStrings.CodeReview.reviewCompletedProject(targetURL.lastPathComponent, findings.count)
        } else if !customSwiftCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasUserInitiatedReview = true
            hasAnalyzed = true
            let now = Date()
            let prev = baselineFindingIDs
            let analyzed = interactor.analyze(source: customSwiftCode, fileName: "Snippet.swift").map { item -> CodeReviewFinding in
                var copy = item
                copy.detectedAt = now
                copy.isNew = prev.isEmpty || !prev.contains(item.id)
                return copy
            }
            findings = CodeReviewEngine.sortFindings(analyzed)
            baselineFindingIDs = Set(analyzed.map(\.id))
            router.statusMessage = AppStrings.CodeReview.reviewCompletedSnippet(findings.count)
        } else {
            hasUserInitiatedReview = false
            hasAnalyzed = false
            findings = []
            baselineFindingIDs = []
            router.statusMessage = AppStrings.CodeReview.emptyPrompt
        }
        onFindingsChanged?()
        return findings.count
    }

    func openInXcode(_ finding: CodeReviewFinding) async {
        await router.openInXcode(fileName: finding.fileName, line: finding.lineNumber)
    }

    func applyQuickFix(for finding: CodeReviewFinding) {
        let path = router.projectURL.flatMap { router.findFile(named: finding.fileName, in: $0)?.path }
        let proposal = interactor.deterministicFix(for: finding, filePath: path)
        if let filePath = proposal.filePath {
            do {
                let record = try interactor.applyPatch(
                    to: URL(fileURLWithPath: filePath),
                    oldSnippet: proposal.oldSnippet,
                    newSnippet: proposal.newSnippet,
                    lineNumber: finding.lineNumber
                )
                lastRevertRecord = record
                router.statusMessage = AppStrings.Performance.patchAppliedToFile(finding.fileName)
                startReview()
            } catch {
                router.statusMessage = error.localizedDescription
            }
        } else if !customSwiftCode.isEmpty, customSwiftCode.contains(proposal.oldSnippet) {
            customSwiftCode = customSwiftCode.replacingOccurrences(of: proposal.oldSnippet, with: proposal.newSnippet)
            _ = runAnalysis()
            router.statusMessage = AppStrings.Performance.patchAppliedToEditor
        }
    }

    func revertLastPatch() {
        guard let record = lastRevertRecord else { return }
        do {
            try interactor.revertPatch(record)
            lastRevertRecord = nil
            router.statusMessage = AppStrings.Performance.patchRolledBack(record.fileURL.lastPathComponent)
            startReview()
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func copyPRMarkdownReport() {
        let scopeTitle: String = switch selectedScopeMode {
        case .branchDiff: "\(sourceBranch) -> \(targetBranch)"
        case .moduleFolder: selectedModuleFolder.isEmpty ? (router.projectURL?.lastPathComponent ?? "Module") : selectedModuleFolder
        case .allProject, nil: router.projectURL?.lastPathComponent ?? "All Project"
        }
        let report = interactor.formatMarkdownPRReport(
            scopeTitle: scopeTitle,
            summary: branchComparisonSummary,
            findings: filteredFindings
        )
        clipboard.copyString(report)
        router.statusMessage = AppStrings.CodeReview.prReportCopied
    }
}

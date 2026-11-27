import Foundation
import AppKit
import UniformTypeIdentifiers
import DevCompanionCore

enum CrashReportKindFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case crash = "Fatal"
    case hang = "ANR / Hang"
    case memory = "Memory"

    var id: String { rawValue }
}

enum CrashInspectorTab: String, CaseIterable, Identifiable {
    case stackTrace
    case rawLog

    var id: String { rawValue }
}

@MainActor
@Observable
final class CrashlyticsPresenter {
    var reports: [DiagnosticReportItem] = []
    var isLoading = false
    var selectedReportID: String?
    var hoveredReportID: String?
    var selectedReportName: String = ""
    var selectedReportContent: String = ""
    var activeAnalysis: CrashAnalysisReport?
    var sourceSnippet: CrashSourceSnippet?
    var activeFixProposal: AgentFixProposal?
    var lastRevertRecord: PatchRevertRecord?
    var selectedPriority: IssuePriorityFilter = .all {
        didSet { visibleReportLimit = ProgressiveListChunker.defaultPageSize }
    }
    var kindFilter: CrashReportKindFilter = .all {
        didSet { visibleReportLimit = ProgressiveListChunker.defaultPageSize }
    }
    var searchText: String = "" {
        didSet { visibleReportLimit = ProgressiveListChunker.defaultPageSize }
    }
    var visibleReportLimit: Int = ProgressiveListChunker.defaultPageSize
    var visibleStackFrameLimit: Int = ProgressiveListChunker.defaultPageSize
    var inspectorTab: CrashInspectorTab = .stackTrace
    var showSystemReports = false {
        didSet {
            if oldValue != showSystemReports {
                Task { await refreshReports() }
            }
        }
    }
    var onSessionChanged: (() -> Void)?

    private let interactor: any PerformanceInteractorProtocol
    private let router: AppRouter
    private let clipboard: any ClipboardManaging
    private var baselineReportIDs: Set<String> = []
    private var selectTask: Task<Void, Never>?

    init(
        interactor: any PerformanceInteractorProtocol,
        router: AppRouter,
        clipboard: any ClipboardManaging = MacOSClipboard()
    ) {
        self.interactor = interactor
        self.router = router
        self.clipboard = clipboard
    }

    var hasProject: Bool { router.projectURL != nil }
    var projectName: String? { router.projectURL?.lastPathComponent }

    var fatalCount: Int {
        reports.filter { $0.kind == .crash }.count
    }

    var hangCount: Int {
        reports.filter { $0.kind == .hang }.count
    }

    var memoryCount: Int {
        reports.filter { $0.kind == .memory }.count
    }

    func count(for filter: CrashReportKindFilter) -> Int {
        switch filter {
        case .all: return reports.count
        case .crash: return fatalCount
        case .hang: return hangCount
        case .memory: return memoryCount
        }
    }

    func priorityCount(for filter: IssuePriorityFilter) -> Int {
        switch filter {
        case .all: return reports.count
        case .critical: return reports.filter { $0.priority == .critical }.count
        case .warning: return reports.filter { $0.priority == .warning }.count
        case .suggestion: return reports.filter { $0.priority == .suggestion }.count
        }
    }

    var filteredReports: [DiagnosticReportItem] {
        let byPriority: [DiagnosticReportItem] = switch selectedPriority {
        case .all: reports
        case .critical: reports.filter { $0.priority == .critical }
        case .warning: reports.filter { $0.priority == .warning }
        case .suggestion: reports.filter { $0.priority == .suggestion }
        }
        let byKind: [DiagnosticReportItem] = switch kindFilter {
        case .all: byPriority
        case .crash: byPriority.filter { $0.kind == .crash }
        case .hang: byPriority.filter { $0.kind == .hang }
        case .memory: byPriority.filter { $0.kind == .memory }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return byKind }
        return byKind.filter {
            SmartSearchMatcher.matches(
                [$0.processName, $0.fileName, $0.summary, $0.humanTitle, $0.whenContext, $0.sourceLocation ?? ""],
                query: q
            )
        }
    }

    var visibleFilteredReports: ArraySlice<DiagnosticReportItem> {
        ProgressiveListChunker.visibleSlice(of: filteredReports, limit: visibleReportLimit)
    }

    func loadMoreReportsIfNeeded(currentIndex: Int) {
        let total = filteredReports.count
        if ProgressiveListChunker.shouldLoadMore(currentIndex: currentIndex, currentLimit: visibleReportLimit, totalCount: total) {
            visibleReportLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleReportLimit, totalCount: total)
        }
    }

    func loadMoreReports() {
        let total = filteredReports.count
        visibleReportLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleReportLimit, totalCount: total)
    }

    func loadMoreStackFramesIfNeeded(currentIndex: Int, totalCount: Int) {
        if ProgressiveListChunker.shouldLoadMore(currentIndex: currentIndex, currentLimit: visibleStackFrameLimit, totalCount: totalCount) {
            visibleStackFrameLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleStackFrameLimit, totalCount: totalCount)
        }
    }

    func loadMoreStackFrames(totalCount: Int) {
        visibleStackFrameLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleStackFrameLimit, totalCount: totalCount)
    }

    var inspectedTimelineReport: DiagnosticReportItem? {
        if let id = hoveredReportID, let r = filteredReports.first(where: { $0.id == id }) {
            return r
        }
        if let id = selectedReportID, let r = filteredReports.first(where: { $0.id == id }) {
            return r
        }
        return filteredReports.first
    }

    func isAppFrame(_ frame: String) -> Bool {
        let proc = activeAnalysis?.processName ?? selectedReportName
        return DiagnosticService.isAppStackFrame(frame, processName: proc, projectName: projectName)
    }

    func resetSessionState() {
        selectTask?.cancel()
        selectTask = nil
        isLoading = false
        selectedReportID = nil
        hoveredReportID = nil
        selectedReportName = ""
        selectedReportContent = ""
        activeAnalysis = nil
        sourceSnippet = nil
        activeFixProposal = nil
        lastRevertRecord = nil
        selectedPriority = .all
        kindFilter = .all
        searchText = ""
        baselineReportIDs = []
    }

    /// 100% non-blocking background report discovery (zero main-thread disk enumeration or O(N*M) project scan loop).
    func refreshReports() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let interactorRef = interactor
        let projName = router.projectURL?.lastPathComponent
        let includeSys = showSystemReports
        let prevBaseline = baselineReportIDs

        let loaded = await Task.detached {
            let procs = await interactorRef.listSimulatorProcesses()
            var items = interactorRef.loadDiagnosticReports(
                projectName: projName,
                simulatorAppNames: procs.map(\.name),
                includeSystemReports: includeSys
            )
            if !prevBaseline.isEmpty {
                for idx in items.indices {
                    items[idx].isNew = !prevBaseline.contains(items[idx].id)
                }
            }
            items.sort { lhs, rhs in
                if lhs.priority.priorityRank != rhs.priority.priorityRank {
                    return lhs.priority.priorityRank < rhs.priority.priorityRank
                }
                if lhs.isNew != rhs.isNew {
                    return lhs.isNew && !rhs.isNew
                }
                return lhs.timestamp > rhs.timestamp
            }
            return items
        }.value

        reports = loaded
        baselineReportIDs = Set(loaded.map(\.id))

        if selectedReportID == nil, let first = loaded.first {
            selectReport(first)
        } else if let currentID = selectedReportID,
                  let current = loaded.first(where: { $0.id == currentID }) {
            selectReport(current)
        }
    }

    /// Resolves full stack trace and Swift source code off the main thread only for the single selected report.
    func selectReport(_ report: DiagnosticReportItem) {
        selectTask?.cancel()
        selectedReportID = report.id
        selectedReportName = report.fileName
        visibleStackFrameLimit = ProgressiveListChunker.defaultPageSize

        let interactorRef = interactor
        let projURL = router.projectURL
        let reportID = report.id
        let reportPath = report.filePath
        let procName = report.processName

        selectTask = Task { [weak self] in
            let (content, resolved, proposal) = await Task.detached {
                let raw = interactorRef.readReportContent(at: reportPath)
                let parsed = interactorRef.analyzeCrashReport(content: raw, processName: procName)
                let res = interactorRef.resolveProjectCrashSource(for: parsed, in: projURL)
                let prop = interactorRef.proposeCrashFix(for: res.analysis, snippet: res.snippet)
                return (raw, res, prop)
            }.value

            guard let self, !Task.isCancelled, self.selectedReportID == reportID else { return }
            self.selectedReportContent = content
            self.activeAnalysis = resolved.analysis
            self.sourceSnippet = resolved.snippet
            self.activeFixProposal = proposal

            if let file = resolved.analysis.sourceFileName,
               let idx = self.reports.firstIndex(where: { $0.id == reportID }) {
                self.reports[idx].sourceLocation = "\(file):\(resolved.analysis.sourceLineNumber ?? 1)"
                self.reports[idx].whenContext = resolved.analysis.whenAction
                self.reports[idx].humanTitle = resolved.analysis.humanExplanation
            }
            self.onSessionChanged?()
        }
    }

    func openInXcode() async {
        guard let fileName = sourceSnippet?.fileName ?? activeAnalysis?.sourceFileName else {
            router.statusMessage = AppStrings.Performance.noFindingForXcode
            return
        }
        let line = sourceSnippet?.lineNumber ?? activeAnalysis?.sourceLineNumber ?? 1
        await router.openInXcode(fileName: fileName, line: line)
    }

    func copyActiveDiff() {
        guard let proposal = activeFixProposal else { return }
        clipboard.copyString("- \(proposal.oldSnippet)\n+ \(proposal.newSnippet)")
        router.statusMessage = AppStrings.Common.copyDiff
    }

    func applyActiveFix() {
        guard let proposal = activeFixProposal, let path = proposal.filePath else {
            router.statusMessage = AppStrings.Performance.noFindingForXcode
            return
        }
        do {
            let record = try interactor.applyPatch(
                to: URL(fileURLWithPath: path),
                oldSnippet: proposal.oldSnippet,
                newSnippet: proposal.newSnippet,
                lineNumber: proposal.lineNumber
            )
            lastRevertRecord = record
            router.statusMessage = AppStrings.Performance.patchAppliedToFile(URL(fileURLWithPath: path).lastPathComponent)
            if let currentID = selectedReportID, let current = reports.first(where: { $0.id == currentID }) {
                selectReport(current)
            }
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func revertLastPatch() {
        guard let record = lastRevertRecord else { return }
        do {
            try interactor.revertPatch(record)
            lastRevertRecord = nil
            router.statusMessage = AppStrings.Performance.patchRolledBack(record.fileURL.lastPathComponent)
            if let currentID = selectedReportID, let current = reports.first(where: { $0.id == currentID }) {
                selectReport(current)
            }
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func copyAntigravityCrashPrompt(openApp: Bool = true) {
        guard let crash = activeAnalysis else { return }
        let prompt = interactor.buildAntigravityCrashPrompt(crash: crash, snippet: sourceSnippet)
        clipboard.copyString(prompt)
        router.statusMessage = AppStrings.Performance.antigravityPromptCopied
        if openApp { router.openAntigravity() }
    }

    func copyMarkdownReport() {
        let md = DiagnosticReportExporter.buildCrashlyticsMarkdown(
            reports: reports,
            projectName: router.projectURL?.lastPathComponent
        )
        clipboard.copyString(md)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "XScope_Crashlytics_Report.md"
        if panel.runModal() == .OK, let dest = panel.url {
            try? md.write(to: dest, atomically: true, encoding: .utf8)
            router.statusMessage = "Exported Crashlytics report to \(dest.lastPathComponent) (also copied)."
        } else {
            router.statusMessage = "Crashlytics Markdown report copied to clipboard."
        }
    }

    func importDroppedCrashFile(url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["ips", "crash", "hang", "diag", "txt"].contains(ext) else { return }
        let kind: DiagnosticReportItem.Kind = ext == "hang" ? .hang : .crash
        let item = DiagnosticReportItem(
            id: "drop-\(url.path)",
            fileName: url.lastPathComponent,
            processName: url.deletingPathExtension().lastPathComponent,
            kind: kind,
            timestamp: Date(),
            summary: "Imported via drag & drop",
            filePath: url.path,
            isSystemDaemon: false,
            isNew: true
        )
        if !reports.contains(where: { $0.filePath == url.path }) {
            reports.insert(item, at: 0)
        }
        selectReport(item)
        router.statusMessage = "Loaded dropped report: \(url.lastPathComponent)"
    }
}

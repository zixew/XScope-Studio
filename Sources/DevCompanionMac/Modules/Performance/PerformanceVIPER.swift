import Foundation
import AppKit
import UniformTypeIdentifiers
import DevCompanionCore

// MARK: - Performance & Instruments VIPER
protocol PerformanceInteractorProtocol: Sendable {
    func loadDiagnosticReports(projectName: String?, simulatorAppNames: [String], includeSystemReports: Bool) -> [DiagnosticReportItem]
    func readReportContent(at path: String) -> String
    func analyzeCrashReport(content: String, processName: String) -> CrashAnalysisReport
    func locateCrashSource(fileName: String, lineNumber: Int?, in projectURL: URL) -> CrashSourceSnippet?
    func resolveProjectCrashSource(for report: CrashAnalysisReport, in projectURL: URL?) -> (analysis: CrashAnalysisReport, snippet: CrashSourceSnippet?)
    func proposeCrashFix(for crash: CrashAnalysisReport, snippet: CrashSourceSnippet?) -> AgentFixProposal
    func buildAntigravityPrompt(for finding: CodeReviewFinding, filePath: String?) -> String
    func buildAntigravityCrashPrompt(crash: CrashAnalysisReport, snippet: CrashSourceSnippet?) -> String
    func listSimulatorProcesses() async -> [SimulatorProcessInfo]
    func listPhysicalDeviceProcesses(deviceID: String, deviceName: String) async -> [SimulatorProcessInfo]
    func sampleTelemetry(pid: Int32) async -> ProcessTelemetrySample?
    func sampleTelemetry(for process: SimulatorProcessInfo) async -> ProcessTelemetrySample?
    func sampleRuntimeLeaks(pid: Int32) async -> RuntimeLeakSnapshot
    func sampleProcessCallStack(pid: Int32, processName: String) async -> String?
    func extractHangDuration(reportPath: String) -> Double?
    func proposeFix(for finding: CodeReviewFinding, filePath: String?, provider: AgentProviderKind, apiKey: String, ollamaModel: String) async -> AgentFixProposal
    func applyPatch(to fileURL: URL, oldSnippet: String, newSnippet: String, lineNumber: Int?) throws -> PatchRevertRecord
    func revertPatch(_ record: PatchRevertRecord) throws
    func loadApiKey() -> String
    func saveApiKey(_ key: String) throws
}

struct PerformanceInteractor: PerformanceInteractorProtocol {
    private let diagnosticService: DiagnosticService
    private let telemetryService: ProcessTelemetryService
    private let agentService: AgentService
    private let secretStore: any SecretStoring
    private let apiKeyAccount = "gemini_api_key"

    init(
        diagnosticService: DiagnosticService,
        telemetryService: ProcessTelemetryService,
        agentService: AgentService,
        secretStore: any SecretStoring
    ) {
        self.diagnosticService = diagnosticService
        self.telemetryService = telemetryService
        self.agentService = agentService
        self.secretStore = secretStore
    }

    func loadDiagnosticReports(projectName: String?, simulatorAppNames: [String], includeSystemReports: Bool) -> [DiagnosticReportItem] {
        diagnosticService.loadRecentReports(
            projectName: projectName,
            simulatorAppNames: simulatorAppNames,
            includeSystemReports: includeSystemReports
        )
    }

    func readReportContent(at path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? handle.close() }
        // Cap preview reads at 512 KB to prevent UI stalls on multi-megabyte .ips logs.
        let maxBytes = 524_288
        let data = handle.readData(ofLength: maxBytes)
        let text = String(data: data, encoding: .utf8) ?? ""
        return data.count == maxBytes ? text + "\n\n[Truncated at 512 KB for responsiveness]" : text
    }

    func analyzeCrashReport(content: String, processName: String) -> CrashAnalysisReport {
        diagnosticService.analyzeCrashReport(content: content, processName: processName)
    }

    func locateCrashSource(fileName: String, lineNumber: Int?, in projectURL: URL) -> CrashSourceSnippet? {
        diagnosticService.locateSourceSnippet(fileName: fileName, lineNumber: lineNumber, in: projectURL)
    }

    func resolveProjectCrashSource(for report: CrashAnalysisReport, in projectURL: URL?) -> (analysis: CrashAnalysisReport, snippet: CrashSourceSnippet?) {
        diagnosticService.resolveProjectSource(for: report, in: projectURL)
    }

    func proposeCrashFix(for crash: CrashAnalysisReport, snippet: CrashSourceSnippet?) -> AgentFixProposal {
        agentService.proposeCrashFix(for: crash, snippet: snippet)
    }

    func buildAntigravityPrompt(for finding: CodeReviewFinding, filePath: String?) -> String {
        agentService.buildAntigravityPrompt(for: finding, filePath: filePath)
    }

    func buildAntigravityCrashPrompt(crash: CrashAnalysisReport, snippet: CrashSourceSnippet?) -> String {
        agentService.buildAntigravityCrashPrompt(crash: crash, snippet: snippet)
    }

    func listSimulatorProcesses() async -> [SimulatorProcessInfo] {
        await telemetryService.listRunningSimulatorProcesses()
    }

    func listPhysicalDeviceProcesses(deviceID: String, deviceName: String) async -> [SimulatorProcessInfo] {
        await telemetryService.listRunningPhysicalDeviceProcesses(deviceID: deviceID, deviceName: deviceName)
    }

    func sampleTelemetry(pid: Int32) async -> ProcessTelemetrySample? {
        await telemetryService.sampleTelemetry(pid: pid)
    }

    func sampleTelemetry(for process: SimulatorProcessInfo) async -> ProcessTelemetrySample? {
        await telemetryService.sampleTelemetry(for: process)
    }

    func sampleRuntimeLeaks(pid: Int32) async -> RuntimeLeakSnapshot {
        await telemetryService.sampleRuntimeLeaks(pid: pid)
    }

    func sampleProcessCallStack(pid: Int32, processName: String) async -> String? {
        await telemetryService.sampleProcessCallStack(pid: pid, processName: processName)
    }

    func extractHangDuration(reportPath: String) -> Double? {
        telemetryService.extractHangDurationSeconds(from: reportPath)
    }

    func proposeFix(
        for finding: CodeReviewFinding,
        filePath: String?,
        provider: AgentProviderKind,
        apiKey: String,
        ollamaModel: String
    ) async -> AgentFixProposal {
        await agentService.proposeFix(
            for: finding,
            filePath: filePath,
            provider: provider,
            apiKey: apiKey,
            ollamaModel: ollamaModel
        )
    }

    func applyPatch(to fileURL: URL, oldSnippet: String, newSnippet: String, lineNumber: Int?) throws -> PatchRevertRecord {
        try agentService.applyPatch(to: fileURL, oldSnippet: oldSnippet, newSnippet: newSnippet, lineNumber: lineNumber)
    }

    func revertPatch(_ record: PatchRevertRecord) throws {
        try agentService.revertPatch(record)
    }

    func loadApiKey() -> String {
        secretStore.loadSecret(account: apiKeyAccount) ?? ""
    }

    func saveApiKey(_ key: String) throws {
        try secretStore.saveSecret(key, account: apiKeyAccount)
    }
}

enum LeakDetectionScope: String, CaseIterable, Identifiable {
    case projectHistory = "Project History"
    case realtimeSession = "Realtime Debug"

    var id: String { rawValue }
}

@MainActor
@Observable
final class PerformancePresenter {
    var leakScope: LeakDetectionScope = .realtimeSession
    var realtimeSessionFreezes: [FreezeLagEvent] = []
    var diagnosticReports: [DiagnosticReportItem] = []
    var simulatorProcesses: [SimulatorProcessInfo] = []
    var selectedProcess: SimulatorProcessInfo? {
        didSet {
            if oldValue?.id != selectedProcess?.id {
                liveCPU = 0
                liveMemoryMB = 0
                cpuHistory = Array(repeating: 0, count: AppConstants.Telemetry.historyCapacity)
                memoryHistory = Array(repeating: 0, count: AppConstants.Telemetry.historyCapacity)
                cpuTimeline = Array(repeating: TelemetryTimelinePoint(value: 0), count: AppConstants.Telemetry.historyCapacity)
                activeFreezeDurationSeconds = 0
                activeFreezeEvent = nil
            }
        }
    }
    var liveCPU: Double = 0
    var liveMemoryMB: Double = 0
    var cpuHistory: [Double] = Array(repeating: 0, count: AppConstants.Telemetry.historyCapacity)
    var memoryHistory: [Double] = Array(repeating: 0, count: AppConstants.Telemetry.historyCapacity)
    var cpuTimeline: [TelemetryTimelinePoint] = Array(repeating: TelemetryTimelinePoint(value: 0), count: AppConstants.Telemetry.historyCapacity)
    var capturedFreezeEvents: [FreezeLagEvent] = []
    var activeFreezeDurationSeconds: Double = 0
    var activeFreezeEvent: FreezeLagEvent?
    var onSessionChanged: (() -> Void)?
    var lastHangSeconds: Double?
    var isTelemetryActive = false
    var selectedPriority: IssuePriorityFilter = .all {
        didSet {
            visibleLeakLimit = ProgressiveListChunker.defaultPageSize
        }
    }
    var visibleLeakLimit: Int = ProgressiveListChunker.defaultPageSize
    var runtimeLeakSnapshot: RuntimeLeakSnapshot?
    var isSamplingRuntimeLeaks = false
    var selectedFindingID: String?
    var selectedReportContent: String = ""
    var selectedReportName: String = ""
    var activeCrashAnalysis: CrashAnalysisReport?
    var crashSourceSnippet: CrashSourceSnippet?
    var showSystemReports = false {
        didSet {
            if oldValue != showSystemReports {
                Task { await refreshReportsAndProcesses() }
            }
        }
    }

    var agentProvider: AgentProviderKind = .antigravityPrompt
    var agentApiKey: String {
        didSet {
            do {
                try interactor.saveApiKey(agentApiKey)
            } catch {
                router.statusMessage = error.localizedDescription
            }
        }
    }
    var agentOllamaModel: String {
        didSet { preferencesStore.set(agentOllamaModel, forKey: AppConstants.StorageKeys.ollamaModel) }
    }
    var activeFixProposal: AgentFixProposal?
    var lastRevertRecord: PatchRevertRecord?

    private let interactor: any PerformanceInteractorProtocol
    private let router: AppRouter
    private let codeReviewerPresenter: CodeReviewerPresenter
    private let preferencesStore: any PreferencesStoring
    private let clipboard: any ClipboardManaging
    private var telemetryTask: Task<Void, Never>?
    private var runtimeLeakTask: Task<Void, Never>?
    private var stackSampleTask: Task<Void, Never>?
    private var isSamplingStack = false
    private var proposalTask: Task<Void, Never>?

    init(
        interactor: any PerformanceInteractorProtocol,
        router: AppRouter,
        codeReviewerPresenter: CodeReviewerPresenter,
        preferencesStore: any PreferencesStoring = UserDefaultsStore(),
        clipboard: any ClipboardManaging = MacOSClipboard()
    ) {
        self.interactor = interactor
        self.router = router
        self.codeReviewerPresenter = codeReviewerPresenter
        self.preferencesStore = preferencesStore
        self.clipboard = clipboard
        self.agentApiKey = interactor.loadApiKey()
        self.agentOllamaModel = preferencesStore.string(forKey: AppConstants.StorageKeys.ollamaModel) ?? AppConstants.Defaults.defaultOllamaModel
    }

    var leakAndHangFindings: [CodeReviewFinding] {
        codeReviewerPresenter.sortedFindings.filter {
            $0.category == .memoryLeak || $0.category == .mainThread || $0.category == .uiKit
        }
    }

    var filteredLeakAndHangFindings: [CodeReviewFinding] {
        switch selectedPriority {
        case .all: return leakAndHangFindings
        case .critical: return leakAndHangFindings.filter { $0.severity == .critical }
        case .warning: return leakAndHangFindings.filter { $0.severity == .warning }
        case .suggestion: return leakAndHangFindings.filter { $0.severity == .suggestion }
        }
    }

    var visibleLeakAndHangFindings: ArraySlice<CodeReviewFinding> {
        ProgressiveListChunker.visibleSlice(of: filteredLeakAndHangFindings, limit: visibleLeakLimit)
    }

    func loadMoreLeaksIfNeeded(currentIndex: Int) {
        let total = filteredLeakAndHangFindings.count
        if ProgressiveListChunker.shouldLoadMore(currentIndex: currentIndex, currentLimit: visibleLeakLimit, totalCount: total) {
            visibleLeakLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleLeakLimit, totalCount: total)
        }
    }

    func loadMoreLeaks() {
        let total = filteredLeakAndHangFindings.count
        visibleLeakLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleLeakLimit, totalCount: total)
    }

    func count(for filter: IssuePriorityFilter) -> Int {
        switch filter {
        case .all: return leakAndHangFindings.count
        case .critical: return leakAndHangFindings.filter { $0.severity == .critical }.count
        case .warning: return leakAndHangFindings.filter { $0.severity == .warning }.count
        case .suggestion: return leakAndHangFindings.filter { $0.severity == .suggestion }.count
        }
    }

    var totalPotentialLeakCount: Int {
        leakAndHangFindings.count + (runtimeLeakSnapshot?.leakCount ?? 0)
    }

    var isXcodeDebugSessionActive: Bool {
        !simulatorProcesses.isEmpty && selectedProcess != nil
    }

    func resetRealtimeDebugSession() {
        runtimeLeakSnapshot = nil
        realtimeSessionFreezes = []
        activeFreezeDurationSeconds = 0
        activeFreezeEvent = nil
    }

    var hasProject: Bool { router.projectURL != nil }

    func resetSessionState() {
        telemetryTask?.cancel()
        telemetryTask = nil
        runtimeLeakTask?.cancel()
        runtimeLeakTask = nil
        stackSampleTask?.cancel()
        stackSampleTask = nil
        proposalTask?.cancel()
        proposalTask = nil
        isTelemetryActive = false
        isSamplingRuntimeLeaks = false
        isSamplingStack = false
        runtimeLeakSnapshot = nil
        selectedPriority = .all
        liveCPU = 0
        liveMemoryMB = 0
        cpuHistory = Array(repeating: 0, count: AppConstants.Telemetry.historyCapacity)
        memoryHistory = Array(repeating: 0, count: AppConstants.Telemetry.historyCapacity)
        cpuTimeline = Array(repeating: TelemetryTimelinePoint(value: 0), count: AppConstants.Telemetry.historyCapacity)
        capturedFreezeEvents = []
        activeFreezeDurationSeconds = 0
        activeFreezeEvent = nil
        lastHangSeconds = nil
        selectedFindingID = nil
        activeFixProposal = nil
        lastRevertRecord = nil
        selectedReportContent = ""
        selectedReportName = ""
        activeCrashAnalysis = nil
        crashSourceSnippet = nil
    }

    func clearCapturedFreezeHistory() {
        capturedFreezeEvents = []
        activeFreezeDurationSeconds = 0
        activeFreezeEvent = nil
        onSessionChanged?()
    }

    func seedStaticFreezesFromFindingsIfNeeded() {
        // Remove any legacy static events that were seeded from non-mainThread (.uiKit) findings
        capturedFreezeEvents.removeAll { ev in
            ev.id.hasPrefix("static-") && !ev.id.contains("Main Thread")
        }
        guard capturedFreezeEvents.isEmpty else { return }
        let mainThreadItems = leakAndHangFindings.filter { $0.category == .mainThread }
        guard !mainThreadItems.isEmpty else { return }
        let baseDuration = lastHangSeconds ?? 1.5
        capturedFreezeEvents = mainThreadItems.prefix(8).enumerated().map { idx, finding in
            let estDuration = max(0.6, baseDuration - (Double(idx % 3) * 0.25))
            return FreezeLagEvent(
                id: "static-\(finding.id)",
                startedAt: finding.detectedAt > Date(timeIntervalSince1970: 0) ? finding.detectedAt : Date().addingTimeInterval(Double(-idx * 15)),
                durationSeconds: estDuration,
                peakCPUPercent: 100.0,
                memoryMB: max(liveMemoryMB, 120.0),
                culpritSymbol: "\(finding.fileName):\(finding.lineNumber)",
                fileName: finding.fileName,
                lineNumber: finding.lineNumber,
                codeSnippet: finding.codeSnippet,
                reason: finding.title,
                findingID: finding.id
            )
        }
    }

    func refreshReportsAndProcesses() async {
        var combinedProcesses = await interactor.listSimulatorProcesses()
        let devicesToInspect: [PhysicalDevice] = if let selectedDev = router.selectedPhysicalDevice {
            [selectedDev]
        } else {
            Array(router.physicalDevices.filter(\.isConnected).prefix(2))
        }
        for dev in devicesToInspect {
            let devProcs = await interactor.listPhysicalDeviceProcesses(deviceID: dev.id, deviceName: dev.name)
            combinedProcesses.append(contentsOf: devProcs)
        }
        simulatorProcesses = combinedProcesses
        diagnosticReports = interactor.loadDiagnosticReports(
            projectName: router.projectURL?.lastPathComponent,
            simulatorAppNames: simulatorProcesses.map(\.name),
            includeSystemReports: showSystemReports
        )
        if let firstHang = diagnosticReports.first(where: { $0.kind == .hang }) {
            lastHangSeconds = interactor.extractHangDuration(reportPath: firstHang.filePath)
        } else {
            lastHangSeconds = nil
        }
        if let current = selectedProcess,
           !simulatorProcesses.contains(where: { $0.id == current.id }) {
            selectedProcess = nil
        }
        if selectedProcess == nil {
            selectedProcess = simulatorProcesses.first
        }
        if simulatorProcesses.isEmpty || selectedProcess == nil {
            resetRealtimeDebugSession()
        }
        seedStaticFreezesFromFindingsIfNeeded()
    }

    func toggleTelemetry() {
        if isTelemetryActive {
            telemetryTask?.cancel()
            telemetryTask = nil
            runtimeLeakTask?.cancel()
            runtimeLeakTask = nil
            isTelemetryActive = false
            isSamplingRuntimeLeaks = false
            return
        }

        isTelemetryActive = true
        telemetryTask = Task { [weak self] in
            guard let initialSelf = self else { return }
            if initialSelf.selectedProcess == nil {
                await initialSelf.refreshReportsAndProcesses()
            }
            guard !Task.isCancelled else { return }
            guard initialSelf.selectedProcess != nil else {
                initialSelf.isTelemetryActive = false
                initialSelf.router.statusMessage = AppStrings.Performance.noActiveSimProcess
                return
            }

            var tickCount = 0
            while !Task.isCancelled {
                guard let self else { break }
                if let proc = self.selectedProcess,
                   let sample = await self.interactor.sampleTelemetry(for: proc) {
                    guard !Task.isCancelled else { break }
                    self.recordTelemetryTick(sample: sample, process: proc)

                    if tickCount % 10 == 0 && !proc.isPhysicalDevice {
                        self.scheduleRuntimeDiagnosticsAndLeaks(pid: proc.id)
                    }
                    tickCount += 1
                } else {
                    await self.refreshReportsAndProcesses()
                    guard !Task.isCancelled else { break }
                    if self.selectedProcess == nil {
                        self.isTelemetryActive = false
                        self.resetRealtimeDebugSession()
                        self.router.statusMessage = AppStrings.Performance.processStopped
                        break
                    }
                }
                let intervalMs = Int(max(0.5, AppPreferencesStore().load().telemetryIntervalSeconds) * 1000)
                try? await Task.sleep(for: .milliseconds(intervalMs))
            }
        }
    }

    private func scheduleRuntimeDiagnosticsAndLeaks(pid: Int32) {
        guard !isSamplingRuntimeLeaks else { return }
        isSamplingRuntimeLeaks = true
        runtimeLeakTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSamplingRuntimeLeaks = false }
            let snapshot = await self.interactor.sampleRuntimeLeaks(pid: pid)
            guard !Task.isCancelled else { return }
            self.runtimeLeakSnapshot = snapshot

            let reports = self.interactor.loadDiagnosticReports(
                projectName: self.router.projectURL?.lastPathComponent,
                simulatorAppNames: self.simulatorProcesses.map(\.name),
                includeSystemReports: self.showSystemReports
            )
            guard !Task.isCancelled else { return }
            self.diagnosticReports = reports
            if let firstHang = reports.first(where: { $0.kind == .hang }) {
                self.lastHangSeconds = self.interactor.extractHangDuration(reportPath: firstHang.filePath)
            }
        }
    }

    private func recordTelemetryTick(sample: ProcessTelemetrySample, process: SimulatorProcessInfo) {
        liveCPU = sample.cpuPercent
        liveMemoryMB = sample.memoryMB
        memoryHistory.append(sample.memoryMB)
        if memoryHistory.count > AppConstants.Telemetry.historyCapacity { memoryHistory.removeFirst() }

        let threshold = AppConstants.Telemetry.freezeCPUThresholdPercent
        let stepSeconds = Double(AppConstants.Telemetry.pollIntervalMs) / 1000.0

        if sample.cpuPercent >= threshold {
            activeFreezeDurationSeconds += stepSeconds
            let primaryFinding = leakAndHangFindings.first(where: { $0.category == .mainThread }) ?? leakAndHangFindings.first
            var event = activeFreezeEvent ?? FreezeLagEvent(
                startedAt: sample.timestamp,
                durationSeconds: activeFreezeDurationSeconds,
                peakCPUPercent: sample.cpuPercent,
                memoryMB: sample.memoryMB,
                culpritSymbol: primaryFinding.map { "\($0.fileName):\($0.lineNumber)" } ?? process.name,
                fileName: primaryFinding?.fileName,
                lineNumber: primaryFinding?.lineNumber,
                codeSnippet: primaryFinding?.codeSnippet ?? "Main thread busy (\(String(format: "%.1f%%", sample.cpuPercent)) CPU)",
                reason: primaryFinding?.title ?? "High CPU / Main-Thread Stall",
                findingID: primaryFinding?.id
            )
            event.durationSeconds = activeFreezeDurationSeconds
            event.peakCPUPercent = max(event.peakCPUPercent, sample.cpuPercent)
            event.memoryMB = sample.memoryMB
            activeFreezeEvent = event
            lastHangSeconds = max(lastHangSeconds ?? 0, activeFreezeDurationSeconds)

            // Flatline plateau value: keep horizontal line at peak height while freeze persists
            let flatlineValue = event.peakCPUPercent
            cpuHistory.append(flatlineValue)
            if cpuHistory.count > AppConstants.Telemetry.historyCapacity { cpuHistory.removeFirst() }

            let point = TelemetryTimelinePoint(
                value: flatlineValue,
                isFreezeFlatline: true,
                elapsedFreezeSeconds: activeFreezeDurationSeconds,
                freezeEvent: event
            )
            cpuTimeline.append(point)
            if cpuTimeline.count > AppConstants.Telemetry.historyCapacity { cpuTimeline.removeFirst() }

            upsertCapturedFreezeEvent(event)
            scheduleStackSampleForActiveFreeze(process: process)
        } else {
            if activeFreezeEvent != nil {
                activeFreezeDurationSeconds = 0
                activeFreezeEvent = nil
                onSessionChanged?()
            }
            cpuHistory.append(sample.cpuPercent)
            if cpuHistory.count > AppConstants.Telemetry.historyCapacity { cpuHistory.removeFirst() }

            let point = TelemetryTimelinePoint(
                value: sample.cpuPercent,
                isFreezeFlatline: false,
                elapsedFreezeSeconds: 0,
                freezeEvent: nil
            )
            cpuTimeline.append(point)
            if cpuTimeline.count > AppConstants.Telemetry.historyCapacity { cpuTimeline.removeFirst() }
        }
    }

    private func upsertCapturedFreezeEvent(_ event: FreezeLagEvent) {
        if let idx = capturedFreezeEvents.firstIndex(where: { $0.id == event.id }) {
            capturedFreezeEvents[idx] = event
        } else {
            capturedFreezeEvents.insert(event, at: 0)
            if capturedFreezeEvents.count > AppConstants.Telemetry.maxCapturedFreezeEvents {
                capturedFreezeEvents.removeLast()
            }
            realtimeSessionFreezes.insert(event, at: 0)
            if realtimeSessionFreezes.count > 20 {
                realtimeSessionFreezes.removeLast()
            }
            NotificationCenter.default.post(
                name: Notification.Name("xscope.background.alert"),
                object: nil,
                userInfo: [
                    "category": "hang",
                    "title": "Critical Hang / Freeze Detected",
                    "body": "\(event.culpritSymbol) stalled (\(String(format: "%.1fs", event.durationSeconds))).",
                    "module": CompanionModule.performance.rawValue
                ]
            )
        }
    }

    private func scheduleStackSampleForActiveFreeze(process: SimulatorProcessInfo) {
        guard !isSamplingStack else { return }
        isSamplingStack = true
        let eventID = activeFreezeEvent?.id
        stackSampleTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSamplingStack = false }
            guard let hotSymbol = await self.interactor.sampleProcessCallStack(pid: process.id, processName: process.name),
                  !Task.isCancelled
            else { return }

            let matchedFinding = self.leakAndHangFindings.first { finding in
                let stem = (finding.fileName as NSString).deletingPathExtension
                return hotSymbol.localizedCaseInsensitiveContains(stem)
            } ?? self.leakAndHangFindings.first(where: { $0.category == .mainThread }) ?? self.leakAndHangFindings.first

            if var current = self.activeFreezeEvent, current.id == eventID {
                current.culpritSymbol = hotSymbol
                if let matchedFinding {
                    current.fileName = matchedFinding.fileName
                    current.lineNumber = matchedFinding.lineNumber
                    current.codeSnippet = matchedFinding.codeSnippet
                    current.reason = matchedFinding.title
                    current.findingID = matchedFinding.id
                }
                self.activeFreezeEvent = current
                self.upsertCapturedFreezeEvent(current)
            }
        }
    }

    func selectFreezeEvent(_ event: FreezeLagEvent) async {
        if let findingID = event.findingID,
           let finding = leakAndHangFindings.first(where: { $0.id == findingID }) {
            await selectFinding(finding)
            return
        }
        if let fileName = event.fileName,
           let finding = leakAndHangFindings.first(where: { $0.fileName == fileName }) {
            await selectFinding(finding)
            return
        }
        if let firstFinding = leakAndHangFindings.first {
            await selectFinding(firstFinding)
        }
    }

    func selectFinding(_ finding: CodeReviewFinding) async {
        proposalTask?.cancel()
        selectedFindingID = finding.id
        activeCrashAnalysis = nil
        crashSourceSnippet = nil
        let findingID = finding.id
        let path = router.projectURL.flatMap { router.findFile(named: finding.fileName, in: $0)?.path }
        let provider = agentProvider
        let apiKey = agentApiKey
        let ollamaModel = agentOllamaModel
        let task = Task { [weak self] in
            guard let self else { return }
            let proposal = await self.interactor.proposeFix(
                for: finding,
                filePath: path,
                provider: provider,
                apiKey: apiKey,
                ollamaModel: ollamaModel
            )
            guard !Task.isCancelled, self.selectedFindingID == findingID else { return }
            self.activeFixProposal = proposal
            self.router.statusMessage = AppStrings.Performance.agentFixReady(finding.fileName, finding.lineNumber)
        }
        proposalTask = task
        await task.value
    }

    func selectReport(_ report: DiagnosticReportItem) {
        proposalTask?.cancel()
        activeFixProposal = nil
        selectedFindingID = nil
        selectedReportName = report.fileName
        let content = interactor.readReportContent(at: report.filePath)
        selectedReportContent = content
        let analysis = interactor.analyzeCrashReport(content: content, processName: report.processName)
        activeCrashAnalysis = analysis
        if let fileName = analysis.sourceFileName, let projectURL = router.projectURL {
            crashSourceSnippet = interactor.locateCrashSource(
                fileName: fileName,
                lineNumber: analysis.sourceLineNumber,
                in: projectURL
            )
        } else {
            crashSourceSnippet = nil
        }
    }

    func openCrashInXcode() async {
        guard let fileName = crashSourceSnippet?.fileName ?? activeCrashAnalysis?.sourceFileName else {
            router.statusMessage = AppStrings.Performance.noFindingForXcode
            return
        }
        let line = crashSourceSnippet?.lineNumber ?? activeCrashAnalysis?.sourceLineNumber ?? 1
        await router.openInXcode(fileName: fileName, line: line)
    }

    func copyActiveDiff() {
        guard let proposal = activeFixProposal else { return }
        clipboard.copyString("- \(proposal.oldSnippet)\n+ \(proposal.newSnippet)")
        router.statusMessage = AppStrings.Common.copyDiff
    }

    func copyAntigravityFindingPrompt(openApp: Bool = true) {
        guard let finding = leakAndHangFindings.first(where: { $0.id == selectedFindingID }) else { return }
        let prompt = interactor.buildAntigravityPrompt(for: finding, filePath: activeFixProposal?.filePath)
        clipboard.copyString(prompt)
        router.statusMessage = AppStrings.Performance.antigravityPromptCopied
        if openApp { router.openAntigravity() }
    }

    func copyAntigravityCrashPrompt(openApp: Bool = true) {
        guard let crash = activeCrashAnalysis else { return }
        let prompt = interactor.buildAntigravityCrashPrompt(crash: crash, snippet: crashSourceSnippet)
        clipboard.copyString(prompt)
        router.statusMessage = AppStrings.Performance.antigravityPromptCopied
        if openApp { router.openAntigravity() }
    }

    func openInXcode(line: Int) async {
        let selectedFileName = leakAndHangFindings.first(where: { $0.id == selectedFindingID })?.fileName
        let proposalFileName = activeFixProposal?.filePath.map { URL(fileURLWithPath: $0).lastPathComponent }
        guard let fileName = proposalFileName ?? selectedFileName ?? leakAndHangFindings.first(where: { $0.lineNumber == line })?.fileName else {
            router.statusMessage = AppStrings.Performance.noFindingForXcode
            return
        }
        await router.openInXcode(fileName: fileName, line: line)
    }

    func openInstruments() {
        router.openInstruments()
    }

    func applyActiveFix() {
        guard let proposal = activeFixProposal else { return }
        if let path = proposal.filePath {
            do {
                let record = try interactor.applyPatch(
                    to: URL(fileURLWithPath: path),
                    oldSnippet: proposal.oldSnippet,
                    newSnippet: proposal.newSnippet,
                    lineNumber: proposal.lineNumber
                )
                lastRevertRecord = record
                activeFixProposal = nil
                selectedFindingID = nil
                codeReviewerPresenter.runAnalysis()
                router.statusMessage = AppStrings.Performance.patchAppliedToFile(URL(fileURLWithPath: path).lastPathComponent)
            } catch {
                router.statusMessage = error.localizedDescription
            }
        } else {
            guard codeReviewerPresenter.customSwiftCode.contains(proposal.oldSnippet) else {
                router.statusMessage = CompanionError.patchMismatch(fileName: "Snippet.swift").localizedDescription
                return
            }
            codeReviewerPresenter.customSwiftCode = codeReviewerPresenter.customSwiftCode
                .replacingOccurrences(of: proposal.oldSnippet, with: proposal.newSnippet)
            activeFixProposal = nil
            selectedFindingID = nil
            codeReviewerPresenter.runAnalysis()
            router.statusMessage = AppStrings.Performance.patchAppliedToEditor
        }
    }

    func revertLastPatch() {
        guard let record = lastRevertRecord else { return }
        do {
            try interactor.revertPatch(record)
            lastRevertRecord = nil
            activeFixProposal = nil
            selectedFindingID = nil
            codeReviewerPresenter.runAnalysis()
            router.statusMessage = AppStrings.Performance.patchRolledBack(record.fileURL.lastPathComponent)
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func copyMarkdownReport() {
        let md = DiagnosticReportExporter.buildPerformanceMarkdown(
            appName: selectedProcess?.name,
            cpuHistory: cpuHistory,
            memoryHistory: memoryHistory,
            freezes: capturedFreezeEvents
        )
        clipboard.copyString(md)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "XScope_Performance_Report.md"
        if panel.runModal() == .OK, let dest = panel.url {
            try? md.write(to: dest, atomically: true, encoding: .utf8)
            router.statusMessage = "Exported Performance report to \(dest.lastPathComponent) (also copied)."
        } else {
            router.statusMessage = "Performance Markdown report copied to clipboard."
        }
    }
}

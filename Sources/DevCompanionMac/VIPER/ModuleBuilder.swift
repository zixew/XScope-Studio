import Foundation
import DevCompanionCore

/// Assembles all 6 VIPER modules using `AppContainer` and `AppRouter`.
@MainActor
final class ModuleBuilder {
    let router: AppRouter
    let smartScanPresenter: SmartScanPresenter
    let crashlyticsPresenter: CrashlyticsPresenter
    let simulatorPresenter: SimulatorPresenter
    let codeReviewerPresenter: CodeReviewerPresenter
    let performancePresenter: PerformancePresenter
    let refactorPresenter: RefactorPresenter
    let unitTestPresenter: UnitTestPresenter
    let utilitiesPresenter: UtilitiesPresenter

    private let sessionStore: any ProjectSessionStoring

    init(container: AppContainer = AppContainer()) {
        self.sessionStore = container.sessionStore
        let router = AppRouter(
            agentService: container.agentService,
            preferencesStore: container.preferencesStore
        )
        self.router = router

        let simInteractor = SimulatorInteractor(service: container.simulatorService, liveReloadService: container.liveReloadService)
        let codeInteractor = CodeReviewerInteractor(engine: container.codeReviewEngine, agentService: container.agentService)
        let codePresenter = CodeReviewerPresenter(interactor: codeInteractor, router: router, clipboard: container.clipboard)
        self.codeReviewerPresenter = codePresenter

        let utilInteractor = UtilitiesInteractor(service: container.utilitiesService, agentService: container.agentService)
        let utilitiesPresenter = UtilitiesPresenter(
            interactor: utilInteractor,
            router: router,
            clipboard: container.clipboard
        )
        self.utilitiesPresenter = utilitiesPresenter

        let simPresenter = SimulatorPresenter(
            interactor: simInteractor,
            router: router,
            clipboard: container.clipboard,
            onProjectFilesChanged: {
                _ = codePresenter.runBackgroundProjectScan()
                utilitiesPresenter.scanLocalizations()
            }
        )
        self.simulatorPresenter = simPresenter

        let perfInteractor = PerformanceInteractor(
            diagnosticService: container.diagnosticService,
            telemetryService: container.telemetryService,
            agentService: container.agentService,
            secretStore: container.secretStore
        )
        let perfPresenter = PerformancePresenter(
            interactor: perfInteractor,
            router: router,
            codeReviewerPresenter: codePresenter,
            preferencesStore: container.preferencesStore,
            clipboard: container.clipboard
        )
        self.performancePresenter = perfPresenter

        let crashPresenter = CrashlyticsPresenter(
            interactor: perfInteractor,
            router: router,
            clipboard: container.clipboard
        )
        self.crashlyticsPresenter = crashPresenter

        let testInteractor = UnitTestInteractor(
            agentService: container.agentService,
            studio: container.unitTestStudio
        )
        let unitTestPresenter = UnitTestPresenter(
            interactor: testInteractor,
            router: router,
            clipboard: container.clipboard
        )
        self.unitTestPresenter = unitTestPresenter

        let refactorInteractor = RefactorInteractor(agentService: container.agentService)
        let refactorPresenter = RefactorPresenter(
            interactor: refactorInteractor,
            router: router,
            clipboard: container.clipboard
        )
        self.refactorPresenter = refactorPresenter

        let smartInteractor = SmartScanInteractor(
            simulatorService: container.simulatorService,
            diagnosticService: container.diagnosticService
        )
        let smartPresenter = SmartScanPresenter(
            interactor: smartInteractor,
            router: router,
            onScanFindings: {
                let count = codePresenter.runBackgroundProjectScan()
                unitTestPresenter.syncProjectContext(router.projectURL)
                if router.projectURL != nil {
                    utilitiesPresenter.scanLocalizations()
                } else {
                    utilitiesPresenter.resetProjectState()
                }
                Task {
                    await perfPresenter.refreshReportsAndProcesses()
                    await crashPresenter.refreshReports()
                }
                return count
            }
        )
        self.smartScanPresenter = smartPresenter

        smartPresenter.onProjectSwitched = { [weak self] oldURL, newURL in
            guard let self else { return }
            if let oldURL {
                self.saveSession(for: oldURL)
            }
            self.resetAllPresenterStates()
            if let newURL {
                self.restoreSession(for: newURL)
            }
        }

        codePresenter.onFindingsChanged = { [weak self] in
            guard let self else { return }
            self.performancePresenter.seedStaticFreezesFromFindingsIfNeeded()
            if let url = self.router.projectURL {
                self.saveSession(for: url)
            }
        }

        perfPresenter.onSessionChanged = { [weak self] in
            guard let self, let url = self.router.projectURL else { return }
            self.saveSession(for: url)
        }

        crashPresenter.onSessionChanged = { [weak self] in
            guard let self, let url = self.router.projectURL else { return }
            self.saveSession(for: url)
        }

        smartPresenter.onSessionChanged = { [weak self] in
            guard let self, let url = self.router.projectURL else { return }
            self.saveSession(for: url)
        }

        smartPresenter.onResetProjectData = { [weak self] in
            self?.resetCurrentProjectData()
        }

        smartPresenter.onExportBackup = { [weak self] in
            self?.exportBackup()
        }

        smartPresenter.onImportBackup = { [weak self] in
            self?.importBackup()
        }

        if let currentURL = router.projectURL {
            restoreSession(for: currentURL)
        }
    }

    func saveSession(for projectURL: URL) {
        let snapshot = ProjectSessionSnapshot(
            projectPath: projectURL.path,
            projectName: projectURL.lastPathComponent,
            liveCPU: performancePresenter.liveCPU,
            liveMemoryMB: performancePresenter.liveMemoryMB,
            cpuHistory: performancePresenter.cpuHistory,
            memoryHistory: performancePresenter.memoryHistory,
            lastHangSeconds: performancePresenter.lastHangSeconds,
            selectedProcessName: performancePresenter.selectedProcess?.name,
            capturedFreezeEvents: performancePresenter.capturedFreezeEvents,
            selectedReportPath: crashlyticsPresenter.selectedReportID,
            selectedReportName: crashlyticsPresenter.selectedReportName.isEmpty ? performancePresenter.selectedReportName : crashlyticsPresenter.selectedReportName,
            selectedReportContent: crashlyticsPresenter.selectedReportContent.isEmpty ? performancePresenter.selectedReportContent : crashlyticsPresenter.selectedReportContent,
            activeCrashAnalysis: crashlyticsPresenter.activeAnalysis ?? performancePresenter.activeCrashAnalysis,
            findings: codeReviewerPresenter.findings,
            hasAnalyzed: codeReviewerPresenter.hasAnalyzed,
            sourceFileName: unitTestPresenter.sourceFileName,
            testModuleName: unitTestPresenter.testModuleName,
            xcodeProjectPath: unitTestPresenter.xcodeProjectPath,
            schemeName: unitTestPresenter.schemeName,
            discoveredSchemes: unitTestPresenter.discoveredSchemes,
            generatedTestCode: unitTestPresenter.generatedTestCode,
            missingLocalizations: utilitiesPresenter.missingLocalizations,
            liveReloadScheme: simulatorPresenter.liveReloadScheme,
            lastReloadSummary: simulatorPresenter.lastReloadSummary
        )
        try? sessionStore.save(snapshot)
    }

    func restoreSession(for projectURL: URL) {
        guard let snap = sessionStore.load(for: projectURL) else {
            unitTestPresenter.syncProjectContext(projectURL)
            return
        }
        performancePresenter.liveCPU = snap.liveCPU
        performancePresenter.liveMemoryMB = snap.liveMemoryMB
        performancePresenter.cpuHistory = snap.cpuHistory
        performancePresenter.memoryHistory = snap.memoryHistory
        performancePresenter.cpuTimeline = snap.cpuHistory.map {
            TelemetryTimelinePoint(
                value: $0,
                isFreezeFlatline: $0 >= AppConstants.Telemetry.freezeCPUThresholdPercent
            )
        }
        performancePresenter.capturedFreezeEvents = snap.capturedFreezeEvents
        performancePresenter.lastHangSeconds = snap.lastHangSeconds
        performancePresenter.selectedReportName = snap.selectedReportName
        performancePresenter.selectedReportContent = snap.selectedReportContent
        performancePresenter.activeCrashAnalysis = snap.activeCrashAnalysis

        crashlyticsPresenter.selectedReportID = snap.selectedReportPath
        crashlyticsPresenter.selectedReportName = snap.selectedReportName
        crashlyticsPresenter.selectedReportContent = snap.selectedReportContent
        crashlyticsPresenter.activeAnalysis = snap.activeCrashAnalysis

        codeReviewerPresenter.findings = snap.findings
        // Keep Code Review in its clean initial non-state (`selectedScopeMode == nil`, `hasAnalyzed == false`, `hasUserInitiatedReview == false`)
        // until the user explicitly chooses a scope/category and runs Code Review.
        codeReviewerPresenter.hasAnalyzed = false
        codeReviewerPresenter.hasUserInitiatedReview = false
        codeReviewerPresenter.selectedScopeMode = nil
        smartScanPresenter.findingsCount = snap.findings.count

        unitTestPresenter.sourceFileName = snap.sourceFileName
        unitTestPresenter.testModuleName = snap.testModuleName
        unitTestPresenter.xcodeProjectPath = snap.xcodeProjectPath
        unitTestPresenter.schemeName = snap.schemeName
        unitTestPresenter.discoveredSchemes = snap.discoveredSchemes
        unitTestPresenter.generatedTestCode = snap.generatedTestCode

        utilitiesPresenter.missingLocalizations = snap.missingLocalizations
        simulatorPresenter.liveReloadScheme = snap.liveReloadScheme
        simulatorPresenter.lastReloadSummary = snap.lastReloadSummary
    }

    func resetAllPresenterStates() {
        performancePresenter.resetSessionState()
        crashlyticsPresenter.resetSessionState()
        codeReviewerPresenter.resetSessionState()
        unitTestPresenter.syncProjectContext(nil)
        refactorPresenter.resetSessionState()
        utilitiesPresenter.resetProjectState()
        simulatorPresenter.resetSessionState()
        smartScanPresenter.findingsCount = 0
        smartScanPresenter.reportCount = 0
    }

    func resetCurrentProjectData() {
        if let currentURL = router.projectURL {
            try? sessionStore.delete(for: currentURL)
        }
        resetAllPresenterStates()
        router.statusMessage = AppStrings.Overview.dataResetDone
    }

    func exportBackup() {
        if let currentURL = router.projectURL {
            saveSession(for: currentURL)
        }
        let defaultName = "DevCompanion_Backup_\(Int(Date().timeIntervalSince1970)).json"
        guard let destURL = router.pickBackupSaveURL(defaultName: defaultName) else { return }
        do {
            try sessionStore.exportBackup(to: destURL, projectURL: nil)
            router.statusMessage = AppStrings.Overview.backupExported(destURL.lastPathComponent)
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func importBackup() {
        guard let srcURL = router.pickBackupOpenURL() else { return }
        do {
            let count = try sessionStore.importBackup(from: srcURL)
            if let currentURL = router.projectURL {
                resetAllPresenterStates()
                restoreSession(for: currentURL)
            }
            router.statusMessage = AppStrings.Overview.backupRestored(count)
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }
}

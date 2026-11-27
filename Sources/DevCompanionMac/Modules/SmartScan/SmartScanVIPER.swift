import Foundation
import DevCompanionCore

// MARK: - SmartScan VIPER
protocol SmartScanInteractorProtocol: Sendable {
    func scanDevicesAndSimulators() async -> ([SimulatorDevice], [PhysicalDevice])
    func scanDiagnosticReports(projectName: String?) -> [DiagnosticReportItem]
}

struct SmartScanInteractor: SmartScanInteractorProtocol {
    private let simulatorService: SimulatorService
    private let diagnosticService: DiagnosticService

    init(simulatorService: SimulatorService, diagnosticService: DiagnosticService) {
        self.simulatorService = simulatorService
        self.diagnosticService = diagnosticService
    }

    func scanDevicesAndSimulators() async -> ([SimulatorDevice], [PhysicalDevice]) {
        async let sims = (try? simulatorService.listSimulators()) ?? []
        async let devs = (try? simulatorService.listPhysicalDevices()) ?? []
        return await (sims, devs)
    }

    func scanDiagnosticReports(projectName: String?) -> [DiagnosticReportItem] {
        diagnosticService.loadRecentReports(projectName: projectName, includeSystemReports: false)
    }
}

@MainActor
@Observable
final class SmartScanPresenter {
    var isScanning = false
    var reportCount = 0
    var findingsCount = 0
    var healthHistory: [ScanHealthSnapshot] = []

    private let interactor: any SmartScanInteractorProtocol
    private let router: AppRouter
    private let onScanFindings: @MainActor () -> Int
    private let healthStore = ScanHealthHistoryStore()
    var onProjectSwitched: (@MainActor (URL?, URL?) -> Void)?
    var onSessionChanged: (@MainActor () -> Void)?
    var onResetProjectData: (@MainActor () -> Void)?
    var onExportBackup: (@MainActor () -> Void)?
    var onImportBackup: (@MainActor () -> Void)?

    init(
        interactor: any SmartScanInteractorProtocol,
        router: AppRouter,
        onScanFindings: @escaping @MainActor () -> Int
    ) {
        self.interactor = interactor
        self.router = router
        self.onScanFindings = onScanFindings
        self.healthHistory = healthStore.load()
    }

    var bootedCount: Int { router.bootedSimulators.count }
    var totalSimulators: Int { router.simulators.count }
    var projectName: String? { router.projectURL?.lastPathComponent }
    var hasProject: Bool { router.projectURL != nil }

    func refreshDevicesAndReportsOnly() async {
        let (sims, devs) = await interactor.scanDevicesAndSimulators()
        router.simulators = sims.filter(\.isBooted)
        router.physicalDevices = devs.filter(\.isConnected)
        if let firstBooted = router.bootedSimulators.first {
            if !router.bootedSimulators.contains(where: { $0.id == router.selectedSimulatorUDID }) {
                router.selectedSimulatorUDID = firstBooted.id
            }
        } else {
            router.selectedSimulatorUDID = AppConstants.Defaults.defaultSimulatorUDID
        }
        reportCount = interactor.scanDiagnosticReports(projectName: projectName).count
    }

    func runSmartScan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        router.statusMessage = AppStrings.Overview.scanningMessage
        let (sims, devs) = await interactor.scanDevicesAndSimulators()
        router.simulators = sims.filter(\.isBooted)
        router.physicalDevices = devs.filter(\.isConnected)
        if let firstBooted = router.bootedSimulators.first {
            if !router.bootedSimulators.contains(where: { $0.id == router.selectedSimulatorUDID }) {
                router.selectedSimulatorUDID = firstBooted.id
            }
        } else {
            router.selectedSimulatorUDID = AppConstants.Defaults.defaultSimulatorUDID
        }

        reportCount = interactor.scanDiagnosticReports(projectName: projectName).count
        findingsCount = onScanFindings()
        let computedScore = max(0, min(100, 100 - (reportCount * 8) - (findingsCount * 2)))
        healthHistory = healthStore.record(
            ScanHealthSnapshot(
                score: computedScore,
                crashCount: reportCount,
                hangCount: 0,
                warningCount: findingsCount
            )
        )
        onSessionChanged?()
        router.statusMessage = AppStrings.Overview.scanCompleted(bootedCount, reportCount)
        NotificationCenter.default.post(
            name: Notification.Name("xscope.background.alert"),
            object: nil,
            userInfo: [
                "category": reportCount > 0 ? "crash" : "scan_complete",
                "title": reportCount > 0 ? "New Crash Reports Detected" : "Smart Scan Complete",
                "body": "\(bootedCount) booted simulators, \(reportCount) crash reports, \(findingsCount) findings.",
                "module": (reportCount > 0 ? CompanionModule.crashlytics : CompanionModule.smartScan).rawValue
            ]
        )
    }

    func chooseProjectFolder() {
        let oldURL = router.projectURL
        if let newURL = router.pickProjectFolder() {
            onProjectSwitched?(oldURL, newURL)
            Task { await runSmartScan() }
        }
    }

    func resetProject() {
        let oldURL = router.projectURL
        router.projectURL = nil
        onProjectSwitched?(oldURL, nil)
    }

    func resetProjectData() {
        onResetProjectData?()
    }

    func exportBackup() {
        onExportBackup?()
    }

    func importBackup() {
        onImportBackup?()
    }

    func openInstallerReleases() {
        router.openInstallerReleasesFolder()
    }
}

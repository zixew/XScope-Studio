import Foundation
import DevCompanionCore

// MARK: - Utilities VIPER
protocol UtilitiesInteractorProtocol: Sendable {
    func generateColorToken(name: String, hex: String) -> String
    func scanLocalizations(in url: URL) -> [LocalizationMissingEntry]
    func scanDerivedData() -> DerivedDataSummary
    func cleanDerivedData() throws -> Int
    func buildAntigravityL10nPrompt(missingEntries: [LocalizationMissingEntry], projectName: String?) -> String
}

struct UtilitiesInteractor: UtilitiesInteractorProtocol {
    private let service: XcodeUtilitiesService
    private let agentService: AgentService

    init(service: XcodeUtilitiesService, agentService: AgentService = AgentService()) {
        self.service = service
        self.agentService = agentService
    }

    func generateColorToken(name: String, hex: String) -> String {
        service.generateColorTokenCode(name: name, hex: hex)
    }

    func scanLocalizations(in url: URL) -> [LocalizationMissingEntry] {
        service.scanMissingLocalizationsInDirectory(at: url)
    }

    func scanDerivedData() -> DerivedDataSummary {
        service.scanDerivedDataSize()
    }

    func cleanDerivedData() throws -> Int {
        try service.cleanDerivedData()
    }

    func buildAntigravityL10nPrompt(missingEntries: [LocalizationMissingEntry], projectName: String?) -> String {
        agentService.buildAntigravityL10nPrompt(missingEntries: missingEntries, projectName: projectName)
    }
}

@MainActor
@Observable
final class UtilitiesPresenter {
    var missingLocalizations: [LocalizationMissingEntry] = [] {
        didSet {
            visibleL10nLimit = ProgressiveListChunker.defaultPageSize
        }
    }
    var visibleL10nLimit: Int = ProgressiveListChunker.defaultPageSize
    var derivedDataSummary: DerivedDataSummary?
    var tokenName = ""
    var tokenHex = ""
    var generatedTokenCode = ""
    var isScanningL10n = false
    var isRefreshingDerivedData = false
    var buildTimings: [BuildTimingTarget] = []
    var provisioningProfiles: [ProvisioningProfileSummary] = []
    var isScanningBuildAndSigning = false
    var unusedAssets: [UnusedAssetItem] = []
    var isScanningUnusedAssets = false

    private let interactor: any UtilitiesInteractorProtocol
    private let router: AppRouter
    private let clipboard: any ClipboardManaging
    private let buildInspector = BuildAndSigningInspector()
    private let assetAuditor = AssetAndDeadCodeAuditor()

    init(
        interactor: any UtilitiesInteractorProtocol,
        router: AppRouter,
        clipboard: any ClipboardManaging
    ) {
        self.interactor = interactor
        self.router = router
        self.clipboard = clipboard
    }

    var hasProject: Bool { router.projectURL != nil }
    var canGenerateColorToken: Bool {
        !tokenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tokenHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canCleanDerivedData: Bool {
        (derivedDataSummary?.projectCount ?? 0) > 0
    }

    var visibleMissingLocalizations: ArraySlice<LocalizationMissingEntry> {
        ProgressiveListChunker.visibleSlice(of: missingLocalizations, limit: visibleL10nLimit)
    }

    func loadMoreL10nIfNeeded(currentIndex: Int) {
        let total = missingLocalizations.count
        if ProgressiveListChunker.shouldLoadMore(currentIndex: currentIndex, currentLimit: visibleL10nLimit, totalCount: total) {
            visibleL10nLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleL10nLimit, totalCount: total)
        }
    }

    func loadMoreL10n() {
        let total = missingLocalizations.count
        visibleL10nLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleL10nLimit, totalCount: total)
    }

    func onAppear() {
        refreshDerivedData()
    }

    func copyAntigravityL10nPrompt(openApp: Bool = true) {
        guard !missingLocalizations.isEmpty else { return }
        let prompt = interactor.buildAntigravityL10nPrompt(
            missingEntries: missingLocalizations,
            projectName: router.projectURL?.lastPathComponent
        )
        clipboard.copyString(prompt)
        router.statusMessage = AppStrings.Performance.antigravityPromptCopied
        if openApp { router.openAntigravity() }
    }

    func resetProjectState() {
        missingLocalizations = []
    }

    func generateColorToken() {
        let name = tokenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = tokenHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !hex.isEmpty else {
            generatedTokenCode = ""
            return
        }
        generatedTokenCode = interactor.generateColorToken(name: name, hex: hex)
    }

    func copyGeneratedTokenCode() {
        guard !generatedTokenCode.isEmpty else { return }
        clipboard.copyString(generatedTokenCode)
        router.statusMessage = AppStrings.Common.copy
    }

    func scanLocalizations() {
        guard let projectURL = router.projectURL else {
            missingLocalizations = []
            router.statusMessage = AppStrings.Common.selectProjectFirst
            return
        }
        guard !isScanningL10n else { return }
        isScanningL10n = true
        let interactor = self.interactor
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                interactor.scanLocalizations(in: projectURL)
            }.value
            self.missingLocalizations = results
            self.isScanningL10n = false
            self.router.statusMessage = AppStrings.Utilities.l10nScanCompleted(results.count)
        }
    }

    func refreshDerivedData() {
        guard !isRefreshingDerivedData else { return }
        isRefreshingDerivedData = true
        let interactor = self.interactor
        Task {
            let summary = await Task.detached(priority: .utility) {
                interactor.scanDerivedData()
            }.value
            self.derivedDataSummary = summary
            self.isRefreshingDerivedData = false
        }
    }

    func cleanDerivedData() {
        guard !isRefreshingDerivedData else { return }
        isRefreshingDerivedData = true
        let interactor = self.interactor
        Task {
            do {
                let removed = try await Task.detached(priority: .userInitiated) {
                    try interactor.cleanDerivedData()
                }.value
                self.isRefreshingDerivedData = false
                self.refreshDerivedData()
                self.router.statusMessage = AppStrings.Utilities.derivedDataCleaned(removed)
            } catch {
                self.isRefreshingDerivedData = false
                self.router.statusMessage = error.localizedDescription
            }
        }
    }

    func scanBuildAndSigning() {
        guard !isScanningBuildAndSigning else { return }
        isScanningBuildAndSigning = true
        let inspector = self.buildInspector
        Task {
            let (timings, profiles) = await Task.detached(priority: .userInitiated) {
                (inspector.scanRecentBuildTimings(), inspector.scanProvisioningProfiles())
            }.value
            self.buildTimings = timings
            self.provisioningProfiles = profiles
            self.isScanningBuildAndSigning = false
            self.router.statusMessage = "Found \(timings.count) build targets & \(profiles.count) provisioning profiles."
        }
    }

    func scanUnusedAssets() {
        guard let projectURL = router.projectURL else {
            router.statusMessage = AppStrings.Common.selectProjectFirst
            return
        }
        guard !isScanningUnusedAssets else { return }
        isScanningUnusedAssets = true
        let auditor = self.assetAuditor
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                auditor.findUnusedImageAssets(in: projectURL)
            }.value
            self.unusedAssets = items
            self.isScanningUnusedAssets = false
            self.router.statusMessage = "Unused assets audit complete: \(items.count) unreferenced imagesets."
        }
    }

    func cleanUnavailableSimulators() {
        Task {
            do {
                let out = try await SimulatorService().deleteUnavailableSimulators()
                self.router.statusMessage = out.isSuccess ? "Unavailable simulators cleaned." : out.stderr
            } catch {
                self.router.statusMessage = error.localizedDescription
            }
        }
    }
}

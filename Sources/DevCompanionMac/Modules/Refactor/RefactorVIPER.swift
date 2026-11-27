import Foundation
import DevCompanionCore

protocol RefactorInteractorProtocol {
    func analyze(directoryURL: URL, moduleFilter: String?) -> [RefactorOpportunity]
    func buildCompactPrompt(opportunity: RefactorOpportunity, goal: String?) -> (prompt: String, budget: TokenBudgetEstimate)
    func applyPatch(filePath: String, oldSnippet: String, newSnippet: String) throws -> PatchRevertRecord
    func revertPatch(_ record: PatchRevertRecord) throws
}

final class RefactorInteractor: RefactorInteractorProtocol {
    private let engine: RefactorEngine
    private let agentService: AgentService

    init(engine: RefactorEngine = RefactorEngine(), agentService: AgentService) {
        self.engine = engine
        self.agentService = agentService
    }

    func analyze(directoryURL: URL, moduleFilter: String?) -> [RefactorOpportunity] {
        engine.analyze(directoryURL: directoryURL, moduleFilter: moduleFilter)
    }

    func buildCompactPrompt(opportunity: RefactorOpportunity, goal: String?) -> (prompt: String, budget: TokenBudgetEstimate) {
        engine.buildCompactRefactorPrompt(opportunity: opportunity, goal: goal)
    }

    func applyPatch(filePath: String, oldSnippet: String, newSnippet: String) throws -> PatchRevertRecord {
        try agentService.applyPatch(to: URL(fileURLWithPath: filePath), oldSnippet: oldSnippet, newSnippet: newSnippet, lineNumber: nil)
    }

    func revertPatch(_ record: PatchRevertRecord) throws {
        try agentService.revertPatch(record)
    }
}

@MainActor
@Observable
final class RefactorPresenter {
    private let interactor: any RefactorInteractorProtocol
    private let router: AppRouter
    private let clipboard: any ClipboardManaging

    var opportunities: [RefactorOpportunity] = []
    var selectedRule: RefactorRuleKind? = nil
    var searchQuery: String = ""
    var moduleFilter: String = ""
    var customGoal: String = ""
    var selectedOpportunityID: String?
    var isScanning: Bool = false
    var hasScanned: Bool = false
    var lastRevertRecord: PatchRevertRecord?

    init(
        interactor: any RefactorInteractorProtocol,
        router: AppRouter,
        clipboard: any ClipboardManaging
    ) {
        self.interactor = interactor
        self.router = router
        self.clipboard = clipboard
    }

    var hasProjectURL: Bool { router.projectURL != nil }
    var projectName: String { router.projectURL?.lastPathComponent ?? AppStrings.Common.noProjectSelected }

    var filteredOpportunities: [RefactorOpportunity] {
        opportunities.filter { item in
            if let rule = selectedRule, item.rule != rule { return false }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                let hit = item.fileName.lowercased().contains(q)
                    || item.symbolName.lowercased().contains(q)
                    || item.metricSummary.lowercased().contains(q)
                if !hit { return false }
            }
            return true
        }
    }

    var selectedOpportunity: RefactorOpportunity? {
        guard let id = selectedOpportunityID else { return filteredOpportunities.first }
        return filteredOpportunities.first(where: { $0.id == id }) ?? filteredOpportunities.first
    }

    var localFixCount: Int {
        opportunities.filter { $0.hasLocalFix }.count
    }

    var activeCompactPromptAndBudget: (prompt: String, budget: TokenBudgetEstimate)? {
        guard let opp = selectedOpportunity else { return nil }
        return interactor.buildCompactPrompt(opportunity: opp, goal: customGoal)
    }

    func count(for rule: RefactorRuleKind) -> Int {
        opportunities.filter { $0.rule == rule }.count
    }

    func scanProject() {
        guard let url = router.projectURL else {
            router.statusMessage = AppStrings.Common.selectProjectFirst
            return
        }
        isScanning = true
        let filter = moduleFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeFilter = filter.isEmpty ? nil : filter
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                RefactorEngine().analyze(directoryURL: url, moduleFilter: activeFilter)
            }.value
            self.opportunities = results
            self.selectedOpportunityID = results.first?.id
            self.hasScanned = true
            self.isScanning = false
            self.router.statusMessage = "\(AppStrings.Refactor.scanCompleted): \(results.count)"
        }
    }

    func applyLocalFix() {
        guard let opp = selectedOpportunity,
              opp.hasLocalFix,
              let old = opp.localOldSnippet,
              let new = opp.localNewSnippet else { return }
        do {
            lastRevertRecord = try interactor.applyPatch(filePath: opp.filePath, oldSnippet: old, newSnippet: new)
            router.statusMessage = AppStrings.Refactor.localFixApplied
            scanProject()
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func revertLastLocalFix() {
        guard let record = lastRevertRecord else { return }
        do {
            try interactor.revertPatch(record)
            lastRevertRecord = nil
            router.statusMessage = AppStrings.Performance.undoPatch
            scanProject()
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func copyCompactPrompt(openApp: Bool = true) {
        guard let bundle = activeCompactPromptAndBudget else { return }
        clipboard.copyString(bundle.prompt)
        router.statusMessage = "\(AppStrings.Performance.antigravityPromptCopied) (~\(bundle.budget.compactTokens) tokens, -\(bundle.budget.savedPercent)%)"
        if openApp { router.openAntigravity() }
    }

    func openInXcode() async {
        guard let opp = selectedOpportunity else { return }
        await router.openInXcode(fileName: opp.fileName, line: opp.startLine)
    }

    func resetSessionState() {
        opportunities = []
        selectedOpportunityID = nil
        hasScanned = false
        lastRevertRecord = nil
    }
}

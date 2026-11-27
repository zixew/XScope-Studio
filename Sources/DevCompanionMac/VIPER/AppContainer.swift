import Foundation
import DevCompanionCore

/// Composition Root injecting Core Services & Keychain into VIPER Interactors.
struct AppContainer: Sendable {
    let runner: any CommandExecuting
    let secretStore: any SecretStoring
    let preferencesStore: any PreferencesStoring
    let clipboard: any ClipboardManaging
    let simulatorService: SimulatorService
    let diagnosticService: DiagnosticService
    let telemetryService: ProcessTelemetryService
    let codeReviewEngine: CodeReviewEngine
    let unitTestStudio: UnitTestStudio
    let utilitiesService: XcodeUtilitiesService
    let agentService: AgentService
    let liveReloadService: LiveReloadService
    let sessionStore: any ProjectSessionStoring

    init(
        runner: any CommandExecuting = ProcessRunner(),
        secretStore: any SecretStoring = KeychainStore(),
        preferencesStore: any PreferencesStoring = UserDefaultsStore(),
        clipboard: any ClipboardManaging = MacOSClipboard(),
        sessionStore: any ProjectSessionStoring = FileProjectSessionStore()
    ) {
        self.runner = runner
        self.secretStore = secretStore
        self.preferencesStore = preferencesStore
        self.clipboard = clipboard
        self.sessionStore = sessionStore
        self.simulatorService = SimulatorService(runner: runner)
        self.diagnosticService = DiagnosticService(runner: runner)
        self.telemetryService = ProcessTelemetryService(runner: runner)
        self.codeReviewEngine = CodeReviewEngine()
        self.unitTestStudio = UnitTestStudio(runner: runner)
        self.utilitiesService = XcodeUtilitiesService()
        self.agentService = AgentService(runner: runner)
        self.liveReloadService = LiveReloadService(runner: runner)
    }
}

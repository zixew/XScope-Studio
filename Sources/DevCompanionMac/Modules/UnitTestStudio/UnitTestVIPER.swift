import Foundation
import AppKit
import DevCompanionCore

// MARK: - UnitTestStudio VIPER
protocol UnitTestInteractorProtocol: Sendable {
    func buildPlan(source: String, sourceFileName: String, projectURL: URL?, moduleName: String, framework: TestFrameworkKind) -> UnitTestPlacementPlan
    func writePlan(_ plan: UnitTestPlacementPlan, projectURL: URL) throws -> URL
    func discoverSchemes(projectPath: String) async throws -> XcodeProjectMetadata?
    func runTests(projectPath: String, scheme: String, destination: String) async throws -> CommandOutput
    func buildAntigravityTestPrompt(
        sourceCode: String,
        fileName: String,
        moduleName: String,
        framework: TestFrameworkKind,
        targetPath: String?,
        dependencyContext: String,
        targetCoveragePercent: Int
    ) -> String
}

struct UnitTestInteractor: UnitTestInteractorProtocol {
    private let agentService: AgentService
    private let studio: UnitTestStudio

    init(agentService: AgentService, studio: UnitTestStudio) {
        self.agentService = agentService
        self.studio = studio
    }

    func buildPlan(source: String, sourceFileName: String, projectURL: URL?, moduleName: String, framework: TestFrameworkKind) -> UnitTestPlacementPlan {
        agentService.buildUnitTestPlan(
            source: source,
            sourceFileName: sourceFileName,
            projectURL: projectURL,
            moduleName: moduleName,
            framework: framework
        )
    }

    func writePlan(_ plan: UnitTestPlacementPlan, projectURL: URL) throws -> URL {
        try agentService.writeApprovedTestPlan(plan, projectURL: projectURL)
    }

    func discoverSchemes(projectPath: String) async throws -> XcodeProjectMetadata? {
        try await studio.discoverProjectMetadata(projectPath: projectPath)
    }

    func runTests(projectPath: String, scheme: String, destination: String) async throws -> CommandOutput {
        try await studio.runXcodeBuildTest(projectPath: projectPath, scheme: scheme, destination: destination)
    }

    func buildAntigravityTestPrompt(
        sourceCode: String,
        fileName: String,
        moduleName: String,
        framework: TestFrameworkKind,
        targetPath: String?,
        dependencyContext: String,
        targetCoveragePercent: Int
    ) -> String {
        agentService.buildAntigravityUnitTestPrompt(
            sourceCode: sourceCode,
            fileName: fileName,
            moduleName: moduleName,
            framework: framework,
            targetPath: targetPath,
            dependencyContext: dependencyContext,
            targetCoveragePercent: targetCoveragePercent
        )
    }
}

@MainActor
@Observable
final class UnitTestPresenter {
    var sourceFileName = ""
    var testSourceCode: String = ""
    var testModuleName = ""
    var selectedFramework: TestFrameworkKind = .swiftTesting
    var placementPlan: UnitTestPlacementPlan?
    var generatedTestCode = ""
    var testRunOutput = ""
    var discoveredSchemes: [String] = []
    var xcodeProjectPath = ""
    var schemeName = ""
    var destination = AppConstants.Defaults.defaultDestination
    var isDiscoveringSchemes = false
    var isRunningTests = false

    // Cross-file Dependency Graph & Coverage
    var availableProjectTargets: [String] = []
    var selectedRelativeTarget = ""
    var resolvedDependencies: [SwiftDependencyNode] = []
    var isResolvingDependencies = false
    var coverageScope: CoverageScopeKind = .none
    var selectedCoverageFilePath = ""
    var selectedCoverageDirectoryPath = ""
    var targetCoveragePercent = 80
    var coverageReport: CoverageReportSummary?
    var isCheckingCoverage = false

    private let interactor: any UnitTestInteractorProtocol
    private let router: AppRouter
    private let clipboard: any ClipboardManaging
    private let dependencyResolver = UnitTestDependencyResolver()
    private let coverageService = CodeCoverageService()

    init(
        interactor: any UnitTestInteractorProtocol,
        router: AppRouter,
        clipboard: any ClipboardManaging
    ) {
        self.interactor = interactor
        self.router = router
        self.clipboard = clipboard
    }

    var displaySourceFileName: String {
        sourceFileName.isEmpty ? AppStrings.UnitTest.noFileLoaded : sourceFileName
    }

    var hasProject: Bool { router.projectURL != nil }
    var canBuildPlan: Bool { !testSourceCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func copyAntigravityTestPrompt(openApp: Bool = true) {
        guard canBuildPlan else { return }
        let resolvedModule = testModuleName.isEmpty ? (router.projectURL?.lastPathComponent ?? "AppModule") : testModuleName
        let resolvedFileName = sourceFileName.isEmpty ? "Source.swift" : sourceFileName
        let prompt = interactor.buildAntigravityTestPrompt(
            sourceCode: testSourceCode,
            fileName: resolvedFileName,
            moduleName: resolvedModule,
            framework: selectedFramework,
            targetPath: placementPlan?.operations.first?.relativePath,
            dependencyContext: UnitTestDependencyResolver.formatDependencyContext(resolvedDependencies),
            targetCoveragePercent: targetCoveragePercent
        )
        clipboard.copyString(prompt)
        router.statusMessage = AppStrings.Performance.antigravityPromptCopied
        if openApp { router.openAntigravity() }
    }

    func syncProjectContext(_ projectURL: URL?) {
        coverageScope = .none
        selectedCoverageFilePath = ""
        selectedCoverageDirectoryPath = ""
        coverageReport = nil
        resolvedDependencies = []
        selectedRelativeTarget = ""

        guard let projectURL else {
            availableProjectTargets = []
            testModuleName = ""
            xcodeProjectPath = ""
            discoveredSchemes = []
            schemeName = ""
            placementPlan = nil
            generatedTestCode = ""
            return
        }
        testModuleName = projectURL.lastPathComponent
        discoveredSchemes = []
        schemeName = ""
        if let entries = try? FileManager.default.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            if let workspace = entries.first(where: { $0.pathExtension == "xcworkspace" }) {
                xcodeProjectPath = workspace.path
            } else if let proj = entries.first(where: { $0.pathExtension == "xcodeproj" }) {
                xcodeProjectPath = proj.path
            } else {
                xcodeProjectPath = ""
            }
        }
        refreshAvailableProjectTargets(in: projectURL)
    }

    func refreshAvailableProjectTargets(in projectURL: URL) {
        let resolver = self.dependencyResolver
        Task {
            let targets = await Task.detached(priority: .utility) {
                resolver.listProjectSwiftTargets(in: projectURL)
            }.value
            self.availableProjectTargets = targets
        }
    }

    func selectProjectRelativeTarget(_ relativePath: String) {
        guard let projectURL = router.projectURL else { return }
        selectedRelativeTarget = relativePath
        let targetURL = projectURL.appendingPathComponent(relativePath)
        loadTargets([targetURL], autoDetectProject: false)
    }

    func pickSwiftFile() {
        let urls = router.pickSwiftFilesOrDirectory()
        guard !urls.isEmpty else { return }
        loadTargets(urls, autoDetectProject: true)
    }

    private func loadTargets(_ urls: [URL], autoDetectProject: Bool) {
        guard let first = urls.first else { return }
        if autoDetectProject {
            if let detectedRoot = UnitTestDependencyResolver.detectProjectRoot(startingAt: first) {
                let currentRoot = router.projectURL?.standardizedFileURL.path
                if currentRoot == nil || !(first.standardizedFileURL.path.hasPrefix(currentRoot!)) {
                    router.projectURL = detectedRoot
                    syncProjectContext(detectedRoot)
                } else if availableProjectTargets.isEmpty {
                    refreshAvailableProjectTargets(in: detectedRoot)
                }
            }
        }

        let collected = dependencyResolver.collectSwiftSources(from: urls)
        guard !collected.combinedSource.isEmpty else {
            router.statusMessage = "No Swift source files found in selection."
            return
        }
        sourceFileName = collected.displayTitle
        testSourceCode = collected.combinedSource
        if let root = router.projectURL {
            let rootPrefix = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : (root.standardizedFileURL.path + "/")
            if first.standardizedFileURL.path.hasPrefix(rootPrefix) {
                selectedRelativeTarget = String(first.standardizedFileURL.path.dropFirst(rootPrefix.count))
            }
        }
        buildPlacementPlan()
        resolveCrossFileDependencies(excludingFilePath: collected.primaryFilePath)
    }

    func resolveCrossFileDependencies(excludingFilePath: String? = nil) {
        guard let projectURL = router.projectURL, canBuildPlan, !isResolvingDependencies else { return }
        isResolvingDependencies = true
        let source = testSourceCode
        let resolver = self.dependencyResolver
        Task {
            let nodes = await Task.detached(priority: .userInitiated) {
                resolver.resolveDependencies(for: source, excludingFilePath: excludingFilePath, in: projectURL)
            }.value
            self.resolvedDependencies = nodes
            self.isResolvingDependencies = false
            self.router.statusMessage = "Resolved \(nodes.count) cross-file dependencies."
        }
    }

    func pickCoverageFile() {
        if let picked = router.pickSwiftFile() {
            selectedCoverageFilePath = picked.url.path
        }
    }

    func pickCoverageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let root = router.projectURL {
            panel.directoryURL = root
        }
        if panel.runModal() == .OK, let url = panel.url {
            selectedCoverageDirectoryPath = url.path
        }
    }

    var canCheckCoverage: Bool {
        guard hasProject, !isCheckingCoverage else { return false }
        switch coverageScope {
        case .none: return false
        case .file: return !selectedCoverageFilePath.isEmpty
        case .directory: return !selectedCoverageDirectoryPath.isEmpty
        case .project: return true
        }
    }

    func checkCoverage() async {
        guard let projectURL = router.projectURL, canCheckCoverage else { return }
        isCheckingCoverage = true
        defer { isCheckingCoverage = false }
        router.statusMessage = AppStrings.Enhancements.checkingCoverage
        do {
            let report = try await coverageService.runCoverage(
                projectURL: projectURL,
                xcodeProjectPath: xcodeProjectPath,
                scheme: schemeName,
                destination: destination,
                scope: coverageScope,
                selectedFilePath: selectedCoverageFilePath,
                selectedDirectoryPath: selectedCoverageDirectoryPath
            )
            coverageReport = report
            router.statusMessage = String(format: "Coverage: %.1f%% (%d/%d lines)", report.overallPercent, report.coveredLines, report.executableLines)
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func loadUncoveredFileForTesting(_ item: FileCoverageItem) {
        guard let content = try? String(contentsOfFile: item.filePath, encoding: .utf8) else { return }
        sourceFileName = item.fileName
        testSourceCode = content
        buildPlacementPlan()
        resolveCrossFileDependencies(excludingFilePath: item.filePath)
    }

    func buildPlacementPlan() {
        resolvedDependencies = []
        guard !testSourceCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            placementPlan = nil
            generatedTestCode = ""
            return
        }
        let resolvedModule = testModuleName.isEmpty ? (router.projectURL?.lastPathComponent ?? "AppModule") : testModuleName
        let resolvedFileName = sourceFileName.isEmpty ? "Source.swift" : sourceFileName
        let plan = interactor.buildPlan(
            source: testSourceCode,
            sourceFileName: resolvedFileName,
            projectURL: router.projectURL,
            moduleName: resolvedModule,
            framework: selectedFramework
        )
        placementPlan = plan
        generatedTestCode = plan.generatedCode
        router.statusMessage = AppStrings.UnitTest.planReady(plan.operations.count)
    }

    func copyGeneratedCode() {
        guard !generatedTestCode.isEmpty else { return }
        clipboard.copyString(generatedTestCode)
        router.statusMessage = AppStrings.Common.copyCode
    }

    func approveAndWritePlan() {
        guard let plan = placementPlan else { return }
        guard let projectURL = router.projectURL else {
            router.statusMessage = AppStrings.UnitTest.selectProjectToWrite
            return
        }
        do {
            let writtenURL = try interactor.writePlan(plan, projectURL: projectURL)
            router.statusMessage = AppStrings.UnitTest.testFileWritten(writtenURL.lastPathComponent)
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func discoverSchemes() async {
        guard !xcodeProjectPath.isEmpty, !isDiscoveringSchemes else { return }
        isDiscoveringSchemes = true
        defer { isDiscoveringSchemes = false }
        let name = URL(fileURLWithPath: xcodeProjectPath).lastPathComponent
        router.statusMessage = AppStrings.UnitTest.detectingSchemes(name)
        do {
            if let meta = try await interactor.discoverSchemes(projectPath: xcodeProjectPath) {
                discoveredSchemes = meta.schemes
                if let first = meta.schemes.first, schemeName.isEmpty {
                    schemeName = first
                }
                router.statusMessage = AppStrings.UnitTest.schemesFound(meta.schemes.count)
            } else {
                router.statusMessage = AppStrings.UnitTest.detectSchemesFailed
            }
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func runXcodeTests() async {
        guard !xcodeProjectPath.isEmpty, !schemeName.isEmpty, !isRunningTests else { return }
        isRunningTests = true
        defer { isRunningTests = false }
        router.statusMessage = AppStrings.UnitTest.runningTests(schemeName)
        do {
            let out = try await interactor.runTests(projectPath: xcodeProjectPath, scheme: schemeName, destination: destination)
            testRunOutput = out.stdout + (out.stderr.isEmpty ? "" : "\n--- STDERR ---\n" + out.stderr)
            router.statusMessage = out.isSuccess ? AppStrings.UnitTest.testsPassed : AppStrings.UnitTest.testsFailed
            NotificationCenter.default.post(
                name: Notification.Name("xscope.background.alert"),
                object: nil,
                userInfo: [
                    "category": "tests_complete",
                    "title": out.isSuccess ? "Unit Tests Passed" : "Unit Tests Failed",
                    "body": "Scheme \(schemeName) finished.",
                    "module": CompanionModule.unitTests.rawValue
                ]
            )
        } catch {
            testRunOutput = error.localizedDescription
            router.statusMessage = error.localizedDescription
        }
    }
}

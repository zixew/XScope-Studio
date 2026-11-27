import SwiftUI
import AppKit
import DevCompanionCore

enum CompanionModule: String, CaseIterable, Identifiable {
    case smartScan = "Overview"
    case crashlytics = "Crashlytics"
    case performance = "Leaks & Hangs"
    case codeReview = "Code Review"
    case simulator = "Simulator"
    case unitTests = "Unit Tests"
    case utilities = "Utilities"

    static let monitorModules: [CompanionModule] = [.smartScan, .crashlytics, .performance, .codeReview]
    static let toolModules: [CompanionModule] = [.simulator, .unitTests, .utilities]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: AppStrings.Navigation.overview
        case .crashlytics: AppStrings.Navigation.crashlytics
        case .simulator: AppStrings.Navigation.simulator
        case .performance: AppStrings.Navigation.leaksAndHangs
        case .codeReview: AppStrings.Navigation.codeReview
        case .unitTests: AppStrings.Navigation.unitTests
        case .utilities: AppStrings.Navigation.utilities
        }
    }

    var icon: String {
        switch self {
        case .smartScan: AppConstants.Icons.overview
        case .crashlytics: AppConstants.Icons.crashlytics
        case .simulator: AppConstants.Icons.iphone
        case .performance: AppConstants.Icons.performance
        case .codeReview: AppConstants.Icons.shieldCheck
        case .unitTests: AppConstants.Icons.unitTests
        case .utilities: AppConstants.Icons.utilities
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedModule: CompanionModule = .smartScan
    var projectURL: URL? {
        didSet {
            if let path = projectURL?.path {
                preferencesStore.set(path, forKey: AppConstants.StorageKeys.lastProjectPath)
            } else {
                preferencesStore.removeObject(forKey: AppConstants.StorageKeys.lastProjectPath)
            }
        }
    }
    var simulators: [SimulatorDevice] = []
    var physicalDevices: [PhysicalDevice] = []
    var selectedSimulatorUDID: String = AppConstants.Defaults.defaultSimulatorUDID
    var selectedPhysicalDeviceID: String?
    var statusMessage: String = AppStrings.Common.ready

    private let agentService: AgentService
    private let preferencesStore: any PreferencesStoring

    init(
        agentService: AgentService,
        preferencesStore: any PreferencesStoring = UserDefaultsStore()
    ) {
        self.agentService = agentService
        self.preferencesStore = preferencesStore
        if let savedPath = preferencesStore.string(forKey: AppConstants.StorageKeys.lastProjectPath),
           FileManager.default.fileExists(atPath: savedPath) {
            self.projectURL = URL(fileURLWithPath: savedPath)
        }
    }

    var bootedSimulators: [SimulatorDevice] {
        simulators.filter { $0.isBooted }
    }

    var activePhysicalDevices: [PhysicalDevice] {
        physicalDevices.filter { $0.isConnected }
    }

    var selectedPhysicalDevice: PhysicalDevice? {
        guard let id = selectedPhysicalDeviceID else { return nil }
        return activePhysicalDevices.first(where: { $0.id == id })
    }

    var hasAnyActiveTarget: Bool {
        !bootedSimulators.isEmpty || !activePhysicalDevices.isEmpty
    }

    var activeTargetLabel: String {
        if let dev = selectedPhysicalDevice {
            return "\(dev.name) (iOS \(dev.osVersion))"
        }
        if let sim = bootedSimulators.first(where: { $0.id == selectedSimulatorUDID }) ?? bootedSimulators.first {
            return sim.name
        }
        if let firstDev = activePhysicalDevices.first {
            return "\(firstDev.name) (iOS \(firstDev.osVersion))"
        }
        return AppStrings.TopBar.noBootedSimulator
    }

    func selectSimulator(_ udid: String) {
        selectedPhysicalDeviceID = nil
        selectedSimulatorUDID = udid
    }

    func selectPhysicalDevice(_ id: String) {
        selectedPhysicalDeviceID = id
    }

    func pickProjectFolder() -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AppStrings.Router.openProjectPrompt
        if panel.runModal() == .OK {
            projectURL = panel.url
            return panel.url
        }
        return nil
    }

    func pickSwiftFile() -> (url: URL, content: String)? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.swiftSource]
        if let projectURL {
            panel.directoryURL = projectURL
        }
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return (url, content)
        }
        return nil
    }

    func pickSwiftFilesOrDirectory() -> [URL] {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.swiftSource, .folder]
        if let projectURL {
            panel.directoryURL = projectURL
        }
        if panel.runModal() == .OK {
            return panel.urls
        }
        return []
    }

    func pickBackupSaveURL(defaultName: String) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url : nil
    }

    func pickBackupOpenURL() -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func openInXcode(fileName: String, line: Int) async {
        guard let projectURL else {
            statusMessage = AppStrings.Router.selectProjectFirst(fileName)
            return
        }
        let targetURL = await Task.detached(priority: .userInitiated) {
            Self.scanFile(named: fileName, in: projectURL)
        }.value
        guard let fileURL = targetURL else {
            statusMessage = AppStrings.Router.fileNotFound(fileName, projectURL.lastPathComponent)
            return
        }
        let container = AgentService.resolveXcodeContainer(in: projectURL)
        do {
            let out = try await agentService.openInXcode(
                filePath: fileURL.path,
                line: line,
                projectURL: projectURL
            )
            let containerLabel = container.url.lastPathComponent
            statusMessage = out.isSuccess
                ? "\(AppStrings.Router.openedInXcode(fileName, line)) (\(containerLabel))"
                : out.stderr
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openInstruments() {
        NSWorkspace.shared.open(URL(fileURLWithPath: AppConstants.Defaults.instrumentsAppPath))
    }

    func openAntigravity() {
        let appURL = URL(fileURLWithPath: "/Applications/Antigravity.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.open(appURL)
        }
    }

    func openInstallerReleasesFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloudReleases = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/DevCompanionReleases")
        let localReleases = home.appendingPathComponent("Documents/Projects/DevCompanionMac/dist/releases")

        let targetFolder: URL = if FileManager.default.fileExists(atPath: iCloudReleases.path) {
            iCloudReleases
        } else {
            localReleases
        }
        let dmgFile = targetFolder.appendingPathComponent("new_version/XScopeStudio.dmg")
        let legacyDmgFile = targetFolder.appendingPathComponent("new_version/DevCompanion.dmg")
        if FileManager.default.fileExists(atPath: dmgFile.path) {
            NSWorkspace.shared.selectFile(dmgFile.path, inFileViewerRootedAtPath: targetFolder.path)
        } else if FileManager.default.fileExists(atPath: legacyDmgFile.path) {
            NSWorkspace.shared.selectFile(legacyDmgFile.path, inFileViewerRootedAtPath: targetFolder.path)
        } else {
            NSWorkspace.shared.open(targetFolder)
        }
        statusMessage = AppStrings.Overview.openedInstallerFolder(targetFolder.path)
    }

    func findFile(named fileName: String, in root: URL) -> URL? {
        Self.scanFile(named: fileName, in: root)
    }

    nonisolated private static func scanFile(named fileName: String, in root: URL) -> URL? {
        // 1. Direct relative path match (e.g. "Modules/Transfer/TransferVC.swift")
        let directCandidate = root.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: directCandidate.path) {
            return directCandidate
        }

        let targetLeaf = (fileName as NSString).lastPathComponent
        let skippedDirs: Set<String> = ["Pods", ".build", "DerivedData", ".git", "Carthage", ".swiftpm"]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if skippedDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if name == targetLeaf {
                return url
            }
        }
        return nil
    }
}

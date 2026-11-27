import Foundation
import AppKit
import ImageIO
import DevCompanionCore

enum SimulatorWorkspaceTab: String, CaseIterable, Identifiable {
    case uiInspector = "2D / 3D Live UI Inspector"
    case quickTools = "Simulator Tools & Live Reload"
    case consoleAndLinks = "Console & Deep Links"

    var id: String { rawValue }
}

enum UIRenderDimensionMode: String, CaseIterable, Identifiable {
    case render2D = "2D Canvas"
    case render3D = "3D Exploded Layers"

    var id: String { rawValue }
}

struct InspectorTargetOption: Identifiable, Hashable {
    let id: String
    let title: String
    let isPhysicalDevice: Bool
}

// MARK: - Simulator VIPER
protocol SimulatorInteractorProtocol: Sendable {
    func listSimulators() async throws -> [SimulatorDevice]
    func listPhysicalDevices() async throws -> [PhysicalDevice]
    func listRunningApps(physicalDevices: [PhysicalDevice]) async -> [SimulatorProcessInfo]
    func buildUIHierarchy(for process: SimulatorProcessInfo, screenshotURL: URL?, in projectURL: URL?) -> [UIComponentNode]
    func buildComponentCodePatch(for node: UIComponentNode) -> (oldSnippet: String, newSnippet: String)
    func applyComponentPatch(to fileURL: URL, oldSnippet: String, newSnippet: String, lineNumber: Int?) throws -> PatchRevertRecord
    func revertComponentPatch(_ record: PatchRevertRecord) throws
    func setAppearance(_ appearance: SimulatorAppearance, udid: String) async throws -> CommandOutput
    func setDynamicType(_ size: DynamicTypeSizeOption, udid: String) async throws -> CommandOutput
    func overrideStatusBar(udid: String) async throws -> CommandOutput
    func openDeepLink(_ url: String, udid: String) async throws -> CommandOutput
    func sendPush(bundleID: String, title: String, body: String, udid: String) async throws -> CommandOutput
    func captureScreenshot(to url: URL, udid: String) async throws -> CommandOutput
    func capturePhysicalDeviceScreenshot(deviceID: String, to url: URL) async throws -> CommandOutput
    func incrementalBuildAndLaunch(projectPath: String, scheme: String, simulatorUDID: String, destination: String) async throws -> CommandOutput
}

struct SimulatorInteractor: SimulatorInteractorProtocol {
    private let service: SimulatorService
    private let liveReloadService: LiveReloadService
    private let telemetryService: ProcessTelemetryService
    private let hierarchyService: UIHierarchyInspectorService
    private let agentService: AgentService

    init(
        service: SimulatorService,
        liveReloadService: LiveReloadService = LiveReloadService(),
        telemetryService: ProcessTelemetryService = ProcessTelemetryService(),
        hierarchyService: UIHierarchyInspectorService = UIHierarchyInspectorService(),
        agentService: AgentService = AgentService()
    ) {
        self.service = service
        self.liveReloadService = liveReloadService
        self.telemetryService = telemetryService
        self.hierarchyService = hierarchyService
        self.agentService = agentService
    }

    func listSimulators() async throws -> [SimulatorDevice] { try await service.listSimulators() }
    func listPhysicalDevices() async throws -> [PhysicalDevice] { try await service.listPhysicalDevices() }

    func listRunningApps(physicalDevices: [PhysicalDevice]) async -> [SimulatorProcessInfo] {
        var procs = await telemetryService.listRunningSimulatorProcesses()
        for dev in physicalDevices.filter(\.isConnected).prefix(2) {
            let devProcs = await telemetryService.listRunningPhysicalDeviceProcesses(deviceID: dev.id, deviceName: dev.name)
            procs.append(contentsOf: devProcs)
        }
        return procs
    }

    func buildUIHierarchy(for process: SimulatorProcessInfo, screenshotURL: URL?, in projectURL: URL?) -> [UIComponentNode] {
        hierarchyService.buildHierarchy(for: process, screenshotURL: screenshotURL, in: projectURL)
    }

    func buildComponentCodePatch(for node: UIComponentNode) -> (oldSnippet: String, newSnippet: String) {
        hierarchyService.buildCodePatch(for: node)
    }

    func applyComponentPatch(to fileURL: URL, oldSnippet: String, newSnippet: String, lineNumber: Int?) throws -> PatchRevertRecord {
        try agentService.applyPatch(to: fileURL, oldSnippet: oldSnippet, newSnippet: newSnippet, lineNumber: lineNumber)
    }

    func revertComponentPatch(_ record: PatchRevertRecord) throws {
        try agentService.revertPatch(record)
    }

    func setAppearance(_ appearance: SimulatorAppearance, udid: String) async throws -> CommandOutput {
        try await service.setAppearance(appearance, udid: udid)
    }
    func setDynamicType(_ size: DynamicTypeSizeOption, udid: String) async throws -> CommandOutput {
        try await service.setDynamicType(size, udid: udid)
    }
    func overrideStatusBar(udid: String) async throws -> CommandOutput {
        try await service.overrideStatusBarClean(udid: udid)
    }
    func openDeepLink(_ url: String, udid: String) async throws -> CommandOutput {
        try await service.openDeepLink(url, udid: udid)
    }
    func sendPush(bundleID: String, title: String, body: String, udid: String) async throws -> CommandOutput {
        try await service.sendPushNotification(bundleID: bundleID, title: title, body: body, udid: udid)
    }
    func captureScreenshot(to url: URL, udid: String) async throws -> CommandOutput {
        try await service.captureScreenshot(to: url, udid: udid)
    }
    func capturePhysicalDeviceScreenshot(deviceID: String, to url: URL) async throws -> CommandOutput {
        try await service.capturePhysicalDeviceScreenshot(deviceID: deviceID, to: url)
    }
    func incrementalBuildAndLaunch(projectPath: String, scheme: String, simulatorUDID: String, destination: String) async throws -> CommandOutput {
        try await liveReloadService.incrementalBuildAndLaunch(
            projectPath: projectPath,
            scheme: scheme,
            simulatorUDID: simulatorUDID,
            destination: destination
        )
    }
}

@MainActor
@Observable
final class SimulatorPresenter {
    var workspaceTab: SimulatorWorkspaceTab = .uiInspector
    var renderMode: UIRenderDimensionMode = .render3D
    var runningApps: [SimulatorProcessInfo] = []
    var selectedTargetID: String? {
        didSet {
            if oldValue != selectedTargetID {
                syncTargetSelectionToRouterAndPickOpenedApp()
            }
        }
    }
    var selectedRunningApp: SimulatorProcessInfo? {
        didSet {
            if oldValue?.id != selectedRunningApp?.id {
                Task { await captureHierarchyForSelectedApp() }
            }
        }
    }
    var componentNodes: [UIComponentNode] = [] {
        didSet {
            visibleNodeLimit = ProgressiveListChunker.defaultPageSize
        }
    }
    var visibleNodeLimit: Int = ProgressiveListChunker.defaultPageSize
    var selectedNodeID: String? {
        didSet {
            if oldValue != selectedNodeID {
                loadDraftForSelection()
            }
        }
    }
    var draftNode: UIComponentNode?
    var originalSourceSlice: String = ""
    var draftSourceSlice: String = ""
    var isDebugBridgeConnected: Bool = false
    var lastActionStatus: String = ""
    var collapsedNodeIDs: Set<String> = []
    var hierarchySearchQuery: String = ""
    var liveScreenImagePath: String?
    var liveScreenCGImage: CGImage?
    var preCroppedTextures: [String: CGImage] = [:]
    var cameraResetCounter: Int = 0
    var isCapturingHierarchy = false
    var isLiveScreenSyncActive = false
    var rotationAngleDegrees: Double = -28
    var pitchAngleDegrees: Double = 8
    var layerSpacing: Double = 32
    var canvasZoom: Double = 1.0
    var showWireframesOnly: Bool = false
    var displayMode: HierarchyDisplayMode = .wireframesAndContents
    var minDepthRatio: Double = 0.0
    var maxDepthRatio: Double = 1.0
    var lastComponentRevertRecord: PatchRevertRecord?

    var deepLinkURL = ""
    var deepLinkPresetTitle = ""
    var deepLinkPresets: [DeepLinkPreset] = []
    var pushBundleID = ""
    var pushTitle = ""
    var pushBody = ""
    var isLiveReloadActive = false
    var liveReloadScheme = ""
    var lastReloadSummary = ""

    // Live Simulator Console (os_log)
    var logLevelFilter: SimulatorLogLevel = .all
    var logSearchQuery = ""
    var isStreamingLogs = false
    var logEntries: [SimulatorLogEntry] = []

    // App Sandbox & Location/Privacy
    var sandboxBundleID = ""
    var sandboxSnapshot: SimulatorSandboxSnapshot?
    var isInspectingSandbox = false
    var customLatitude = "-6.2088"
    var customLongitude = "106.8456"
    var isRecordingVideo = false

    private let interactor: any SimulatorInteractorProtocol
    private let router: AppRouter
    private let clipboard: any ClipboardManaging
    private let fileWatcher = ProjectFileWatcher()
    private let onProjectFilesChanged: @MainActor () -> Void
    private let deepLinkStore = DeepLinkPresetStore()
    private let sandboxService = SimulatorSandboxService()
    private let bridgeService = XScopeDebugBridgeService()
    private let hierarchyInspector = UIHierarchyInspectorService()
    private var logBuffer = SimulatorLogRingBuffer(maxCapacity: AppPreferencesStore().load().logBufferCapacity)
    private var logStreamProcess: Process?
    private var videoRecordProcess: Process?
    private var videoTempURL: URL?
    private var logFlushTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var liveScreenSyncTask: Task<Void, Never>?

    init(
        interactor: any SimulatorInteractorProtocol,
        router: AppRouter,
        clipboard: any ClipboardManaging,
        onProjectFilesChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.interactor = interactor
        self.router = router
        self.clipboard = clipboard
        self.onProjectFilesChanged = onProjectFilesChanged
        self.deepLinkPresets = deepLinkStore.load()
    }

    var hasProject: Bool { router.projectURL != nil }
    var hasBootedSimulator: Bool { bootedCount > 0 }
    var physicalDevices: [PhysicalDevice] { router.activePhysicalDevices }
    var selectedPhysicalDeviceID: String? { router.selectedPhysicalDeviceID }

    var resolvedBootedUDID: String {
        if let match = router.bootedSimulators.first(where: { $0.id == router.selectedSimulatorUDID }) {
            return match.id
        }
        return router.bootedSimulators.first?.id ?? AppConstants.Defaults.defaultSimulatorUDID
    }

    var selectedNodeIndex: Int? {
        guard let id = selectedNodeID else { return componentNodes.indices.first }
        return componentNodes.firstIndex(where: { $0.id == id }) ?? componentNodes.indices.first
    }

    var selectedNode: UIComponentNode? {
        guard let idx = selectedNodeIndex, idx < componentNodes.count else { return nil }
        return componentNodes[idx]
    }

    var visibleComponentNodes: ArraySlice<UIComponentNode> {
        ProgressiveListChunker.visibleSlice(of: componentNodes, limit: visibleNodeLimit)
    }

    func loadMoreNodesIfNeeded(currentIndex: Int) {
        let total = componentNodes.count
        if ProgressiveListChunker.shouldLoadMore(currentIndex: currentIndex, currentLimit: visibleNodeLimit, totalCount: total) {
            visibleNodeLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleNodeLimit, totalCount: total)
        }
    }

    func loadMoreNodes() {
        let total = componentNodes.count
        visibleNodeLimit = ProgressiveListChunker.nextLimit(currentLimit: visibleNodeLimit, totalCount: total)
    }

    func selectPhysicalDevice(_ device: PhysicalDevice) {
        router.selectPhysicalDevice(device.id)
        router.statusMessage = "\(AppStrings.TopBar.activeDeviceTarget): \(device.name) (iOS \(device.osVersion))"
    }

    var canOpenDeepLink: Bool {
        hasBootedSimulator && !deepLinkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canSendPush: Bool {
        hasBootedSimulator && !pushBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resetSessionState() {
        watchTask?.cancel()
        watchTask = nil
        liveScreenSyncTask?.cancel()
        liveScreenSyncTask = nil
        isLiveScreenSyncActive = false
        isLiveReloadActive = false
        liveReloadScheme = ""
        lastReloadSummary = ""
        componentNodes = []
        selectedNodeID = nil
        liveScreenImagePath = nil
        liveScreenCGImage = nil
        preCroppedTextures = [:]
        lastComponentRevertRecord = nil
    }

    func toggleLiveScreenSync() {
        if isLiveScreenSyncActive {
            liveScreenSyncTask?.cancel()
            liveScreenSyncTask = nil
            isLiveScreenSyncActive = false
            return
        }
        isLiveScreenSyncActive = true
        liveScreenSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isLiveScreenSyncActive else { break }
                await self.captureHierarchyForSelectedApp()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    var availableTargets: [InspectorTargetOption] {
        let sims = router.bootedSimulators.map {
            InspectorTargetOption(id: $0.id, title: "[SIM] \($0.name)", isPhysicalDevice: false)
        }
        let devs = router.activePhysicalDevices.map {
            InspectorTargetOption(id: $0.id, title: "[DEVICE] \($0.name) (iOS \($0.osVersion))", isPhysicalDevice: true)
        }
        return sims + devs
    }

    var filteredRunningApps: [SimulatorProcessInfo] {
        guard let targetID = selectedTargetID,
              let target = availableTargets.first(where: { $0.id == targetID }) else {
            return []
        }
        let projName = router.projectURL?.lastPathComponent
        return ProcessTelemetryService.filterOpenedAppsForTarget(
            runningApps,
            targetID: target.id,
            isPhysicalDevice: target.isPhysicalDevice,
            projectName: projName
        )
    }

    private func syncTargetSelectionToRouterAndPickOpenedApp() {
        guard let targetID = selectedTargetID,
              let target = availableTargets.first(where: { $0.id == targetID }) else {
            selectedRunningApp = nil
            componentNodes = []
            selectedNodeID = nil
            return
        }
        if target.isPhysicalDevice {
            router.selectPhysicalDevice(target.id)
        } else {
            router.selectSimulator(target.id)
        }
        let opened = filteredRunningApps
        if let current = selectedRunningApp, opened.contains(where: { $0.id == current.id }) {
            return
        }
        selectedRunningApp = opened.first
    }

    func refreshRunningAppsAndHierarchy() async {
        await refreshDevices()
        let apps = await interactor.listRunningApps(physicalDevices: router.activePhysicalDevices)
        runningApps = apps
        if let targetID = selectedTargetID, !availableTargets.contains(where: { $0.id == targetID }) {
            selectedTargetID = nil
        }
        guard selectedTargetID != nil else {
            selectedRunningApp = nil
            return
        }
        let opened = filteredRunningApps
        if let current = selectedRunningApp, !opened.contains(where: { $0.id == current.id }) {
            selectedRunningApp = nil
        }
        if selectedRunningApp == nil {
            selectedRunningApp = opened.first
        } else {
            await captureHierarchyForSelectedApp()
        }
    }

    func captureHierarchyForSelectedApp() async {
        guard let app = selectedRunningApp else {
            componentNodes = []
            selectedNodeID = nil
            liveScreenImagePath = nil
            liveScreenCGImage = nil
            return
        }
        guard !isCapturingHierarchy else { return }
        isCapturingHierarchy = true
        defer { isCapturingHierarchy = false }

        let screenURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xscope_live_screen_\(app.id).png")
        var capturedURL: URL?

        // 1. Capture live screen from either Physical iPhone (devicectl) or Booted Simulator (simctl)
        if app.isPhysicalDevice,
           let devID = router.activePhysicalDevices.first(where: { $0.name == app.deviceName })?.id
            ?? router.selectedPhysicalDeviceID
            ?? router.activePhysicalDevices.first?.id {
            if let out = try? await interactor.capturePhysicalDeviceScreenshot(deviceID: devID, to: screenURL),
               out.isSuccess,
               FileManager.default.fileExists(atPath: screenURL.path) {
                capturedURL = screenURL
            }
        } else if hasBootedSimulator && !app.isPhysicalDevice {
            if let out = try? await interactor.captureScreenshot(to: screenURL, udid: resolvedBootedUDID),
               out.isSuccess,
               FileManager.default.fileExists(atPath: screenURL.path) {
                capturedURL = screenURL
            }
        }

        // 2. Try Live Debug Bridge GET /hierarchy first; fallback to Vision OCR/Rectangle + Swift AST
        let bridgeNodes = await bridgeService.fetchHierarchy()
        isDebugBridgeConnected = (bridgeNodes != nil)

        let interactorRef = interactor
        let projURL = router.projectURL
        let screenFileURL = capturedURL
        let (cgImg, nodes, crops) = await Task.detached { () -> (CGImage?, [UIComponentNode], [String: CGImage]) in
            var decoded: CGImage?
            if let screenFileURL,
               let src = CGImageSourceCreateWithURL(screenFileURL as CFURL, nil) {
                decoded = CGImageSourceCreateImageAtIndex(src, 0, nil)
            }
            let extracted = bridgeNodes ?? interactorRef.buildUIHierarchy(for: app, screenshotURL: screenFileURL, in: projURL)
            let croppedMap = decoded.map { UIHierarchyInspectorService.preCropTextures(from: $0, nodes: extracted) } ?? [:]
            return (decoded, extracted, croppedMap)
        }.value

        if let screenFileURL {
            liveScreenImagePath = screenFileURL.path
        }
        if let cgImg {
            liveScreenCGImage = cgImg
        }
        preCroppedTextures = crops

        componentNodes = nodes
        if selectedNodeID == nil || !nodes.contains(where: { $0.id == selectedNodeID }) {
            selectedNodeID = nodes.last?.id ?? nodes.first?.id
        }
    }

    func selectComponent(_ node: UIComponentNode) {
        selectedNodeID = node.id
    }

    var visibleHierarchyNodes: [UIComponentNode] {
        let q = hierarchySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            return componentNodes.filter {
                $0.name.lowercased().contains(q)
                    || $0.className.lowercased().contains(q)
                    || $0.kind.rawValue.lowercased().contains(q)
                    || $0.fileName.lowercased().contains(q)
            }
        }
        var hiddenByAncestor: Set<String> = []
        var visible: [UIComponentNode] = []
        for node in componentNodes {
            if let pid = node.parentID, (collapsedNodeIDs.contains(pid) || hiddenByAncestor.contains(pid)) {
                hiddenByAncestor.insert(node.id)
                continue
            }
            visible.append(node)
        }
        return visible
    }

    func toggleNodeCollapse(_ id: String) {
        if collapsedNodeIDs.contains(id) {
            collapsedNodeIDs.remove(id)
        } else {
            collapsedNodeIDs.insert(id)
        }
    }

    func expandAllNodes() {
        collapsedNodeIDs.removeAll()
    }

    func collapseToContainers() {
        collapsedNodeIDs = Set(componentNodes.filter { $0.depth >= 1 && $0.childCount > 0 }.map(\.id))
    }

    func reset3DCamera() {
        rotationAngleDegrees = -28
        pitchAngleDegrees = 8
        layerSpacing = 32
        canvasZoom = 1.0
        showWireframesOnly = false
        displayMode = .wireframesAndContents
        minDepthRatio = 0.0
        maxDepthRatio = 1.0
        cameraResetCounter += 1
    }

    var breadcrumbNodes: [UIComponentNode] {
        UIHierarchyInspectorService.ancestorBreadcrumb(for: selectedNodeID, in: componentNodes)
    }

    var hasUnappliedChanges: Bool {
        guard let selected = selectedNode, let draft = draftNode else { return false }
        return selected != draft || draftSourceSlice != originalSourceSlice
    }

    func inspectNode(_ id: String) {
        selectedNodeID = id
    }

    func loadDraftForSelection() {
        guard var node = selectedNode else {
            draftNode = nil
            originalSourceSlice = ""
            draftSourceSlice = ""
            return
        }
        let resolvedPath = node.filePath ?? router.projectURL.flatMap { router.findFile(named: node.fileName, in: $0)?.path }
        if let path = resolvedPath,
           let fullSource = try? String(contentsOfFile: path, encoding: .utf8) {
            if node.actions.isEmpty {
                node.actions = hierarchyInspector.discoverActions(in: fullSource, componentName: node.name)
            }
            if node.constraints == ComponentConstraints() {
                node.constraints = hierarchyInspector.parseConstraints(in: fullSource, aroundLine: node.lineNumber)
            }
            let slice = hierarchyInspector.loadSurroundingSource(filePath: path, lineNumber: node.lineNumber, radius: 14) ?? node.codeSnippet
            originalSourceSlice = slice
            draftSourceSlice = slice
        } else {
            originalSourceSlice = node.codeSnippet
            draftSourceSlice = node.codeSnippet
        }
        draftNode = node
    }

    func applyDraftToPreview() {
        guard let idx = selectedNodeIndex, var draft = draftNode else { return }
        draft.isEdited = true
        componentNodes[idx] = draft
        draftNode = draft
        router.statusMessage = "Applied preview for \(draft.name)"
        Task {
            if await bridgeService.pingBridge() {
                isDebugBridgeConnected = true
                _ = await bridgeService.sendMutation(node: draft)
            }
        }
    }

    func discardDraft() {
        draftNode = selectedNode
        draftSourceSlice = originalSourceSlice
        router.statusMessage = "Discarded unapplied draft"
    }

    func applyDirectCodeToXcode() {
        guard let idx = selectedNodeIndex else { return }
        let node = componentNodes[idx]
        let filePath = node.filePath ?? router.projectURL.flatMap { router.findFile(named: node.fileName, in: $0)?.path }
        guard let path = filePath else {
            router.statusMessage = AppStrings.Performance.noFindingForXcode
            return
        }
        guard draftSourceSlice != originalSourceSlice else {
            applyComponentChangesToSwiftCode()
            return
        }
        do {
            let record = try interactor.applyComponentPatch(
                to: URL(fileURLWithPath: path),
                oldSnippet: originalSourceSlice,
                newSnippet: draftSourceSlice,
                lineNumber: node.lineNumber
            )
            lastComponentRevertRecord = record
            originalSourceSlice = draftSourceSlice
            router.statusMessage = AppStrings.Performance.patchAppliedToFile(node.fileName)
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func checkBridgeStatus() async {
        isDebugBridgeConnected = await bridgeService.pingBridge()
    }

    func invokeActionViaBridge(_ action: ComponentActionBinding) async {
        let ok = await bridgeService.invokeAction(selectorName: action.selectorName, targetName: selectedNode?.name ?? "")
        if ok {
            isDebugBridgeConnected = true
        } else {
            isDebugBridgeConnected = await bridgeService.pingBridge()
        }
        if ok {
            lastActionStatus = "Invoked `\(action.selectorName)` in live app"
            router.statusMessage = lastActionStatus
        } else {
            lastActionStatus = "Bridge offline — install XScopeDebugBridge.swift or use Simulator Tap"
            router.statusMessage = lastActionStatus
        }
    }

    func triggerComponentTapInSimulator() async {
        guard let node = draftNode ?? selectedNode else { return }
        let centerX = node.normalizedX + node.normalizedWidth / 2.0
        let centerY = node.normalizedY + node.normalizedHeight / 2.0
        let script = """
        tell application "Simulator" to activate
        tell application "System Events"
            tell process "Simulator"
                if (count of windows) > 0 then
                    set wPos to position of window 1
                    set wSize to size of window 1
                    set tapX to (item 1 of wPos) + ((item 1 of wSize) * \(String(format: "%.3f", centerX)))
                    set tapY to (item 2 of wPos) + ((item 2 of wSize) * \(String(format: "%.3f", centerY)))
                    click at {tapX, tapY}
                end if
            end tell
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        do {
            try proc.run()
            proc.waitUntilExit()
            lastActionStatus = proc.terminationStatus == 0
                ? "Tapped \(node.name) at (\(Int(centerX * 100))%, \(Int(centerY * 100))%)"
                : "Simulator tap requires Accessibility permission"
        } catch {
            lastActionStatus = error.localizedDescription
        }
        router.statusMessage = lastActionStatus
    }

    func installDebugBridgeInProject() {
        guard let root = router.projectURL else {
            router.statusMessage = AppStrings.Common.selectProjectFirst
            return
        }
        let dest = root.appendingPathComponent("XScopeDebugBridge.swift")
        let source = XScopeDebugBridgeService.generateBridgeSwiftSource()
        do {
            try source.write(to: dest, atomically: true, encoding: .utf8)
            clipboard.copyString("XScopeDebugBridge.shared.start()")
            lastActionStatus = "Created XScopeDebugBridge.swift & copied start() call"
            router.statusMessage = lastActionStatus
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func openSelectedComponentInXcode() async {
        guard let node = selectedNode else { return }
        await router.openInXcode(fileName: node.fileName, line: node.lineNumber)
    }

    func applyComponentChangesToSwiftCode() {
        guard let idx = selectedNodeIndex else { return }
        if var draft = draftNode {
            draft.isEdited = true
            componentNodes[idx] = draft
            draftNode = draft
        }
        let node = componentNodes[idx]
        let filePath = node.filePath ?? router.projectURL.flatMap { router.findFile(named: node.fileName, in: $0)?.path }
        guard let path = filePath else {
            router.statusMessage = AppStrings.Performance.noFindingForXcode
            return
        }
        let patch = interactor.buildComponentCodePatch(for: node)
        do {
            let record = try interactor.applyComponentPatch(
                to: URL(fileURLWithPath: path),
                oldSnippet: patch.oldSnippet,
                newSnippet: patch.newSnippet,
                lineNumber: node.lineNumber
            )
            lastComponentRevertRecord = record
            componentNodes[idx].codeSnippet = patch.newSnippet
            router.statusMessage = AppStrings.Performance.patchAppliedToFile(node.fileName)
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func undoLastComponentPatch() {
        guard let record = lastComponentRevertRecord else { return }
        do {
            try interactor.revertComponentPatch(record)
            lastComponentRevertRecord = nil
            router.statusMessage = AppStrings.Performance.patchRolledBack(record.fileURL.lastPathComponent)
            Task { await captureHierarchyForSelectedApp() }
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func toggleLiveReload() {
        if isLiveReloadActive {
            watchTask?.cancel()
            watchTask = nil
            isLiveReloadActive = false
            router.statusMessage = AppStrings.Simulator.liveReloadStopped
            return
        }

        guard let projectURL = router.projectURL else {
            router.statusMessage = AppStrings.Common.selectProjectFirst
            return
        }

        isLiveReloadActive = true
        router.statusMessage = AppStrings.Simulator.liveReloadWatching(projectURL.lastPathComponent)
        watchTask = Task { [weak self] in
            guard let self else { return }
            await self.fileWatcher.reset()
            _ = await self.fileWatcher.detectChanges(in: projectURL)

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { break }
                let changed = await self.fileWatcher.detectChanges(in: projectURL)
                guard !changed.isEmpty else { continue }

                self.onProjectFilesChanged()
                let fileList = changed.prefix(2).map(\.lastPathComponent).joined(separator: ", ")
                self.lastReloadSummary = AppStrings.Simulator.liveReloadTriggered(fileList)
                self.router.statusMessage = self.lastReloadSummary

                if let xcodeProj = Self.findXcodeContainer(in: projectURL),
                   !self.liveReloadScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let dest: String
                    if let phys = self.router.selectedPhysicalDevice {
                        dest = "platform=iOS,name=\(phys.name)"
                    } else {
                        let simName = self.router.bootedSimulators.first(where: { $0.id == self.resolvedBootedUDID })?.name ?? "iPhone 16"
                        dest = "platform=iOS Simulator,name=\(simName)"
                    }
                    do {
                        let out = try await self.interactor.incrementalBuildAndLaunch(
                            projectPath: xcodeProj,
                            scheme: self.liveReloadScheme,
                            simulatorUDID: self.resolvedBootedUDID,
                            destination: dest
                        )
                        self.router.statusMessage = out.isSuccess
                            ? AppStrings.Simulator.liveReloadSucceeded(fileList)
                            : (out.stderr.isEmpty ? AppStrings.Simulator.liveReloadFailed : out.stderr)
                        if out.isSuccess {
                            await self.captureHierarchyForSelectedApp()
                        }
                    } catch {
                        self.router.statusMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private static func findXcodeContainer(in root: URL) -> String? {
        let resolved = AgentService.resolveXcodeContainer(in: root)
        switch resolved.kind {
        case .xcworkspace, .xcodeproj:
            return resolved.url.path
        case .swiftPackage, .directory:
            return nil
        }
    }

    var bootedCount: Int { router.bootedSimulators.count }

    func refreshDevices() async {
        do {
            let sims = try await interactor.listSimulators()
            let devs = try await interactor.listPhysicalDevices()
            router.simulators = sims.filter(\.isBooted)
            router.physicalDevices = devs.filter(\.isConnected)
            if let firstBooted = router.bootedSimulators.first {
                if !router.bootedSimulators.contains(where: { $0.id == router.selectedSimulatorUDID }) {
                    router.selectedSimulatorUDID = firstBooted.id
                }
            } else {
                router.selectedSimulatorUDID = AppConstants.Defaults.defaultSimulatorUDID
            }
            if let selDevID = router.selectedPhysicalDeviceID,
               !router.activePhysicalDevices.contains(where: { $0.id == selDevID }) {
                router.selectedPhysicalDeviceID = nil
            }
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func setAppearance(_ appearance: SimulatorAppearance) async {
        await runAction(AppStrings.Simulator.appearanceUpdated(appearance.rawValue)) {
            try await interactor.setAppearance(appearance, udid: resolvedBootedUDID)
        }
    }

    func setDynamicType(_ size: DynamicTypeSizeOption) async {
        await runAction(AppStrings.Simulator.dynamicTypeUpdated(size.rawValue)) {
            try await interactor.setDynamicType(size, udid: resolvedBootedUDID)
        }
    }

    func overrideStatusBar() async {
        await runAction(AppStrings.Simulator.statusBarOverridden) {
            try await interactor.overrideStatusBar(udid: resolvedBootedUDID)
        }
    }

    func openDeepLink() async {
        let url = deepLinkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        await runAction(AppStrings.Simulator.deepLinkOpened(url)) {
            try await interactor.openDeepLink(url, udid: resolvedBootedUDID)
        }
        deepLinkPresets = deepLinkStore.savePreset(title: deepLinkPresetTitle, urlString: url)
    }

    func saveDeepLinkPreset() {
        let url = deepLinkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        deepLinkPresets = deepLinkStore.savePreset(title: deepLinkPresetTitle, urlString: url)
        deepLinkPresetTitle = ""
    }

    func fireDeepLinkPreset(_ preset: DeepLinkPreset) async {
        deepLinkURL = preset.urlString
        await openDeepLink()
    }

    func removeDeepLinkPreset(id: UUID) {
        deepLinkPresets = deepLinkStore.removePreset(id: id)
    }

    var filteredLogEntries: [SimulatorLogEntry] {
        logBuffer.filter(level: logLevelFilter, query: logSearchQuery)
    }

    func toggleLogStream() {
        if isStreamingLogs {
            stopLogStream()
        } else {
            startLogStream()
        }
    }

    func clearLogs() {
        logBuffer.clear()
        logEntries = []
    }

    func setLogBufferCapacity(_ capacity: Int) {
        let existing = logBuffer.entries
        logBuffer = SimulatorLogRingBuffer(maxCapacity: capacity)
        logBuffer.append(existing)
        logEntries = logBuffer.entries
    }

    func inspectAppSandbox() async {
        let bundle = sandboxBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundle.isEmpty, hasBootedSimulator, !isInspectingSandbox else { return }
        isInspectingSandbox = true
        defer { isInspectingSandbox = false }
        do {
            let snap = try await sandboxService.inspectDataContainer(udid: resolvedBootedUDID, bundleID: bundle)
            sandboxSnapshot = snap
            router.statusMessage = "Inspected sandbox for \(bundle) (\(snap.userDefaults.count) UserDefaults keys)."
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func setSimulatorLocation(latitude: Double, longitude: Double, label: String) async {
        guard hasBootedSimulator else { return }
        await runAction("Simulated location: \(label) (\(latitude), \(longitude))") {
            try await sandboxService.setLocation(latitude: latitude, longitude: longitude, udid: resolvedBootedUDID)
        }
    }

    func resetPrivacy(_ service: SimulatorPrivacyService) async {
        guard hasBootedSimulator else { return }
        await runAction("Reset \(service.displayName) permissions on simulator") {
            try await sandboxService.resetPrivacy(service: service, udid: resolvedBootedUDID)
        }
    }

    var availableShutdownSimulators: [SimulatorDevice] {
        router.simulators.filter { !$0.isBooted }
    }

    func bootSimulator(udid: String) async {
        let svc = SimulatorService()
        await runAction("Booted simulator") {
            try await svc.bootSimulator(udid: udid)
        }
        await refreshRunningAppsAndHierarchy()
    }

    func shutdownBootedSimulator() async {
        guard hasBootedSimulator else { return }
        let svc = SimulatorService()
        let udid = resolvedBootedUDID
        await runAction("Shut down simulator") {
            try await svc.shutdownSimulator(udid: udid)
        }
        await refreshRunningAppsAndHierarchy()
    }

    func toggleVideoRecording() {
        if isRecordingVideo {
            stopVideoRecording()
        } else {
            startVideoRecording()
        }
    }

    private func startVideoRecording() {
        guard !isRecordingVideo, hasBootedSimulator else { return }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("XScope_Sim_\(Int(Date().timeIntervalSince1970)).mp4")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "io", resolvedBootedUDID, "recordVideo", "--force", outURL.path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            videoRecordProcess = proc
            videoTempURL = outURL
            isRecordingVideo = true
            router.statusMessage = "Recording Simulator video (MP4)…"
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func stopVideoRecording() {
        guard isRecordingVideo else { return }
        if let proc = videoRecordProcess, proc.isRunning {
            kill(proc.processIdentifier, SIGINT)
            proc.waitUntilExit()
        }
        videoRecordProcess = nil
        isRecordingVideo = false
        guard let tempURL = videoTempURL, FileManager.default.fileExists(atPath: tempURL.path) else {
            router.statusMessage = "Video recording stopped."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tempURL.lastPathComponent
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: tempURL, to: dest)
            router.statusMessage = "Saved simulator video to \(dest.lastPathComponent)."
        } else {
            try? FileManager.default.removeItem(at: tempURL)
            router.statusMessage = "Simulator video recording discarded."
        }
        videoTempURL = nil
    }

    func startLogStream() {
        guard !isStreamingLogs, hasBootedSimulator else { return }
        let udid = resolvedBootedUDID
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "spawn", udid, "log", "stream", "--style", "compact"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let collector = LogBatchCollector()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
            let parsed = lines.compactMap { SimulatorLogRingBuffer.parseCompactLine(String($0)) }
            if !parsed.isEmpty {
                collector.append(parsed)
            }
        }

        do {
            try process.run()
            logStreamProcess = process
            isStreamingLogs = true
            router.statusMessage = "Streaming Simulator os_log…"

            logFlushTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, self.isStreamingLogs else { break }
                    let batch = collector.drain()
                    if !batch.isEmpty {
                        self.logBuffer.append(batch)
                        self.logEntries = self.logBuffer.entries
                    }
                }
            }
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    func stopLogStream() {
        logFlushTask?.cancel()
        logFlushTask = nil
        if let proc = logStreamProcess {
            if let outPipe = proc.standardOutput as? Pipe {
                outPipe.fileHandleForReading.readabilityHandler = nil
            }
            if proc.isRunning {
                proc.terminate()
            }
        }
        logStreamProcess = nil
        isStreamingLogs = false
    }

    func sendPush() async {
        let bundleID = pushBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }
        await runAction(AppStrings.Simulator.pushSent(bundleID)) {
            try await interactor.sendPush(bundleID: bundleID, title: pushTitle, body: pushBody, udid: resolvedBootedUDID)
        }
    }

    func captureScreenshot() async {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevCompanion_Sim_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outURL) }
        do {
            let out = try await interactor.captureScreenshot(to: outURL, udid: resolvedBootedUDID)
            if out.isSuccess, clipboard.copyImage(at: outURL) {
                router.statusMessage = AppStrings.Simulator.screenshotCopied(outURL.lastPathComponent)
            } else {
                router.statusMessage = out.stderr.isEmpty ? AppStrings.Simulator.screenshotFailed : out.stderr
            }
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }

    private func runAction(_ successMsg: String, block: () async throws -> CommandOutput) async {
        do {
            let out = try await block()
            router.statusMessage = out.isSuccess ? successMsg : out.stderr
        } catch {
            router.statusMessage = error.localizedDescription
        }
    }
}

private final class LogBatchCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [SimulatorLogEntry] = []

    func append(_ items: [SimulatorLogEntry]) {
        lock.lock()
        pending.append(contentsOf: items)
        if pending.count > 500 {
            pending.removeFirst(pending.count - 500)
        }
        lock.unlock()
    }

    func drain() -> [SimulatorLogEntry] {
        lock.lock()
        let copy = pending
        pending.removeAll(keepingCapacity: true)
        lock.unlock()
        return copy
    }
}

import SwiftUI
import AppKit
import Darwin
import DevCompanionCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let reopenDistributedNotification = Notification.Name("com.devcompanion.mac.reopen")
    static let reopenLocalNotification = Notification.Name("com.devcompanion.mac.reopen.local")
    private var lockFileDescriptor: Int32 = -1

    override init() {
        super.init()
        acquireSingleInstanceLockOrExit()
    }

    private func acquireSingleInstanceLockOrExit() {
        let lockPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("com.devcompanion.mac.instance.lock")
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        if fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 {
            lockFileDescriptor = fd
            return
        }
        if fd >= 0 { close(fd) }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let matchingApps: [NSRunningApplication] = if let bundleID = Bundle.main.bundleIdentifier {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        } else {
            NSWorkspace.shared.runningApplications.filter {
                $0.executableURL?.lastPathComponent == "DevCompanionMac"
            }
        }
        let candidatePIDs = matchingApps.map(\.processIdentifier)
        if let existingPID = SingleInstancePolicy.findExistingInstancePID(currentPID: currentPID, candidatePIDs: candidatePIDs),
           let existingApp = matchingApps.first(where: { $0.processIdentifier == existingPID }) {
            DistributedNotificationCenter.default().postNotificationName(
                Self.reopenDistributedNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            existingApp.activate()
        }
        exit(0)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: Self.reopenLocalNotification, object: nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private final class ObserverHolder: @unchecked Sendable {
    var distributedObserver: NSObjectProtocol?
    var localObserver: NSObjectProtocol?

    deinit {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
        }
        if let localObserver {
            NotificationCenter.default.removeObserver(localObserver)
        }
    }
}

@MainActor
@Observable
final class WindowVisibilityController {
    var isMainWindowVisible = true
    private var openWindowHandler: OpenWindowAction?
    private let observers = ObserverHolder()

    init() {
        observers.distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppDelegate.reopenDistributedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreMainWindow()
            }
        }

        observers.localObserver = NotificationCenter.default.addObserver(
            forName: AppDelegate.reopenLocalNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreMainWindow()
            }
        }
    }

    func register(openWindow: OpenWindowAction) {
        self.openWindowHandler = openWindow
    }

    func hideToMenuBar() {
        for window in NSApp.windows where !window.className.contains("NSStatusBar") {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
        isMainWindowVisible = false
    }

    func showMainWindow(openWindow: OpenWindowAction) {
        self.openWindowHandler = openWindow
        restoreMainWindow()
    }

    private func restoreMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if let openWindowHandler {
            openWindowHandler(id: "main")
        }
        for window in NSApp.windows where !window.className.contains("NSStatusBar") {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
        isMainWindowVisible = true
    }

    func quitApplication(performancePresenter: PerformancePresenter, simulatorPresenter: SimulatorPresenter) {
        if performancePresenter.isTelemetryActive {
            performancePresenter.toggleTelemetry()
        }
        if simulatorPresenter.isLiveReloadActive {
            simulatorPresenter.toggleLiveReload()
        }
        if simulatorPresenter.isStreamingLogs {
            simulatorPresenter.stopLogStream()
        }
        if simulatorPresenter.isRecordingVideo {
            simulatorPresenter.stopVideoRecording()
        }
        NSApplication.shared.terminate(nil)
    }
}

@main
struct DevCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var builder = ModuleBuilder()
    @State private var bgSettings = BackgroundSettings()
    @State private var windowController = WindowVisibilityController()
    @State private var notificationService = BackgroundNotificationService()
    @State private var showCommandPalette = false
    @State private var showShortcutsSheet = false
    @State private var languageRevision = 0
    @State private var preferences = AppPreferencesStore().load()
    private let preferencesStore = AppPreferencesStore()

    var body: some Scene {
        Window(AppStrings.Common.appName, id: "main") {
            MainContentView(
                builder: builder,
                bgSettings: bgSettings,
                windowController: windowController,
                notificationService: notificationService,
                showCommandPalette: $showCommandPalette,
                showShortcutsSheet: $showShortcutsSheet,
                preferences: $preferences,
                onSavePreferences: { updated in
                    let prevLang = AppPreferencesStore().load().languageOverride
                    preferencesStore.save(updated)
                    builder.simulatorPresenter.setLogBufferCapacity(updated.logBufferCapacity)
                    if prevLang != updated.languageOverride {
                        languageRevision += 1
                    }
                }
            )
                .id(languageRevision)
                .frame(minWidth: AppConstants.Layout.minWindowWidth, minHeight: AppConstants.Layout.minWindowHeight)
                .preferredColorScheme(bgSettings.theme.colorScheme)
                .tint(CompanionTheme.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    showCommandPalette.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Scan Workspace") {
                    Task { await builder.smartScanPresenter.runSmartScan() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Hide to Menu Bar") {
                    windowController.hideToMenuBar()
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Keyboard Shortcuts") {
                    showShortcutsSheet.toggle()
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            CommandMenu("Navigate") {
                ForEach(Array(CompanionModule.allCases.enumerated()), id: \.element.id) { index, module in
                    Button(module.title) {
                        builder.router.selectedModule = module
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }

        MenuBarExtra(AppStrings.Common.appName, systemImage: ThemeAppearanceModel.shared.menuBarConfig.iconStyle.rawValue) {
            MenuBarContentView(
                simulatorPresenter: builder.simulatorPresenter,
                smartScanPresenter: builder.smartScanPresenter,
                performancePresenter: builder.performancePresenter,
                router: builder.router,
                windowController: windowController
            )
        }
        .menuBarExtraStyle(.window)
    }
}

struct MainContentView: View {
    let builder: ModuleBuilder
    @Bindable var bgSettings: BackgroundSettings
    let windowController: WindowVisibilityController
    let notificationService: BackgroundNotificationService
    @Binding var showCommandPalette: Bool
    @Binding var showShortcutsSheet: Bool
    @Binding var preferences: AppPreferences
    let onSavePreferences: (AppPreferences) -> Void
    @State private var showBackgroundPopover = false
    @State private var showPreferencesPopover = false
    @Namespace private var navNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    private var router: AppRouter { builder.router }

    var body: some View {
        ZStack {
            CustomBackgroundLayer(settings: bgSettings)

            VStack(spacing: 0) {
                topTargetBar
                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                HStack(spacing: 0) {
                    leftRail
                    Rectangle().fill(CompanionTheme.hairlineBorder).frame(width: 1)
                    detailArea
                }
            }

            if showCommandPalette {
                CommandPaletteOverlay(
                    isPresented: $showCommandPalette,
                    items: commandPaletteItems,
                    onSelect: handleCommandPaletteSelection
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if showShortcutsSheet {
                ShortcutsCheatSheetOverlay(isPresented: $showShortcutsSheet)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("xscope.open.command.palette"))) { _ in
            withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
                showCommandPalette = true
            }
        }
        .onAppear {
            windowController.register(openWindow: openWindow)
            notificationService.onSelectModule = { module in
                windowController.showMainWindow(openWindow: openWindow)
                router.selectedModule = module
            }
            notificationService.requestAuthorizationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("xscope.background.alert"))) { note in
            guard let info = note.userInfo,
                  let catRaw = info["category"] as? String,
                  let category = BackgroundAlertCategory(rawValue: catRaw),
                  let title = info["title"] as? String,
                  let body = info["body"] as? String,
                  let modRaw = info["module"] as? String,
                  let module = CompanionModule(rawValue: modRaw) else {
                return
            }
            let allowed: Bool = switch category {
            case .crash: preferences.notifyOnCrash
            case .hang: preferences.notifyOnHang
            case .scanComplete, .testsComplete: preferences.notifyOnTaskComplete
            }
            guard allowed else { return }
            notificationService.notifyIfBackground(category: category, title: title, body: body, module: module)
        }
        .task {
            await builder.smartScanPresenter.refreshDevicesAndReportsOnly()
        }
    }

    private var topTargetBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                XScopeLogoMark(size: 20)
                Text(AppStrings.Common.appName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CompanionTheme.textPrimary)
            }
            .padding(.leading, 68)
            .preventSquish()

            Button {
                builder.smartScanPresenter.chooseProjectFolder()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: AppConstants.Icons.folder)
                        .font(.system(size: 11))
                    Text(router.projectURL?.lastPathComponent ?? AppStrings.Common.selectXcodeProject)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(CompanionTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CompanionTheme.glassLow)
                )
            }
            .buttonStyle(.plain)
            .preventSquish()

            Spacer()

            Button {
                withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
                    showCommandPalette = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                    Text(AppStrings.Enhancements.quickJump)
                        .font(.system(size: 11))
                    Text("⌘K")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(CompanionTheme.glassMid))
                }
                .foregroundStyle(CompanionTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CompanionTheme.glassLow)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .preventSquish()
            .help("Open Command Palette (⌘K)")

            Button {
                windowController.hideToMenuBar()
            } label: {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(CompanionTheme.glassLow)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .preventSquish()
            .help("Hide window and keep running in Menu Bar")
            .accessibilityLabel("Hide to Menu Bar")

            Button {
                showPreferencesPopover.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(CompanionTheme.glassLow)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .preventSquish()
            .help("Preferences")
            .accessibilityLabel("Preferences")
            .popover(isPresented: $showPreferencesPopover, arrowEdge: .bottom) {
                PreferencesPopover(preferences: $preferences, onSave: onSavePreferences)
            }

            Button {
                showBackgroundPopover.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: AppConstants.Icons.paintbrush)
                        .font(.system(size: 11))
                    Text(AppStrings.TopBar.themeAndBackground)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(CompanionTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CompanionTheme.glassLow)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .preventSquish()
            .popover(isPresented: $showBackgroundPopover, arrowEdge: .bottom) {
                BackgroundSettingsPopover(settings: bgSettings)
            }

            Button {
                Task { await builder.smartScanPresenter.runSmartScan() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: AppConstants.Icons.playFill)
                        .font(.system(size: 9))
                    Text(builder.smartScanPresenter.isScanning ? AppStrings.Common.scanning : AppStrings.Common.scanWorkspace)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.055, green: 0.067, blue: 0.090))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(CompanionTheme.accent))
            }
            .buttonStyle(.plain)
            .preventSquish()
            .opacity(builder.smartScanPresenter.hasProject && !builder.smartScanPresenter.isScanning ? 1.0 : 0.45)
            .disabled(!builder.smartScanPresenter.hasProject || builder.smartScanPresenter.isScanning)
        }
        .padding(.horizontal, 16)
        .frame(height: AppConstants.Layout.topBarHeight)
        .focusEffectDisabled()
        .background(
            bgSettings.theme.isLight
                ? Color.white.opacity(bgSettings.resolvedNSImage != nil ? 0.18 : 0.35)
                : Color.black.opacity(bgSettings.resolvedNSImage != nil ? 0.18 : 0.35)
        )
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            navGroupSection(title: AppStrings.Navigation.monitorSection, modules: CompanionModule.monitorModules)
            navGroupSection(title: AppStrings.Navigation.toolsSection, modules: CompanionModule.toolModules)

            Spacer()

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.TopBar.quickSimulator)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CompanionTheme.textSecondary)

                    HStack(spacing: 6) {
                        quickSimBtn(AppStrings.TopBar.darkShort) { await builder.simulatorPresenter.setAppearance(.dark) }
                        quickSimBtn(AppStrings.TopBar.lightShort) { await builder.simulatorPresenter.setAppearance(.light) }
                        quickSimBtn(AppStrings.TopBar.cleanBarShort) { await builder.simulatorPresenter.overrideStatusBar() }
                    }
                    .opacity(builder.simulatorPresenter.hasBootedSimulator ? 1.0 : 0.45)
                    .disabled(!builder.simulatorPresenter.hasBootedSimulator)
                }
            }

            sidebarBottomControls
        }
        .padding(12)
        .frame(width: AppConstants.Layout.leftRailWidth)
        .background(
            bgSettings.theme.isLight
                ? Color.white.opacity(bgSettings.resolvedNSImage != nil ? 0.10 : 0.20)
                : Color.black.opacity(bgSettings.resolvedNSImage != nil ? 0.14 : 0.28)
        )
    }

    private func navGroupSection(title: String, modules: [CompanionModule]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CompanionTheme.textMuted)
                .padding(.horizontal, 8)

            ForEach(modules) { module in
                let isSelected = router.selectedModule == module
                Button {
                    withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
                        router.selectedModule = module
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: module.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? CompanionTheme.accent : CompanionTheme.textSecondary)
                            .frame(width: 16)
                        Text(module.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                        Spacer()
                        if let badge = sidebarBadge(for: module) {
                            Text(badge.text)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(badge.color.opacity(0.22))
                                .foregroundStyle(badge.color)
                                .clipShape(Capsule())
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(CompanionTheme.accentTint)
                                .matchedGeometryEffect(id: "activeNavPill", in: navNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sidebarBadge(for module: CompanionModule) -> (text: String, color: Color)? {
        switch module {
        case .smartScan:
            return builder.smartScanPresenter.isScanning ? ("SCAN", CompanionTheme.accent) : nil
        case .crashlytics:
            let count = builder.crashlyticsPresenter.reports.count
            return count > 0 ? ("\(count)", CompanionTheme.coral) : nil
        case .performance:
            let perf = builder.performancePresenter
            if perf.isTelemetryActive {
                let liveCount = (perf.runtimeLeakSnapshot?.leakCount ?? 0) + perf.realtimeSessionFreezes.count
                return (liveCount > 0 ? "\(liveCount)" : "LIVE", CompanionTheme.coral)
            }
            if perf.leakScope == .realtimeSession {
                let liveCount = (perf.runtimeLeakSnapshot?.leakCount ?? 0) + perf.realtimeSessionFreezes.count
                return liveCount > 0 ? ("\(liveCount)", CompanionTheme.coral) : nil
            }
            let count = perf.leakAndHangFindings.count
            return count > 0 ? ("\(count)", CompanionTheme.amber) : nil
        case .codeReview:
            let cr = builder.codeReviewerPresenter
            if cr.isAnalyzing {
                return ("SCAN", CompanionTheme.accent)
            }
            guard cr.isResultsGateOpen else { return nil }
            let count = cr.filteredFindings.count
            return count > 0 ? ("\(count)", CompanionTheme.accent) : nil
        case .simulator:
            let sim = builder.simulatorPresenter
            if sim.isRecordingVideo {
                return ("REC", CompanionTheme.coral)
            }
            if sim.isLiveReloadActive || sim.isStreamingLogs {
                return ("LIVE", CompanionTheme.mint)
            }
            let activeTargets = router.bootedSimulators.count + router.activePhysicalDevices.count
            return activeTargets > 0 ? ("\(activeTargets)", CompanionTheme.mint) : nil
        case .unitTests:
            let tests = builder.unitTestPresenter
            if tests.isRunningTests || tests.isCheckingCoverage {
                return ("RUN", CompanionTheme.accent)
            }
            if let cov = tests.coverageReport {
                return ("\(Int(cov.overallPercent))%", cov.overallPercent >= Double(tests.targetCoveragePercent) ? CompanionTheme.mint : CompanionTheme.amber)
            }
            return nil
        case .utilities:
            let count = builder.utilitiesPresenter.missingLocalizations.count + builder.utilitiesPresenter.unusedAssets.count
            return count > 0 ? ("\(count)", CompanionTheme.amber) : nil
        }
    }

    private func quickSimBtn(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanionTheme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(CompanionTheme.accentTint))
        }
        .buttonStyle(.plain)
    }

    private var sidebarBottomControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach([AppLanguageOverride.en, AppLanguageOverride.id], id: \.rawValue) { lang in
                    let active = preferences.languageOverride == lang
                    Button(lang == .en ? "EN" : "ID") {
                        var updated = preferences
                        updated.languageOverride = lang
                        preferences = updated
                        onSavePreferences(updated)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: active ? .bold : .medium))
                    .foregroundStyle(active ? Color.white : CompanionTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(active ? CompanionTheme.accent : CompanionTheme.glassLow)
                    )
                }
            }

            HStack {
                Button("Minimize") {
                    windowController.hideToMenuBar()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanionTheme.textSecondary)

                Spacer()

                Button("Quit XScope") {
                    windowController.quitApplication(
                        performancePresenter: builder.performancePresenter,
                        simulatorPresenter: builder.simulatorPresenter
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanionTheme.coral)
            }
            .padding(.horizontal, 4)
        }
    }

    private var detailArea: some View {
        VStack(spacing: 0) {
            Group {
                switch router.selectedModule {
                case .smartScan:
                    SmartScanView(
                        presenter: builder.smartScanPresenter,
                        leakAndHangCount: builder.performancePresenter.totalPotentialLeakCount,
                        onNavigate: { module in
                            withAnimation(.snappy(duration: 0.22)) {
                                router.selectedModule = module
                            }
                        }
                    )
                case .crashlytics:
                    CrashlyticsView(
                        presenter: builder.crashlyticsPresenter,
                        onChooseProject: { builder.smartScanPresenter.chooseProjectFolder() }
                    )
                case .simulator:
                    SimulatorControlsView(
                        presenter: builder.simulatorPresenter,
                        onChooseProject: { builder.smartScanPresenter.chooseProjectFolder() }
                    )
                case .performance:
                    PerformanceView(
                        presenter: builder.performancePresenter,
                        onChooseProject: { builder.smartScanPresenter.chooseProjectFolder() },
                        onOpenCrashlytics: {
                            withAnimation(.snappy(duration: 0.22)) {
                                router.selectedModule = .crashlytics
                            }
                        }
                    )
                case .codeReview:
                    CodeReviewerView(
                        presenter: builder.codeReviewerPresenter,
                        onChooseProject: { builder.smartScanPresenter.chooseProjectFolder() }
                    )
                case .unitTests:
                    UnitTestStudioView(
                        presenter: builder.unitTestPresenter,
                        onChooseProject: { builder.smartScanPresenter.chooseProjectFolder() }
                    )
                case .utilities:
                    UtilitiesView(
                        presenter: builder.utilitiesPresenter,
                        onChooseProject: { builder.smartScanPresenter.chooseProjectFolder() }
                    )
                }
            }
            .id(router.selectedModule)
            .transition(MotionTokens.panelTransition(reduceMotion: reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(MotionTokens.snappy(reduceMotion: reduceMotion), value: router.selectedModule)
            .background(
                bgSettings.theme.isLight
                    ? Color.white.opacity(bgSettings.resolvedNSImage != nil ? 0.04 : 0.12)
                    : Color.black.opacity(bgSettings.resolvedNSImage != nil ? 0.06 : 0.18)
            )

            HStack {
                Text(router.statusMessage)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                if !router.activePhysicalDevices.isEmpty {
                    Text(AppStrings.TopBar.physicalDevicesCount(router.activePhysicalDevices.count))
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.mint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(bgSettings.theme.isLight ? Color.white.opacity(0.30) : Color.black.opacity(0.35))
        }
    }

    private var commandPaletteItems: [CommandPaletteItem] {
        var items: [CommandPaletteItem] = CompanionModule.allCases.enumerated().map { idx, module in
            CommandPaletteItem(
                id: "mod:\(module.rawValue)",
                title: module.title,
                subtitle: "Switch to \(module.title)",
                icon: module.icon,
                shortcutHint: "⌘\(idx + 1)",
                category: .module,
                keywords: [module.rawValue]
            )
        }

        items.append(contentsOf: [
            CommandPaletteItem(
                id: "act:scan",
                title: "Run Smart Scan",
                subtitle: "Scan devices, project health, and crash logs",
                icon: AppConstants.Icons.playFill,
                shortcutHint: "⌘R",
                category: .action,
                keywords: ["scan", "refresh", "health"]
            ),
            CommandPaletteItem(
                id: "act:telemetry",
                title: builder.performancePresenter.isTelemetryActive ? "Stop Live Telemetry" : "Start Live Telemetry",
                subtitle: "Toggle CPU, memory & freeze monitor",
                icon: AppConstants.Icons.performance,
                category: .action,
                keywords: ["cpu", "memory", "fps", "hang", "freeze"]
            ),
            CommandPaletteItem(
                id: "act:livereload",
                title: builder.simulatorPresenter.isLiveReloadActive ? "Stop Live Reload" : "Start Live Reload",
                subtitle: "Toggle incremental SwiftUI/Xcode watcher",
                icon: "bolt.fill",
                category: .action,
                keywords: ["simulator", "watch", "rebuild"]
            ),
            CommandPaletteItem(
                id: "act:deriveddata",
                title: "Clean DerivedData",
                subtitle: "Clear Xcode build cache",
                icon: "trash",
                category: .action,
                keywords: ["cache", "xcode", "utilities", "clean"]
            ),
            CommandPaletteItem(
                id: "act:hide",
                title: "Hide to Menu Bar",
                subtitle: "Keep XScope Studio running in background",
                icon: "menubar.rectangle",
                shortcutHint: "⌘W",
                category: .action,
                keywords: ["minimize", "background", "tray"]
            )
        ])

        for sim in router.bootedSimulators {
            items.append(
                CommandPaletteItem(
                    id: "sim:\(sim.id)",
                    title: sim.name,
                    subtitle: "Use Simulator (\(sim.runtime))",
                    icon: AppConstants.Icons.iphone,
                    category: .target,
                    keywords: ["simulator", sim.runtime]
                )
            )
        }

        for dev in router.activePhysicalDevices {
            items.append(
                CommandPaletteItem(
                    id: "dev:\(dev.id)",
                    title: dev.name,
                    subtitle: "Use Physical Device (\(dev.osVersion))",
                    icon: AppConstants.Icons.iphone,
                    category: .target,
                    keywords: ["device", "iphone", dev.osVersion]
                )
            )
        }
        return items
    }

    private func handleCommandPaletteSelection(_ item: CommandPaletteItem) {
        if item.id.hasPrefix("mod:"), let mod = CompanionModule(rawValue: String(item.id.dropFirst(4))) {
            withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
                router.selectedModule = mod
            }
        } else if item.id == "act:scan" {
            Task { await builder.smartScanPresenter.runSmartScan() }
        } else if item.id == "act:telemetry" {
            builder.performancePresenter.toggleTelemetry()
        } else if item.id == "act:livereload" {
            builder.simulatorPresenter.toggleLiveReload()
        } else if item.id == "act:deriveddata" {
            router.selectedModule = .utilities
            builder.utilitiesPresenter.cleanDerivedData()
        } else if item.id == "act:hide" {
            windowController.hideToMenuBar()
        } else if item.id.hasPrefix("sim:") {
            router.selectedPhysicalDeviceID = nil
            router.selectedSimulatorUDID = String(item.id.dropFirst(4))
        } else if item.id.hasPrefix("dev:") {
            router.selectedPhysicalDeviceID = String(item.id.dropFirst(4))
        }
    }
}

private struct TargetDevicePopover: View {
    let router: AppRouter
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.TopBar.simulatorsSection)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CompanionTheme.textMuted)

            if router.bootedSimulators.isEmpty {
                Text(AppStrings.TopBar.noBootedSimulator)
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .padding(.vertical, 2)
            } else {
                ForEach(router.bootedSimulators) { sim in
                    let isSelected = router.selectedPhysicalDeviceID == nil && sim.id == router.selectedSimulatorUDID
                    Button {
                        router.selectSimulator(sim.id)
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CompanionTheme.mint)
                                .frame(width: 6, height: 6)
                            Text(sim.name)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(CompanionTheme.textPrimary)
                            Spacer()
                            if isSelected {
                                Image(systemName: AppConstants.Icons.checkmark)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(CompanionTheme.accent)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? CompanionTheme.glassHigh : CompanionTheme.glassLow))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !router.activePhysicalDevices.isEmpty {
                Divider()
                Text(AppStrings.TopBar.physicalDevicesSection)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CompanionTheme.textMuted)

                ForEach(router.activePhysicalDevices) { dev in
                    let isSelected = router.selectedPhysicalDeviceID == dev.id
                    Button {
                        router.selectPhysicalDevice(dev.id)
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CompanionTheme.mint)
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dev.name)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Text("iOS \(dev.osVersion) • \(dev.connectionType)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: AppConstants.Icons.checkmark)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(CompanionTheme.accent)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? CompanionTheme.glassHigh : CompanionTheme.glassLow))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

import SwiftUI
import AppKit
import DevCompanionCore

struct MenuBarContentView: View {
    let simulatorPresenter: SimulatorPresenter
    let smartScanPresenter: SmartScanPresenter
    let performancePresenter: PerformancePresenter
    let router: AppRouter
    let windowController: WindowVisibilityController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasRunningTasks: Bool {
        performancePresenter.isTelemetryActive ||
        simulatorPresenter.isLiveReloadActive ||
        smartScanPresenter.isScanning
    }

    var body: some View {
        let config = ThemeAppearanceModel.shared.menuBarConfig
        let spacing: CGFloat = config.density == .compact ? 8 : 12
        VStack(alignment: .leading, spacing: spacing) {
            headerBar

            ForEach(config.sections.filter(\.isEnabled)) { section in
                switch section.kind {
                case .target:
                    if config.showTargetBadge {
                        targetSummaryCard
                    }
                case .running:
                    if config.showLiveMetrics || hasRunningTasks {
                        runningActivityCard
                    }
                case .controls:
                    quickControlsSection
                case .status:
                    Text(router.statusMessage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            footerBar
        }
        .padding(config.density == .compact ? 10 : 14)
        .frame(width: AppConstants.Layout.menuBarWidth + 24)
        .animation(MotionTokens.smooth(reduceMotion: reduceMotion), value: hasRunningTasks)
        .animation(MotionTokens.smooth(reduceMotion: reduceMotion), value: performancePresenter.liveCPU)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            XScopeLogoMark(size: 18)
            Text(AppStrings.Common.appName)
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Button {
                windowController.showMainWindow(openWindow: openWindow)
                NotificationCenter.default.post(name: Notification.Name("xscope.open.command.palette"), object: nil)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open Command Palette (⌘K)")

            if windowController.isMainWindowVisible {
                Button("Hide to Bar") {
                    windowController.hideToMenuBar()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Minimize window and keep running in Menu Bar")
            } else {
                Button("Open Studio") {
                    windowController.showMainWindow(openWindow: openWindow)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var targetSummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(router.hasAnyActiveTarget ? CompanionTheme.mint : CompanionTheme.amber)
                    .frame(width: 6, height: 6)
                Text(router.activeTargetLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(AppStrings.MenuBar.simCount(simulatorPresenter.bootedCount))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let project = router.projectURL?.lastPathComponent {
                HStack(spacing: 5) {
                    Image(systemName: AppConstants.Icons.folder)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(project)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CompanionTheme.glassLow)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
        )
    }

    private var runningActivityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Running Now")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasRunningTasks {
                    Circle()
                        .fill(CompanionTheme.accent)
                        .frame(width: 6, height: 6)
                }
            }

            if !hasRunningTasks {
                Text("Idle, ready for Simulator or Xcode tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                if performancePresenter.isTelemetryActive {
                    HStack {
                        Label("Live Telemetry", systemImage: "waveform.path.ecg")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(String(format: "%.1f%% CPU  •  %.0f MB", performancePresenter.liveCPU, performancePresenter.liveMemoryMB))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CompanionTheme.accent)
                            .contentTransition(.numericText())
                    }
                }

                if simulatorPresenter.isLiveReloadActive {
                    HStack {
                        Label("Live Reload", systemImage: "bolt.horizontal.circle")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Watching")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CompanionTheme.mint)
                    }
                }

                if smartScanPresenter.isScanning {
                    HStack {
                        Label("Workspace Scan", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CompanionTheme.glassLow)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
        )
    }

    private var quickControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(AppStrings.MenuBar.darkMode) { Task { await simulatorPresenter.setAppearance(.dark) } }
                Button(AppStrings.MenuBar.lightMode) { Task { await simulatorPresenter.setAppearance(.light) } }
                Button(AppStrings.MenuBar.cleanBar) { Task { await simulatorPresenter.overrideStatusBar() } }
                Button {
                    Task { await simulatorPresenter.captureScreenshot() }
                } label: {
                    Image(systemName: "camera")
                }
                .help(AppStrings.Simulator.screenshotToClipboard)
                .accessibilityLabel(AppStrings.Simulator.screenshotToClipboard)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!simulatorPresenter.hasBootedSimulator)

            HStack(spacing: 5) {
                ForEach(DynamicTypeSizeOption.allCases) { size in
                    Button(size.rawValue) {
                        Task { await simulatorPresenter.setDynamicType(size) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .disabled(!simulatorPresenter.hasBootedSimulator)
        }
    }

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    Task { await smartScanPresenter.runSmartScan() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(smartScanPresenter.isScanning ? AppStrings.Common.scanning : AppStrings.Common.scanWorkspace)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!smartScanPresenter.hasProject || smartScanPresenter.isScanning)

                Button("Quit") {
                    windowController.quitApplication(
                        performancePresenter: performancePresenter,
                        simulatorPresenter: simulatorPresenter
                    )
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit XScope Studio completely")
            }
        }
    }
}

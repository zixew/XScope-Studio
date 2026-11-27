import SwiftUI

struct SmartScanView: View {
    @Bindable var presenter: SmartScanPresenter
    var leakAndHangCount: Int = 0
    var onNavigate: ((CompanionModule) -> Void)?
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        XScopeLogoMark(size: 32)
                        Text(AppStrings.Common.appName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                    }
                    Text(AppStrings.Overview.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(CompanionTheme.textSecondary)
                }
                .padding(.top, 16)

                if !presenter.hasProject {
                    GuidedRequirementBanner(
                        icon: AppConstants.Icons.folder,
                        message: AppStrings.Overview.needProjectBanner,
                        actionTitle: AppStrings.Common.selectXcodeProjectButton,
                        action: { presenter.chooseProjectFolder() }
                    )
                    .padding(.horizontal, 28)
                }

                CircularScanButton(
                    title: presenter.isScanning ? AppStrings.Common.scanning : AppStrings.Overview.scanTitle,
                    subtitle: AppStrings.Overview.scanSubtitle,
                    isScanning: presenter.isScanning
                ) {
                    Task { await presenter.runSmartScan() }
                }
                .opacity(presenter.hasProject ? 1.0 : 0.45)
                .disabled(!presenter.hasProject || presenter.isScanning)

                // Clickable Quick-Jump KPI Cards
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Overview.quickJumpHint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CompanionTheme.textMuted)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                        metricCard(
                            title: AppStrings.Overview.simulatorsBooted,
                            value: "\(presenter.bootedCount)",
                            detail: AppStrings.Overview.totalAvailable(presenter.totalSimulators),
                            icon: AppConstants.Icons.iphone,
                            accent: CompanionTheme.mint,
                            module: .simulator
                        )
                        metricCard(
                            title: AppStrings.Navigation.crashlytics,
                            value: "\(presenter.reportCount)",
                            detail: AppStrings.Overview.diagnosticReportsPath,
                            icon: AppConstants.Icons.crashlytics,
                            accent: CompanionTheme.coral,
                            module: .crashlytics
                        )
                        metricCard(
                            title: AppStrings.Navigation.leaksAndHangs,
                            value: "\(leakAndHangCount)",
                            detail: AppStrings.Performance.staticCallTreeSub,
                            icon: AppConstants.Icons.performance,
                            accent: CompanionTheme.amber,
                            module: .performance
                        )
                        metricCard(
                            title: AppStrings.Overview.codeReviewFindings,
                            value: "\(presenter.findingsCount)",
                            detail: presenter.projectName ?? AppStrings.Common.noProjectSelected,
                            icon: AppConstants.Icons.shieldCheck,
                            accent: CompanionTheme.accent,
                            module: .codeReview
                        )
                    }
                }
                .padding(.horizontal, 28)

                // Dedicated Project Workspace & Session Backup Card (FlowLayout prevents squished buttons)
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: AppConstants.Icons.folder)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.accent)
                                Text(AppStrings.Overview.sessionCardTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                if let proj = presenter.projectName {
                                    Text(proj)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(CompanionTheme.accentTint)
                                        .foregroundStyle(CompanionTheme.accent)
                                        .clipShape(Capsule())
                                        .preventSquish()
                                }
                            }
                            Text(AppStrings.Overview.sessionCardSub)
                                .font(.system(size: 11))
                                .foregroundStyle(CompanionTheme.textSecondary)
                        }

                        FlowLayout(spacing: 8) {
                            Button(AppStrings.Common.selectXcodeProjectButton) {
                                presenter.chooseProjectFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .preventSquish()

                            if presenter.projectName != nil {
                                Button(AppStrings.Common.clearProject) {
                                    presenter.resetProject()
                                }
                                .buttonStyle(.bordered)
                                .preventSquish()
                            }

                            Button(AppStrings.Overview.resetProjectData) {
                                showResetConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(!presenter.hasProject)
                            .preventSquish()

                            Button(AppStrings.Overview.exportBackup) {
                                presenter.exportBackup()
                            }
                            .buttonStyle(.bordered)
                            .preventSquish()

                            Button(AppStrings.Overview.restoreBackup) {
                                presenter.importBackup()
                            }
                            .buttonStyle(.bordered)
                            .preventSquish()

                            Button(AppStrings.Overview.openDmgInstaller) {
                                presenter.openInstallerReleases()
                            }
                            .buttonStyle(.bordered)
                            .preventSquish()
                        }
                    }
                }
                .padding(.horizontal, 28)

                if !presenter.healthHistory.isEmpty {
                    healthTrendCard
                        .padding(.horizontal, 28)
                }
            }
            .padding(.bottom, 28)
        }
        .alert(AppStrings.Overview.resetProjectData, isPresented: $showResetConfirmation) {
            Button(AppStrings.Overview.resetProjectData, role: .destructive) {
                presenter.resetProjectData()
            }
            Button(AppStrings.Common.clearProject, role: .cancel) {}
        } message: {
            Text(AppStrings.Overview.resetConfirmMessage)
        }
    }

    private var healthTrendCard: some View {
        let latest = presenter.healthHistory.last?.score ?? 100
        return GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppStrings.Enhancements.scanHealthTrend)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textPrimary)
                    Spacer()
                    Text("Score \(latest)/100 (\(presenter.healthHistory.count) scans)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(latest >= 80 ? CompanionTheme.mint : (latest >= 50 ? CompanionTheme.amber : CompanionTheme.coral))
                }

                GeometryReader { geo in
                    let points = presenter.healthHistory
                    let count = points.count
                    Path { path in
                        guard count > 0 else { return }
                        for (idx, snap) in points.enumerated() {
                            let x = count == 1 ? geo.size.width / 2 : (CGFloat(idx) / CGFloat(count - 1)) * geo.size.width
                            let y = geo.size.height - (CGFloat(snap.score) / 100.0) * (geo.size.height - 8) - 4
                            if idx == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(CompanionTheme.mint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 44)
            }
        }
    }

    private func metricCard(
        title: String,
        value: String,
        detail: String,
        icon: String,
        accent: Color,
        module: CompanionModule
    ) -> some View {
        Button {
            onNavigate?(module)
        } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                        Spacer()
                        Text(value)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(CompanionTheme.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: value)
                    }
                    HStack {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: AppConstants.Icons.chevronRight)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textMuted)
                    }
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(InteractiveSurfaceButtonStyle(cornerRadius: 10))
    }
}

import SwiftUI
import DevCompanionCore

struct PerformanceView: View {
    @Bindable var presenter: PerformancePresenter
    var onChooseProject: (() -> Void)?
    var onOpenCrashlytics: (() -> Void)?
    @State private var hoverIndex: Int?
    @State private var staticHoverEventID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppStrings.Performance.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        Text(AppStrings.Performance.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                    }
                    Spacer()

                    FlowLayout(spacing: 8) {
                        Picker(AppStrings.Performance.agentPicker, selection: $presenter.agentProvider) {
                            ForEach(AgentProviderKind.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .frame(width: 150)

                        if let onOpenCrashlytics {
                            Button(AppStrings.Crashlytics.openCrashlytics) {
                                onOpenCrashlytics()
                            }
                            .buttonStyle(.bordered)
                            .preventSquish()
                        }

                        Button(AppStrings.Performance.openInstruments) {
                            presenter.openInstruments()
                        }
                        .buttonStyle(.bordered)
                        .preventSquish()

                        Button(AppStrings.Enhancements.exportMD) {
                            presenter.copyMarkdownReport()
                        }
                        .buttonStyle(.bordered)
                        .preventSquish()
                    }
                }

                if !presenter.hasProject, let onChooseProject {
                    GuidedRequirementBanner(
                        icon: AppConstants.Icons.folder,
                        message: AppStrings.Overview.needProjectBanner,
                        actionTitle: AppStrings.Common.selectXcodeProjectButton,
                        action: onChooseProject
                    )
                }

                if presenter.agentProvider == .geminiCloud {
                    SecureField(AppStrings.Performance.geminiKeyPlaceholder, text: $presenter.agentApiKey)
                        .textFieldStyle(.roundedBorder)
                } else if presenter.agentProvider == .ollamaLocal {
                    TextField(AppStrings.Performance.ollamaModelPlaceholder, text: $presenter.agentOllamaModel)
                        .textFieldStyle(.roundedBorder)
                }

                // 4-Metric Live Telemetry Strip + Simulator Process Picker
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayout(spacing: 10) {
                            HStack(spacing: 6) {
                                ZStack {
                                    if presenter.isTelemetryActive && !reduceMotion {
                                        Circle()
                                            .stroke(CompanionTheme.coral.opacity(0.45), lineWidth: 1.5)
                                            .frame(width: 13, height: 13)
                                            .scaleEffect(presenter.isTelemetryActive ? 1.35 : 1.0)
                                            .opacity(presenter.isTelemetryActive ? 0.0 : 0.7)
                                            .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: presenter.isTelemetryActive)
                                    }
                                    Circle()
                                        .fill(presenter.isTelemetryActive ? CompanionTheme.coral : CompanionTheme.textMuted)
                                        .frame(width: 7, height: 7)
                                }
                                Text(AppStrings.Performance.liveTelemetryTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                    .preventSquish()
                            }

                            Picker(AppStrings.Performance.processPicker, selection: $presenter.selectedProcess) {
                                Text(AppStrings.Performance.selectSimulatorApp).tag(SimulatorProcessInfo?.none)
                                ForEach(presenter.simulatorProcesses) { proc in
                                    Text(proc.displayLabel).tag(SimulatorProcessInfo?.some(proc))
                                }
                            }
                            .frame(minWidth: 190, maxWidth: 280)

                            Button(AppStrings.Performance.refreshPIDs) {
                                Task { await presenter.refreshReportsAndProcesses() }
                            }
                            .buttonStyle(.bordered)
                            .preventSquish()

                            Button(presenter.isTelemetryActive ? AppStrings.Performance.stopLive : AppStrings.Performance.startLive) {
                                withAnimation(.snappy) {
                                    presenter.toggleTelemetry()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!presenter.isTelemetryActive && presenter.selectedProcess == nil)
                            .preventSquish()
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                            telemetryMetric(AppStrings.Performance.cpuUsage, AppStrings.Performance.formattedCPU(presenter.liveCPU), AppStrings.Performance.liveSimulatorSub)
                            telemetryMetric(AppStrings.Performance.memory, AppStrings.Performance.formattedMemory(presenter.liveMemoryMB), AppStrings.Performance.rssResidentSub)
                            telemetryMetric(
                                AppStrings.Performance.lastHang,
                                AppStrings.Performance.formattedHang(presenter.lastHangSeconds),
                                AppStrings.Performance.diagnosticReportsSub
                            )
                            telemetryMetric(
                                AppStrings.Performance.potentialLeaks,
                                "\(presenter.totalPotentialLeakCount)",
                                {
                                    if let snap = presenter.runtimeLeakSnapshot, snap.isAvailable {
                                        return AppStrings.Performance.runtimeLeaksSub(snap.leakCount, snap.leakedBytes / 1024)
                                    }
                                    return AppStrings.Performance.staticCallTreeSub
                                }()
                            )
                        }
                    }
                }

                // 1) Grafik Dinamis Real-Time (Rolling Waveforms + Freeze Flatline + Live Elapsed Timer + Hover Code Tooltip)
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: AppConstants.Icons.waveform)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.amber)
                                Text(AppStrings.Performance.dynamicGraphTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                            }
                            Spacer()
                            if let activeFreeze = presenter.activeFreezeEvent, presenter.activeFreezeDurationSeconds > 0 {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(CompanionTheme.coral)
                                        .frame(width: 7, height: 7)
                                    Text(AppStrings.Performance.freezeElapsedRunning(presenter.activeFreezeDurationSeconds, activeFreeze.locationLabel))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.coral)
                                        .contentTransition(.numericText())
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(CompanionTheme.coral.opacity(0.16))
                                .clipShape(Capsule())
                            }
                        }

                        InstrumentsTrackChart(
                            title: AppStrings.Performance.cpuTrackTitle,
                            subtitle: presenter.isTelemetryActive
                                ? AppStrings.Performance.liveCPUSub(presenter.liveCPU)
                                : AppStrings.Performance.cpuTrackIdleSub,
                            samples: presenter.cpuHistory,
                            timelinePoints: presenter.cpuTimeline,
                            maxScale: max(AppConstants.Telemetry.minCPUScalePercent, presenter.cpuHistory.max() ?? AppConstants.Telemetry.minCPUScalePercent),
                            accentColor: CompanionTheme.amber,
                            hoverIndex: $hoverIndex,
                            unitSuffix: AppConstants.Telemetry.percentUnit,
                            isLive: presenter.isTelemetryActive,
                            activeFreezeSeconds: presenter.activeFreezeDurationSeconds,
                            activeFreezeEvent: presenter.activeFreezeEvent,
                            onSelectFreezeEvent: { event in
                                Task { await presenter.selectFreezeEvent(event) }
                            }
                        )

                        InstrumentsTrackChart(
                            title: AppStrings.Performance.memoryTrackTitle,
                            subtitle: presenter.isTelemetryActive
                                ? AppStrings.Performance.liveMemorySub(presenter.liveMemoryMB)
                                : AppStrings.Performance.retainCyclesCount(presenter.leakAndHangFindings.count),
                            samples: presenter.memoryHistory,
                            timelinePoints: [],
                            maxScale: max(AppConstants.Telemetry.minMemoryScaleMB, (presenter.memoryHistory.max() ?? AppConstants.Telemetry.minMemoryScaleMB) * AppConstants.Telemetry.memoryHeadroomMultiplier),
                            accentColor: CompanionTheme.coral,
                            hoverIndex: $hoverIndex,
                            unitSuffix: AppConstants.Telemetry.megabyteUnit,
                            isLive: presenter.isTelemetryActive,
                            activeFreezeSeconds: 0,
                            activeFreezeEvent: nil,
                            onSelectFreezeEvent: nil
                        )
                    }
                }

                // 2) Grafik Statis (Captured Freeze & Lag Session Timeline with Duration + Code Hover Popover)
                StaticFreezeTimelineCard(
                    events: presenter.capturedFreezeEvents,
                    hoveredEventID: $staticHoverEventID,
                    onClear: { presenter.clearCapturedFreezeHistory() },
                    onSelectEvent: { event in
                        Task { await presenter.selectFreezeEvent(event) }
                    }
                )

                HStack(alignment: .top, spacing: 14) {
                    // Left: Call Tree / Detected Leaks & Hangs
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(AppStrings.Performance.callTreeTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Spacer()
                            }

                            Picker("", selection: $presenter.leakScope) {
                                ForEach(LeakDetectionScope.allCases) { scope in
                                    Text(scope.rawValue).tag(scope)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            if presenter.leakScope == .realtimeSession {
                                realtimeSessionPanel
                            } else {
                                if presenter.isTelemetryActive || presenter.runtimeLeakSnapshot != nil {
                                    runtimeLeakBanner
                                }

                                priorityFilterBar

                                if presenter.filteredLeakAndHangFindings.isEmpty {
                                    Text(AppStrings.Performance.noLeaksOrHangs)
                                        .font(.system(size: 11))
                                        .foregroundStyle(CompanionTheme.textSecondary)
                                        .padding(.vertical, 20)
                                } else {
                                RecycledVirtualList(items: presenter.filteredLeakAndHangFindings, rowSpacing: 6) { finding in
                                    let isSelected = presenter.selectedFindingID == finding.id
                                    Button {
                                        Task {
                                            await presenter.selectFinding(finding)
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(finding.severity.priorityBadge)
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(priorityColor(finding.severity).opacity(0.22))
                                                .foregroundStyle(priorityColor(finding.severity))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                .preventSquish()
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 5) {
                                                    Text("\(finding.fileName):\(finding.lineNumber)")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundStyle(CompanionTheme.textPrimary)
                                                        .lineLimit(1)
                                                    if finding.isNew {
                                                        Text(AppStrings.Performance.newBadge)
                                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 1)
                                                            .background(CompanionTheme.mint.opacity(0.22))
                                                            .foregroundStyle(CompanionTheme.mint)
                                                            .clipShape(Capsule())
                                                            .preventSquish()
                                                    }
                                                }
                                                Text(finding.title)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(CompanionTheme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: AppConstants.Icons.chevronRight)
                                                .font(.system(size: 10))
                                                .foregroundStyle(isSelected ? CompanionTheme.textPrimary : CompanionTheme.textMuted)
                                        }
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(isSelected ? CompanionTheme.hairlineBorder : .clear, lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(minHeight: 280, maxHeight: 460)
                                }
                            }
                        }
                    }
                    .frame(minWidth: 260, idealWidth: AppConstants.Layout.leaksLeftColumnWidth, maxWidth: 360)

                    // Right: Jump to Xcode + Agent Diagnosis, Manual Steps & Diff Fix
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            if let proposal = presenter.activeFixProposal {
                                HStack {
                                    Text(AppStrings.Performance.lineTitle(proposal.lineNumber))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                    Spacer()
                                    Button(AppStrings.Performance.openInXcode) {
                                        Task { await presenter.openInXcode(line: proposal.lineNumber) }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!presenter.hasProject)
                                }

                                Text(AppStrings.Performance.rootCauseTitle)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Text(proposal.diagnosis)
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)

                                if !proposal.manualSteps.isEmpty {
                                    Text(AppStrings.Performance.manualStepsTitle)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(Array(proposal.manualSteps.enumerated()), id: \.offset) { idx, step in
                                            Text("\(idx + 1). \(step)")
                                                .font(.system(size: 11))
                                                .foregroundStyle(CompanionTheme.textSecondary)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("- \(proposal.oldSnippet)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.coral)
                                    Text("+ \(proposal.newSnippet)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.mint)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.32))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                FlowLayout(spacing: 8) {
                                    Button(AppStrings.Performance.applyPatch) {
                                        presenter.applyActiveFix()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .preventSquish()

                                    if presenter.lastRevertRecord != nil {
                                        Button(AppStrings.Performance.undoPatch) {
                                            presenter.revertLastPatch()
                                        }
                                        .buttonStyle(.bordered)
                                        .preventSquish()
                                    }

                                    Button(AppStrings.Common.copyDiff) {
                                        presenter.copyActiveDiff()
                                    }
                                    .buttonStyle(.bordered)
                                    .preventSquish()

                                    Button(AppStrings.Performance.copyAntigravityPrompt) {
                                        presenter.copyAntigravityFindingPrompt()
                                    }
                                    .buttonStyle(.bordered)
                                    .preventSquish()
                                }
                            } else if let crash = presenter.activeCrashAnalysis {
                                HStack {
                                    Text("\(AppStrings.Performance.crashReportTitle) — \(crash.processName)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                    Spacer()
                                    Button(AppStrings.Performance.copyAntigravityPrompt) {
                                        presenter.copyAntigravityCrashPrompt()
                                    }
                                    .buttonStyle(.bordered)
                                    if crash.sourceFileName != nil || presenter.crashSourceSnippet != nil {
                                        Button(AppStrings.Performance.openInXcode) {
                                            Task { await presenter.openCrashInXcode() }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(!presenter.hasProject)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Text(crash.exceptionType)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(CompanionTheme.coral.opacity(0.2))
                                        .foregroundStyle(CompanionTheme.coral)
                                        .clipShape(Capsule())
                                    Text(crash.crashedThread)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.textSecondary)
                                }

                                Text(AppStrings.Performance.terminationLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Text(crash.terminationReason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)

                                Text(AppStrings.Performance.culpritLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Text(crash.culpritSymbol)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.amber)

                                if let fileName = crash.sourceFileName {
                                    Text("\(AppStrings.Performance.sourceLocationLabel): \(fileName):\(crash.sourceLineNumber ?? 1)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                }

                                if let snippet = presenter.crashSourceSnippet {
                                    Text(AppStrings.Performance.offendingCodeLabel)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                    XcodeCodeText(code: snippet.snippet, fontSize: 10)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.32))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                if !presenter.selectedReportContent.isEmpty {
                                    DisclosureGroup(AppStrings.Performance.rawLogLabel) {
                                        ScrollView {
                                            Text(presenter.selectedReportContent)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(CompanionTheme.textSecondary)
                                                .textSelection(.enabled)
                                        }
                                        .frame(maxHeight: 160)
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                }
                            } else if !presenter.selectedReportContent.isEmpty {
                                Text(presenter.selectedReportName)
                                    .font(.system(size: 12, weight: .semibold))
                                ScrollView {
                                    Text(presenter.selectedReportContent)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.textSecondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 260)
                            } else {
                                Text(AppStrings.Performance.emptySelectionPrompt)
                                    .font(.system(size: 12))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: presenter.selectedFindingID)
                    }
                }
            }
            .padding(20)
        }
        .task {
            await presenter.refreshReportsAndProcesses()
        }
    }

    private func telemetryMetric(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanionTheme.textMuted)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(CompanionTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: value)
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(CompanionTheme.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(CompanionTheme.glassLow))
    }

    @ViewBuilder
    private var realtimeSessionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(presenter.isXcodeDebugSessionActive ? CompanionTheme.mint : CompanionTheme.textMuted)
                    .frame(width: 7, height: 7)
                Text(presenter.isXcodeDebugSessionActive ? "Active Debug Target: \(presenter.selectedProcess?.name ?? "")" : "Not debugging Simulator / Device (Reset)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                if presenter.runtimeLeakSnapshot != nil || !presenter.realtimeSessionFreezes.isEmpty {
                    Button("Reset") {
                        presenter.resetRealtimeDebugSession()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if !presenter.isXcodeDebugSessionActive {
                Text("Run your app in Simulator or Physical Device from Xcode to capture realtime leaks & freezes. Session resets automatically when debugging stops.")
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionTheme.textMuted)
                    .padding(.vertical, 16)
            } else {
                runtimeLeakBanner
                if presenter.realtimeSessionFreezes.isEmpty {
                    Text("No realtime freezes captured in current debug session.")
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .padding(.vertical, 10)
                } else {
                    ForEach(presenter.realtimeSessionFreezes) { freeze in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(freeze.culpritSymbol) • \(String(format: "%.2fs", freeze.durationSeconds))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CompanionTheme.coral)
                            Text(freeze.reason)
                                .font(.system(size: 10))
                                .foregroundStyle(CompanionTheme.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(CompanionTheme.glassLow))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var runtimeLeakBanner: some View {
        let snap = presenter.runtimeLeakSnapshot
        let hasLeaks = (snap?.leakCount ?? 0) > 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(hasLeaks ? CompanionTheme.coral : (snap?.isAvailable == false ? CompanionTheme.amber : CompanionTheme.mint))
                    .frame(width: 7, height: 7)
                Text(AppStrings.Performance.runtimeLeaksTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textPrimary)
                Spacer()
                if let snap {
                    if snap.isAvailable {
                        Text(snap.leakCount > 0
                             ? AppStrings.Performance.runtimeLeaksSub(snap.leakCount, snap.leakedBytes / 1024)
                             : AppStrings.Performance.runtimeLeaksZero)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(hasLeaks ? CompanionTheme.coral : CompanionTheme.mint)
                    } else if let note = snap.note {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(CompanionTheme.amber)
                            .lineLimit(1)
                    }
                }
            }
            if let frames = snap?.topFrames, !frames.isEmpty {
                ForEach(frames.prefix(3), id: \.self) { frame in
                    Text(frame)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hasLeaks ? CompanionTheme.coral.opacity(0.12) : CompanionTheme.glassLow)
        )
    }

    private var priorityFilterBar: some View {
        FlowLayout(spacing: 6) {
            ForEach(IssuePriorityFilter.allCases) { filter in
                let active = presenter.selectedPriority == filter
                Button("\(priorityLabel(filter)) (\(presenter.count(for: filter)))") {
                    withAnimation(.snappy) {
                        presenter.selectedPriority = filter
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: active ? .bold : .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(active ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                .foregroundStyle(active ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                .clipShape(Capsule())
                .preventSquish()
            }
        }
    }

    private func priorityLabel(_ filter: IssuePriorityFilter) -> String {
        switch filter {
        case .all: AppStrings.Performance.priorityAll
        case .critical: "P0"
        case .warning: "P1"
        case .suggestion: "P2"
        }
    }

    private func priorityColor(_ severity: CodeReviewFinding.Severity) -> Color {
        switch severity {
        case .critical: CompanionTheme.coral
        case .warning: CompanionTheme.amber
        case .suggestion: CompanionTheme.mint
        }
    }
}

/// Seamless scrolling Instruments-style smooth Bezier area/line waveform with freeze flatline plateau, live running duration bar & hover code popover.
private struct InstrumentsTrackChart: View {
    let title: String
    let subtitle: String
    let samples: [Double]
    let timelinePoints: [TelemetryTimelinePoint]
    let maxScale: Double
    let accentColor: Color
    @Binding var hoverIndex: Int?
    let unitSuffix: String
    let isLive: Bool
    let activeFreezeSeconds: Double
    let activeFreezeEvent: FreezeLagEvent?
    let onSelectFreezeEvent: ((FreezeLagEvent) -> Void)?

    private func points(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let count = max(samples.count, 2)
        let stepX = width / CGFloat(count - 1)
        return samples.enumerated().map { i, val in
            let x = CGFloat(i) * stepX
            let norm = min(1.0, max(0.0, val / max(maxScale, 1)))
            let y = height - (CGFloat(norm) * (height - 10)) - 5
            return CGPoint(x: x, y: y)
        }
    }

    private func smoothLinePath(pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let curr = pts[i]
            let isFlatline = i < timelinePoints.count && timelinePoints[i].isFreezeFlatline && timelinePoints[i - 1].isFreezeFlatline
            if isFlatline {
                // Straight horizontal flatline during freeze/peak plateau
                path.addLine(to: CGPoint(x: curr.x, y: prev.y))
            } else {
                let midX = (prev.x + curr.x) * 0.5
                path.addCurve(
                    to: curr,
                    control1: CGPoint(x: midX, y: prev.y),
                    control2: CGPoint(x: midX, y: curr.y)
                )
            }
        }
        return path
    }

    /// Groups consecutive `isFreezeFlatline` indices into contiguous `(startIndex, endIndex, event, maxElapsed)` ranges.
    private var freezeSegments: [(start: Int, end: Int, event: FreezeLagEvent?, elapsed: Double)] {
        guard !timelinePoints.isEmpty else { return [] }
        var segments: [(start: Int, end: Int, event: FreezeLagEvent?, elapsed: Double)] = []
        var currentStart: Int?
        var currentEvent: FreezeLagEvent?
        var currentElapsed: Double = 0

        for (i, pt) in timelinePoints.enumerated() {
            if pt.isFreezeFlatline {
                if currentStart == nil { currentStart = i }
                if let ev = pt.freezeEvent { currentEvent = ev }
                currentElapsed = max(currentElapsed, pt.elapsedFreezeSeconds)
            } else if let s = currentStart {
                segments.append((start: s, end: i - 1, event: currentEvent, elapsed: max(0.5, currentElapsed)))
                currentStart = nil
                currentEvent = nil
                currentElapsed = 0
            }
        }
        if let s = currentStart {
            segments.append((start: s, end: timelinePoints.count - 1, event: currentEvent ?? activeFreezeEvent, elapsed: max(0.5, max(currentElapsed, activeFreezeSeconds))))
        }
        return segments
    }

    private var hoveredTimelinePoint: TelemetryTimelinePoint? {
        guard let idx = hoverIndex, idx >= 0, idx < timelinePoints.count else { return nil }
        return timelinePoints[idx]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textPrimary)
                    if let idx = hoverIndex, idx >= 0, idx < samples.count {
                        Text(AppStrings.Performance.sampleHover(idx + 1, samples[idx], unitSuffix))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(accentColor)
                            .contentTransition(.numericText())
                        if let ev = hoveredTimelinePoint?.freezeEvent {
                            Text("\(ev.locationLabel) • \(AppStrings.Performance.freezeDurationBadge(ev.durationSeconds))")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CompanionTheme.coral)
                                .lineLimit(1)
                        }
                    } else {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(CompanionTheme.textSecondary)
                    }
                }
                .frame(width: 220, alignment: .leading)

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let pts = points(width: w, height: h)
                    let count = max(samples.count, 2)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.24))

                        // Subtle horizontal gridlines
                        ForEach([0.25, 0.5, 0.75], id: \.self) { ratio in
                            Rectangle()
                                .fill(CompanionTheme.hairlineBorder.opacity(0.6))
                                .frame(height: 0.5)
                                .position(x: w * 0.5, y: h * CGFloat(ratio))
                        }

                        // Highlighted Freeze Flatline Zones + Straight Horizontal Plateau Bar
                        ForEach(Array(freezeSegments.enumerated()), id: \.offset) { _, seg in
                            if seg.start < pts.count && seg.end < pts.count {
                                let x1 = pts[seg.start].x
                                let x2 = max(x1 + 6, pts[seg.end].x)
                                let yFlat = pts[seg.start].y
                                let zoneWidth = x2 - x1

                                Rectangle()
                                    .fill(CompanionTheme.coral.opacity(0.18))
                                    .frame(width: zoneWidth, height: h)
                                    .position(x: x1 + zoneWidth * 0.5, y: h * 0.5)

                                Path { p in
                                    p.move(to: CGPoint(x: x1, y: yFlat))
                                    p.addLine(to: CGPoint(x: x2, y: yFlat))
                                }
                                .stroke(CompanionTheme.coral, style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                            }
                        }

                        // Smooth area fill
                        Path { path in
                            guard let first = pts.first, let last = pts.last else { return }
                            path.move(to: CGPoint(x: first.x, y: h))
                            path.addLine(to: first)
                            for i in 1..<pts.count {
                                let prev = pts[i - 1]
                                let curr = pts[i]
                                let isFlatline = i < timelinePoints.count && timelinePoints[i].isFreezeFlatline && timelinePoints[i - 1].isFreezeFlatline
                                if isFlatline {
                                    path.addLine(to: CGPoint(x: curr.x, y: prev.y))
                                } else {
                                    let midX = (prev.x + curr.x) * 0.5
                                    path.addCurve(
                                        to: curr,
                                        control1: CGPoint(x: midX, y: prev.y),
                                        control2: CGPoint(x: midX, y: curr.y)
                                    )
                                }
                            }
                            path.addLine(to: CGPoint(x: last.x, y: h))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.34), accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Smooth Bezier / Flatline stroke
                        smoothLinePath(pts: pts)
                            .stroke(accentColor, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

                        // Glowing live head dot
                        if isLive, let lastPt = pts.last {
                            let isFreezingNow = activeFreezeSeconds > 0
                            let headColor = isFreezingNow ? CompanionTheme.coral : accentColor
                            ZStack {
                                Circle()
                                    .fill(headColor.opacity(0.35))
                                    .frame(width: 12, height: 12)
                                Circle()
                                    .fill(headColor)
                                    .frame(width: 5, height: 5)
                            }
                            .position(lastPt)
                        }

                        // Interactive Scrubber Line + Dot + Floating Code & Duration Tooltip
                        if let idx = hoverIndex, idx >= 0, idx < pts.count {
                            let pt = pts[idx]
                            let hoveredFreeze = hoveredTimelinePoint?.freezeEvent
                            let dotColor = (hoveredTimelinePoint?.isFreezeFlatline == true) ? CompanionTheme.coral : accentColor
                            Rectangle()
                                .fill(CompanionTheme.textPrimary.opacity(0.45))
                                .frame(width: 1, height: h)
                                .offset(x: pt.x)
                            Circle()
                                .fill(dotColor)
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                .position(pt)

                            if let ev = hoveredFreeze {
                                FreezeHoverCodeBadge(event: ev)
                                    .frame(width: 270)
                                    .position(
                                        x: min(max(140, pt.x), max(140, w - 140)),
                                        y: h * 0.5
                                    )
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.28), value: samples)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let idx = Int((loc.x / max(w, 1)) * CGFloat(count - 1))
                            hoverIndex = min(max(0, idx), count - 1)
                        case .ended:
                            hoverIndex = nil
                        }
                    }
                    .onTapGesture {
                        if let ev = hoveredTimelinePoint?.freezeEvent ?? activeFreezeEvent {
                            onSelectFreezeEvent?(ev)
                        }
                    }
                }
                .frame(height: 58)
            }

            // Seamless Running Freeze Time Bar directly below the Dynamic Graph
            if !freezeSegments.isEmpty {
                HStack(spacing: 14) {
                    Spacer()
                        .frame(width: 220)
                    HStack(spacing: 8) {
                        ForEach(Array(freezeSegments.suffix(3).enumerated()), id: \.offset) { _, seg in
                            Button {
                                if let ev = seg.event {
                                    onSelectFreezeEvent?(ev)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: AppConstants.Icons.warning)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(CompanionTheme.coral)
                                    Text(AppStrings.Performance.freezeDurationBadge(seg.elapsed))
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.coral)
                                        .contentTransition(.numericText())
                                    if let ev = seg.event {
                                        Text("• \(ev.locationLabel)")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(CompanionTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(CompanionTheme.coral.opacity(0.15))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(CompanionTheme.coral.opacity(0.45), lineWidth: 0.8)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

/// Floating glass tooltip showing culprit file:line, freeze duration in seconds, and offending Swift code snippet on hover.
private struct FreezeHoverCodeBadge: View {
    let event: FreezeLagEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(AppStrings.Performance.freezeFlatlineBadge)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(CompanionTheme.coral.opacity(0.28))
                    .foregroundStyle(CompanionTheme.coral)
                    .clipShape(Capsule())
                Text(AppStrings.Performance.freezeDurationBadge(event.durationSeconds))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(CompanionTheme.textPrimary)
                Spacer()
                Text(String(format: "%.0f%% CPU", event.peakCPUPercent))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(CompanionTheme.amber)
            }
            Text("\(event.locationLabel) — \(event.reason)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CompanionTheme.textPrimary)
                .lineLimit(1)
            if !event.codeSnippet.isEmpty {
                Text(event.codeSnippet)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(CompanionTheme.mint)
                    .lineLimit(1)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(CompanionTheme.coral.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

/// Grafik Statis: Sleek Instruments-style full-width spike & pulse timeline track + full-width non-wrapping culprit code inspector bar.
private struct StaticFreezeTimelineCard: View {
    let events: [FreezeLagEvent]
    @Binding var hoveredEventID: String?
    let onClear: () -> Void
    let onSelectEvent: (FreezeLagEvent) -> Void

    private var maxDuration: Double {
        max(1.0, events.map(\.durationSeconds).max() ?? 1.0)
    }

    private var hoveredEvent: FreezeLagEvent? {
        guard let id = hoveredEventID else { return events.first }
        return events.first(where: { $0.id == id }) ?? events.first
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: AppConstants.Icons.warning)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.coral)
                        Text(AppStrings.Performance.staticFreezeGraphTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                    }
                    Spacer()
                    if !events.isEmpty {
                        Text(AppStrings.Performance.staticFreezeStats(events.count, events.map(\.durationSeconds).max() ?? 0))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CompanionTheme.amber)
                        Button(AppStrings.Performance.clearFreezeHistory) {
                            onClear()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                if events.isEmpty {
                    Text(AppStrings.Performance.noFreezeCaptured)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    // Row 1: 220pt Label Column + Full-Width Dark Instruments Pulse Track Canvas
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            if let inspected = hoveredEvent {
                                Text(inspected.locationLabel)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                    .lineLimit(1)
                                Text("\(AppStrings.Performance.freezeDurationBadge(inspected.durationSeconds)) • \(String(format: "%.0f%% CPU", inspected.peakCPUPercent))")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.coral)
                                    .lineLimit(1)
                            } else {
                                Text(AppStrings.Performance.staticFreezeGraphSub)
                                    .font(.system(size: 10))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(width: 220, alignment: .leading)

                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            let count = max(events.count, 1)
                            let stepX = count > 1 ? (w - 56) / CGFloat(count - 1) : 0

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.black.opacity(0.24))

                                // Subtle horizontal gridlines matching InstrumentsTrackChart
                                ForEach([0.25, 0.5, 0.75], id: \.self) { ratio in
                                    Rectangle()
                                        .fill(CompanionTheme.hairlineBorder.opacity(0.6))
                                        .frame(height: 0.5)
                                        .position(x: w * 0.5, y: h * CGFloat(ratio))
                                }

                                // Smooth connecting area + line across captured freeze spikes
                                Path { path in
                                    for (idx, ev) in events.enumerated() {
                                        let x = count > 1 ? 28 + CGFloat(idx) * stepX : w * 0.5
                                        let norm = min(1.0, max(0.18, ev.durationSeconds / maxDuration))
                                        let y = h - (CGFloat(norm) * (h - 18)) - 6
                                        if idx == 0 {
                                            path.move(to: CGPoint(x: x, y: y))
                                        } else {
                                            let prevX = 28 + CGFloat(idx - 1) * stepX
                                            let prevNorm = min(1.0, max(0.18, events[idx - 1].durationSeconds / maxDuration))
                                            let prevY = h - (CGFloat(prevNorm) * (h - 18)) - 6
                                            let midX = (prevX + x) * 0.5
                                            path.addCurve(
                                                to: CGPoint(x: x, y: y),
                                                control1: CGPoint(x: midX, y: prevY),
                                                control2: CGPoint(x: midX, y: y)
                                            )
                                        }
                                    }
                                }
                                .stroke(CompanionTheme.coral.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                                // Individual sleek vertical pulse stems + glowing peak nodes
                                ForEach(Array(events.enumerated()), id: \.element.id) { idx, ev in
                                    let isSelected = (hoveredEvent?.id == ev.id)
                                    let x = count > 1 ? 28 + CGFloat(idx) * stepX : w * 0.5
                                    let norm = min(1.0, max(0.18, ev.durationSeconds / maxDuration))
                                    let stemH = CGFloat(norm) * (h - 18)
                                    let topY = h - stemH - 6

                                    // Vertical pulse stem
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    isSelected ? CompanionTheme.coral : CompanionTheme.amber,
                                                    CompanionTheme.coral.opacity(0.25)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: isSelected ? 6 : 4, height: stemH)
                                        .position(x: x, y: h - (stemH * 0.5) - 6)

                                    // Peak node + duration tag
                                    ZStack {
                                        if isSelected {
                                            Circle()
                                                .fill(CompanionTheme.coral.opacity(0.32))
                                                .frame(width: 16, height: 16)
                                        }
                                        Circle()
                                            .fill(isSelected ? CompanionTheme.coral : CompanionTheme.amber)
                                            .frame(width: 7, height: 7)
                                            .overlay(Circle().stroke(Color.white.opacity(isSelected ? 0.9 : 0.4), lineWidth: 1))
                                    }
                                    .position(x: x, y: topY)

                                    Text(String(format: "%.1fs", ev.durationSeconds))
                                        .font(.system(size: 8.5, weight: isSelected ? .bold : .medium, design: .monospaced))
                                        .foregroundStyle(isSelected ? CompanionTheme.coral : CompanionTheme.textSecondary)
                                        .position(x: x, y: max(9, topY - 10))
                                }
                            }
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    guard count > 0 else { return }
                                    if count == 1 {
                                        hoveredEventID = events[0].id
                                    } else {
                                        let ratio = min(1.0, max(0.0, (loc.x - 28) / max(w - 56, 1)))
                                        let idx = min(count - 1, max(0, Int(round(ratio * CGFloat(count - 1)))))
                                        hoveredEventID = events[idx].id
                                    }
                                case .ended:
                                    break
                                }
                            }
                            .onTapGesture {
                                if let inspected = hoveredEvent {
                                    onSelectEvent(inspected)
                                }
                            }
                        }
                        .frame(height: 58)
                    }

                    // Row 2: Full-Width Clean Non-Wrapping Culprit Code Inspector Strip
                    if let inspected = hoveredEvent {
                        HStack(spacing: 10) {
                            Text(AppStrings.Performance.freezeDurationBadge(inspected.durationSeconds))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(CompanionTheme.coral.opacity(0.22))
                                .foregroundStyle(CompanionTheme.coral)
                                .clipShape(Capsule())

                            Text(inspected.locationLabel)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(CompanionTheme.textPrimary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            Text("— \(inspected.reason)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CompanionTheme.amber)
                                .lineLimit(1)

                            if !inspected.codeSnippet.isEmpty {
                                XcodeCodeText(code: inspected.codeSnippet, fontSize: 10)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            } else {
                                Spacer()
                            }

                            Button(AppStrings.Performance.inspectInAgentFix) {
                                onSelectEvent(inspected)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(CompanionTheme.glassLow)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(CompanionTheme.hairlineBorder, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
    }
}

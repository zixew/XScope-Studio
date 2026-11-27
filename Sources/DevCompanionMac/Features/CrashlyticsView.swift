import SwiftUI
import UniformTypeIdentifiers
import DevCompanionCore

struct CrashlyticsView: View {
    @Bindable var presenter: CrashlyticsPresenter
    var onChooseProject: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: AppConstants.Icons.crashlytics)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CompanionTheme.coral)
                            Text(AppStrings.Crashlytics.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(CompanionTheme.textPrimary)
                        }
                        Text(AppStrings.Crashlytics.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                    }
                    Spacer()
                    FlowLayout(spacing: 10) {
                        if presenter.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Toggle(AppStrings.Performance.showSystemReports, isOn: $presenter.showSystemReports)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .preventSquish()

                        Button(AppStrings.Crashlytics.refreshReports) {
                            Task { await presenter.refreshReports() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(presenter.isLoading)
                        .preventSquish()

                        Button(AppStrings.Enhancements.exportMD) {
                            presenter.copyMarkdownReport()
                        }
                        .buttonStyle(.bordered)
                        .disabled(presenter.reports.isEmpty)
                        .preventSquish()
                        .help("Export Crashlytics report to Markdown")
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

                // Firebase Crashlytics Summary KPI Cards + Visual Severity Distribution Bar
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                            kpiCard(
                                title: AppStrings.Crashlytics.totalEvents,
                                count: presenter.reports.count,
                                color: CompanionTheme.textPrimary
                            )
                            kpiCard(
                                title: AppStrings.Crashlytics.fatalCrashes,
                                count: presenter.fatalCount,
                                color: CompanionTheme.coral
                            )
                            kpiCard(
                                title: AppStrings.Crashlytics.nonFatalHangs,
                                count: presenter.hangCount,
                                color: CompanionTheme.amber
                            )
                            kpiCard(
                                title: AppStrings.Crashlytics.memoryJetsam,
                                count: presenter.memoryCount,
                                color: CompanionTheme.mint
                            )
                        }

                        GeometryReader { geo in
                            let total = max(1, presenter.reports.count)
                            let w = geo.size.width
                            let fatalW = w * CGFloat(presenter.fatalCount) / CGFloat(total)
                            let hangW = w * CGFloat(presenter.hangCount) / CGFloat(total)
                            let memW = max(0, w - fatalW - hangW)

                            HStack(spacing: 2) {
                                if presenter.reports.isEmpty {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(CompanionTheme.glassHigh)
                                } else {
                                    if presenter.fatalCount > 0 {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(CompanionTheme.coral)
                                            .frame(width: max(6, fatalW))
                                    }
                                    if presenter.hangCount > 0 {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(CompanionTheme.amber)
                                            .frame(width: max(6, hangW))
                                    }
                                    if presenter.memoryCount > 0 || memW > 4 {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(CompanionTheme.mint.opacity(0.75))
                                            .frame(width: max(4, memW))
                                    }
                                }
                            }
                        }
                        .frame(height: 8)
                        .animation(MotionTokens.snappy(reduceMotion: reduceMotion), value: presenter.reports.count)
                    }
                }

                // Interactive Crash & Hang Timeline Track (Matching Leaks & Hangs)
                if !presenter.filteredReports.isEmpty {
                    crashTimelineCard
                }

                // Priority Filter (P0/P1/P2) + Kind Filter + Search Bar (FlowLayout prevents chip & button squish)
                GlassCard {
                    FlowLayout(spacing: 8) {
                        ForEach(IssuePriorityFilter.allCases) { pFilter in
                            let active = presenter.selectedPriority == pFilter
                            Button("\(priorityLabel(pFilter)) (\(presenter.priorityCount(for: pFilter)))") {
                                withAnimation(.snappy) {
                                    presenter.selectedPriority = pFilter
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: active ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(active ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                            .foregroundStyle(active ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                            .clipShape(Capsule())
                            .preventSquish()
                        }

                        Divider().frame(height: 16)

                        ForEach(CrashReportKindFilter.allCases) { filter in
                            let active = presenter.kindFilter == filter
                            Button("\(filter.rawValue) (\(presenter.count(for: filter)))") {
                                withAnimation(.snappy) {
                                    presenter.kindFilter = filter
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: active ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(active ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                            .foregroundStyle(active ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                            .clipShape(Capsule())
                            .preventSquish()
                        }

                        HStack(spacing: 6) {
                            Image(systemName: AppConstants.Icons.magnifyingGlass)
                                .font(.system(size: 11))
                                .foregroundStyle(CompanionTheme.textMuted)
                            TextField(AppStrings.Crashlytics.searchPlaceholder, text: $presenter.searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(minWidth: 190, maxWidth: 250)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(CompanionTheme.glassLow)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                        )
                    }
                }

                // Master-Detail Issue Stream & Code-First Crash Inspector
                HStack(alignment: .top, spacing: 14) {
                    // Left: Priority + NEW Sorted Crash & Hang Stream (LazyVStack + Progressive Infinite Scroll)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            if presenter.filteredReports.isEmpty {
                                Text(AppStrings.Crashlytics.noReportsFound)
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
                            } else {
                                RecycledVirtualList(items: presenter.filteredReports, rowSpacing: 6) { report in
                                    let isSelected = presenter.selectedReportID == report.id
                                    Button {
                                        withAnimation(.snappy) {
                                            presenter.selectReport(report)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 5) {
                                                Text(report.priority.priorityBadge)
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(priorityColor(report.priority).opacity(0.22))
                                                    .foregroundStyle(priorityColor(report.priority))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    .preventSquish()

                                                if report.isNew {
                                                    Text(AppStrings.Performance.newBadge)
                                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1.5)
                                                        .background(CompanionTheme.mint.opacity(0.22))
                                                        .foregroundStyle(CompanionTheme.mint)
                                                        .clipShape(Capsule())
                                                        .preventSquish()
                                                }

                                                Text(badgeText(for: report.kind))
                                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(badgeColor(for: report.kind).opacity(0.18))
                                                    .foregroundStyle(badgeColor(for: report.kind))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    .preventSquish()

                                                Text(report.sourceLocation ?? report.processName)
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(CompanionTheme.textPrimary)
                                                    .lineLimit(1)

                                                Spacer()

                                                Text(report.timestamp, style: .relative)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(CompanionTheme.textMuted)
                                                    .preventSquish()
                                            }

                                            Text(report.humanTitle)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(CompanionTheme.textPrimary)
                                                .lineLimit(1)

                                            if !report.whenContext.isEmpty {
                                                Text(report.whenContext)
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundStyle(CompanionTheme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7)
                                                .fill(isSelected ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 7)
                                                        .stroke(isSelected ? badgeColor(for: report.kind).opacity(0.65) : .clear, lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(minHeight: 400, maxHeight: 540)
                            }
                        }
                    }
                    .frame(minWidth: 260, idealWidth: AppConstants.Layout.leaksLeftColumnWidth, maxWidth: 360)

                    // Right: Where / When / Why + Offending Code + Agent Patch + Stack Trace
                    GlassCard {
                        if let crash = presenter.activeAnalysis {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(crash.processName): \(crash.sourceFileName.map { "\($0):\(crash.sourceLineNumber ?? 1)" } ?? crash.exceptionType)")
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundStyle(CompanionTheme.coral)
                                        Text(presenter.selectedReportName)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(CompanionTheme.textMuted)
                                    }
                                    Spacer()
                                    if crash.sourceFileName != nil || presenter.sourceSnippet != nil {
                                        Button(AppStrings.Performance.openInXcode) {
                                            Task { await presenter.openInXcode() }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(!presenter.hasProject)
                                    }
                                    Button(AppStrings.Performance.copyAntigravityPrompt) {
                                        presenter.copyAntigravityCrashPrompt()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                // Clear 3-Row "Where in Code / When It Happened / Why It Crashed" Diagnostic Card
                                VStack(alignment: .leading, spacing: 6) {
                                    diagnosticRow(
                                        label: AppStrings.Crashlytics.whereFileLineLabel,
                                        value: crash.sourceFileName.map { "\($0) : Line \(crash.sourceLineNumber ?? 1)" } ?? crash.culpritSymbol,
                                        color: CompanionTheme.mint
                                    )
                                    diagnosticRow(
                                        label: AppStrings.Crashlytics.whenActionLabel,
                                        value: crash.whenAction,
                                        color: CompanionTheme.amber
                                    )
                                    diagnosticRow(
                                        label: AppStrings.Crashlytics.whyCauseLabel,
                                        value: "\(crash.humanExplanation) (\(crash.exceptionType))",
                                        color: CompanionTheme.coral
                                    )
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(CompanionTheme.glassLow))

                                // Offending Swift Source Code Context
                                if let snippet = presenter.sourceSnippet {
                                    Text("\(AppStrings.Performance.offendingCodeLabel) (\(snippet.fileName):\(snippet.lineNumber))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                    XcodeCodeText(code: snippet.snippet, fontSize: 10)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.35))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                // Agent Fix & Diff Patcher (Matching Leaks & Hangs)
                                if let proposal = presenter.activeFixProposal {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(AppStrings.Crashlytics.agentFixSectionTitle)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(CompanionTheme.textPrimary)

                                        ForEach(Array(proposal.manualSteps.enumerated()), id: \.offset) { idx, step in
                                            Text("\(idx + 1). \(step)")
                                                .font(.system(size: 10))
                                                .foregroundStyle(CompanionTheme.textSecondary)
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("- \(proposal.oldSnippet)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(CompanionTheme.coral)
                                            Text("+ \(proposal.newSnippet)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(CompanionTheme.mint)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.32))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                        HStack(spacing: 8) {
                                            Button(AppStrings.Performance.applyPatch) {
                                                presenter.applyActiveFix()
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            .disabled(!presenter.hasProject || proposal.filePath == nil)
                                            .preventSquish()

                                            if presenter.lastRevertRecord != nil {
                                                Button(AppStrings.Performance.undoPatch) {
                                                    presenter.revertLastPatch()
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                .preventSquish()
                                            }

                                            Button(AppStrings.Common.copyDiff) {
                                                presenter.copyActiveDiff()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .preventSquish()
                                        }
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(CompanionTheme.glassLow))
                                }

                                // Segmented Sub-Tab: Stack Trace vs Raw .ips Log
                                HStack(spacing: 8) {
                                    tabButton(.stackTrace, title: AppStrings.Crashlytics.stackTraceTab)
                                    tabButton(.rawLog, title: AppStrings.Crashlytics.rawLogTab)
                                    Spacer()
                                }

                                if presenter.inspectorTab == .stackTrace {
                                    RecycledVirtualList(
                                        items: crash.stackFrames.enumerated().map { RecycledIndexItem(id: $0.offset, value: $0.element) },
                                        rowSpacing: 4
                                    ) { entry in
                                        let idx = entry.id
                                        let frame = entry.value
                                        let isApp = presenter.isAppFrame(frame)
                                        HStack(spacing: 8) {
                                            Text("#\(idx)")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(CompanionTheme.textMuted)
                                                .frame(width: 24, alignment: .trailing)

                                            Text(isApp ? AppStrings.Crashlytics.appFrameBadge : AppStrings.Crashlytics.sysFrameBadge)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background((isApp ? CompanionTheme.coral : CompanionTheme.textMuted).opacity(0.22))
                                                .foregroundStyle(isApp ? CompanionTheme.coral : CompanionTheme.textMuted)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                                .preventSquish()

                                            Text(frame)
                                                .font(.system(size: 10, weight: isApp ? .semibold : .regular, design: .monospaced))
                                                .foregroundStyle(isApp ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                                                .textSelection(.enabled)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(isApp ? CompanionTheme.coral.opacity(0.12) : CompanionTheme.glassLow)
                                        )
                                    }
                                    .frame(minHeight: 160, maxHeight: 240)
                                } else {
                                    ScrollView {
                                        Text(presenter.selectedReportContent)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(CompanionTheme.textSecondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(8)
                                    .frame(minHeight: 160, maxHeight: 240)
                                    .background(Color.black.opacity(0.32))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        } else {
                            Text(AppStrings.Crashlytics.selectEventPrompt)
                                .font(.system(size: 12))
                                .foregroundStyle(CompanionTheme.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 380, alignment: .center)
                        }
                    }
                }
            }
            .padding(20)
        }
        .task {
            await presenter.refreshReports()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    presenter.importDroppedCrashFile(url: url)
                }
            }
            return true
        }
    }

    // MARK: - Interactive Crash & Hang Timeline Track
    private var crashTimelineCard: some View {
        let items = Array(presenter.filteredReports.prefix(16))
        let inspected = presenter.inspectedTimelineReport

        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: AppConstants.Icons.waveform)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CompanionTheme.coral)
                            Text(AppStrings.Crashlytics.timelineTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CompanionTheme.textPrimary)
                        }
                        if let inspected {
                            Text(inspected.sourceLocation ?? inspected.processName)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(CompanionTheme.mint)
                                .lineLimit(1)
                        } else {
                            Text(AppStrings.Crashlytics.timelineSub)
                                .font(.system(size: 10))
                                .foregroundStyle(CompanionTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(width: 220, alignment: .leading)

                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let count = max(items.count, 1)
                        let stepX = count > 1 ? (w - 56) / CGFloat(count - 1) : 0

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.24))

                            ForEach([0.25, 0.5, 0.75], id: \.self) { ratio in
                                Rectangle()
                                    .fill(CompanionTheme.hairlineBorder.opacity(0.6))
                                    .frame(height: 0.5)
                                    .position(x: w * 0.5, y: h * CGFloat(ratio))
                            }

                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                let isSelected = inspected?.id == item.id
                                let x = count > 1 ? 28 + CGFloat(idx) * stepX : w * 0.5
                                let norm: Double = switch item.priority {
                                case .critical: 0.90
                                case .warning: 0.65
                                case .suggestion: 0.42
                                }
                                let stemH = CGFloat(norm) * (h - 16)
                                let topY = h - stemH - 6
                                let color = badgeColor(for: item.kind)

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [color, color.opacity(0.22)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: isSelected ? 6 : 4, height: stemH)
                                    .position(x: x, y: h - (stemH * 0.5) - 6)

                                ZStack {
                                    if isSelected {
                                        Circle()
                                            .fill(color.opacity(0.32))
                                            .frame(width: 16, height: 16)
                                    }
                                    Circle()
                                        .fill(color)
                                        .frame(width: 7, height: 7)
                                        .overlay(Circle().stroke(Color.white.opacity(isSelected ? 0.9 : 0.4), lineWidth: 1))
                                }
                                .position(x: x, y: topY)
                            }
                        }
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard count > 0 else { return }
                                if count == 1 {
                                    presenter.hoveredReportID = items[0].id
                                } else {
                                    let ratio = min(1.0, max(0.0, (loc.x - 28) / max(w - 56, 1)))
                                    let idx = min(count - 1, max(0, Int(round(ratio * CGFloat(count - 1)))))
                                    presenter.hoveredReportID = items[idx].id
                                }
                            case .ended:
                                break
                            }
                        }
                        .onTapGesture {
                            if let inspected {
                                presenter.selectReport(inspected)
                            }
                        }
                    }
                    .frame(height: 54)
                }

                if let inspected {
                    HStack(spacing: 10) {
                        Text(inspected.priority.priorityBadge)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(priorityColor(inspected.priority).opacity(0.22))
                            .foregroundStyle(priorityColor(inspected.priority))
                            .clipShape(Capsule())

                        Text(inspected.sourceLocation ?? inspected.processName)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(CompanionTheme.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Text(inspected.humanTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanionTheme.amber)
                            .lineLimit(1)

                        Spacer()

                        Text(inspected.whenContext)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .lineLimit(1)

                        Button(AppStrings.Performance.inspectInAgentFix) {
                            presenter.selectReport(inspected)
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

    private func diagnosticRow(label: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(label):")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(CompanionTheme.textMuted)
                .frame(width: 170, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func kpiCard(title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanionTheme.textMuted)
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(CompanionTheme.glassLow))
    }

    private func tabButton(_ tab: CrashInspectorTab, title: String) -> some View {
        let active = presenter.inspectorTab == tab
        return Button(title) {
            withAnimation(.snappy) {
                presenter.inspectorTab = tab
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: active ? .bold : .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
        .foregroundStyle(active ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private func badgeText(for kind: DiagnosticReportItem.Kind) -> String {
        switch kind {
        case .crash: "FATAL"
        case .hang: "HANG"
        case .memory: "JETSAM"
        case .other: "DIAG"
        }
    }

    private func badgeColor(for kind: DiagnosticReportItem.Kind) -> Color {
        switch kind {
        case .crash: CompanionTheme.coral
        case .hang: CompanionTheme.amber
        case .memory: CompanionTheme.mint
        case .other: CompanionTheme.textSecondary
        }
    }
}

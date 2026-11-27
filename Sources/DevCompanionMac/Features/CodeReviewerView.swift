import SwiftUI
import DevCompanionCore

struct CodeReviewerView: View {
    @Bindable var presenter: CodeReviewerPresenter
    var onChooseProject: (() -> Void)?
    @State private var showSourceBranchPopover = false
    @State private var showTargetBranchPopover = false
    @State private var showModulePopover = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header + Primary Actions (FlowLayout prevents squished buttons)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppStrings.CodeReview.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        Text(AppStrings.CodeReview.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(CompanionTheme.textSecondary)
                    }
                    Spacer()

                    FlowLayout(spacing: 8) {
                        if presenter.lastRevertRecord != nil {
                            Button(AppStrings.Performance.undoPatch) {
                                presenter.revertLastPatch()
                            }
                            .buttonStyle(.bordered)
                            .preventSquish()
                        }

                        if presenter.isResultsGateOpen {
                            Button(AppStrings.CodeReview.copyPRReport) {
                                presenter.copyPRMarkdownReport()
                            }
                            .buttonStyle(.bordered)
                            .preventSquish()
                        }

                        if presenter.isAnalyzing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(AppStrings.CodeReview.analyzingProgress)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(CompanionTheme.amber)
                                    .preventSquish()
                                Button(AppStrings.CodeReview.stopReview) {
                                    presenter.cancelReview()
                                }
                                .buttonStyle(.bordered)
                                .preventSquish()
                            }
                        } else {
                            Button(AppStrings.CodeReview.analyzeCode) {
                                presenter.startReview()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!presenter.canAnalyze)
                            .preventSquish()
                        }
                    }
                }

                if !presenter.hasProjectURL, let onChooseProject {
                    GuidedRequirementBanner(
                        icon: AppConstants.Icons.folder,
                        message: AppStrings.Overview.needProjectBanner,
                        actionTitle: AppStrings.Common.selectXcodeProjectButton,
                        action: onChooseProject
                    )
                }

                // Step 1: Interactive Scope Mode Cards (Starts unselected so opening Code Review has zero lag)
                if presenter.hasProjectURL {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                ForEach(CodeReviewScopeMode.allCases) { mode in
                                    let isSelected = presenter.selectedScopeMode == mode
                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            presenter.selectedScopeMode = mode
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: scopeIcon(for: mode))
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(isSelected ? CompanionTheme.accent : CompanionTheme.textSecondary)
                                            Text(mode.rawValue)
                                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                                .foregroundStyle(isSelected ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: AppConstants.Icons.checkmark)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(CompanionTheme.accent)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(InteractiveSurfaceButtonStyle(cornerRadius: 8, isSelected: isSelected))
                                }

                                if presenter.isResultsGateOpen {
                                    Text(presenter.isPRReadyToMerge ? AppStrings.CodeReview.prReadyBadge : AppStrings.CodeReview.prBlockedBadge)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background((presenter.isPRReadyToMerge ? CompanionTheme.mint : CompanionTheme.coral).opacity(0.22))
                                        .foregroundStyle(presenter.isPRReadyToMerge ? CompanionTheme.mint : CompanionTheme.coral)
                                        .clipShape(Capsule())
                                        .preventSquish()
                                }
                            }

                            // Step 2: Mode-Specific Searchable Target Configuration
                            if presenter.selectedScopeMode == .branchDiff {
                                branchDiffSelectorSection
                            } else if presenter.selectedScopeMode == .moduleFolder {
                                moduleFolderSelectorSection
                            }
                        }
                    }
                }

                // Step 3: Results Console (or Paste Editor when no project is connected)
                HStack(alignment: .top, spacing: 14) {
                    if !presenter.hasProjectURL {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(AppStrings.CodeReview.pasteEditorTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                TextEditor(text: $presenter.customSwiftCode)
                                    .font(.system(size: 12, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 380)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            // Top Toolbar: Findings Count + View Mode Toggle (By Priority vs Grouped by File) + Search Findings + Priority Chips
                            FlowLayout(spacing: 10) {
                                Text(AppStrings.CodeReview.findingsTitle(presenter.displayedFindings.count))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                    .preventSquish()

                                HStack(spacing: 4) {
                                    viewModeButton(title: AppStrings.CodeReview.viewByPriority, isGrouped: false)
                                    viewModeButton(title: AppStrings.CodeReview.viewByFile, isGrouped: true)
                                }
                                .padding(2)
                                .background(RoundedRectangle(cornerRadius: 7).fill(CompanionTheme.glassLow))

                                // Search Findings Input
                                HStack(spacing: 6) {
                                    Image(systemName: AppConstants.Icons.magnifyingGlass)
                                        .font(.system(size: 11))
                                        .foregroundStyle(CompanionTheme.textMuted)
                                    TextField(AppStrings.CodeReview.searchFindingsPlaceholder, text: $presenter.findingsSearchText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .frame(minWidth: 180, maxWidth: 230)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(CompanionTheme.glassLow)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                                )

                                // Priority Filter Chips (All / P0 / P1 / P2)
                                ForEach(IssuePriorityFilter.allCases) { filter in
                                    let active = presenter.selectedPriority == filter
                                    Button("\(priorityLabel(filter)) (\(presenter.count(for: filter)))") {
                                        withAnimation(.snappy) {
                                            presenter.selectedPriority = filter
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
                            }

                            // 6-Category Quality Filter Bar (Responsive FlowLayout)
                            FlowLayout(spacing: 6) {
                                let allCatActive = presenter.selectedCategory == nil
                                Button(AppStrings.CodeReview.categoryAll) {
                                    withAnimation(.snappy) {
                                        presenter.selectedCategory = nil
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: allCatActive ? .bold : .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(allCatActive ? CompanionTheme.accentTint : CompanionTheme.glassLow)
                                .foregroundStyle(allCatActive ? CompanionTheme.accent : CompanionTheme.textSecondary)
                                .clipShape(Capsule())
                                .preventSquish()

                                ForEach(CodeReviewFinding.Category.allCases) { cat in
                                    let count = presenter.categoryCount(cat)
                                    let active = presenter.selectedCategory == cat
                                    Button("\(cat.rawValue) (\(count))") {
                                        withAnimation(.snappy) {
                                            presenter.selectedCategory = active ? nil : cat
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: active ? .bold : .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(active ? CompanionTheme.accentTint : CompanionTheme.glassLow)
                                    .foregroundStyle(active ? CompanionTheme.accent : CompanionTheme.textSecondary)
                                    .clipShape(Capsule())
                                    .preventSquish()
                                }
                            }

                            if !presenter.isResultsGateOpen {
                                VStack(spacing: 8) {
                                    Image(systemName: AppConstants.Icons.shieldCheck)
                                        .font(.system(size: 26))
                                        .foregroundStyle(CompanionTheme.textMuted)
                                    Text(presenter.hasProjectURL ? AppStrings.CodeReview.selectScopePrompt : AppStrings.CodeReview.emptyPrompt)
                                        .font(.system(size: 13))
                                        .foregroundStyle(CompanionTheme.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
                            } else if presenter.displayedFindings.isEmpty {
                                Text(AppStrings.CodeReview.noFindings)
                                    .font(.system(size: 13))
                                    .foregroundStyle(CompanionTheme.mint)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
                            } else if presenter.groupByFile {
                                RecycledVirtualList(items: presenter.displayedFileGroups, rowSpacing: 12) { group in
                                    fileGroupCard(group)
                                }
                                .frame(minHeight: 380, maxHeight: 560)
                            } else {
                                RecycledVirtualList(items: presenter.displayedFindings, rowSpacing: 10) { item in
                                    findingRowCard(item)
                                }
                                .frame(minHeight: 380, maxHeight: 560)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .task {
            await presenter.refreshProjectGitAndModules()
        }
        .sheet(item: $presenter.selectedFindingForDetail) { finding in
            findingDetailSheet(finding)
        }
    }

    // MARK: - Searchable Branch Diff Section
    private var branchDiffSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 10) {
                Text(AppStrings.CodeReview.sourceBranchLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .preventSquish()

                // Source Branch Searchable Popover Button
                Button {
                    showSourceBranchPopover.toggle()
                } label: {
                    branchButtonLabel(
                        selected: presenter.sourceBranch,
                        placeholder: AppStrings.CodeReview.selectSourceBranchPlaceholder,
                        isCurrent: !presenter.sourceBranch.isEmpty && presenter.sourceBranch == presenter.currentGitBranch
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSourceBranchPopover, arrowEdge: .bottom) {
                    SearchableBranchPopover(
                        branches: presenter.availableBranches,
                        currentBranch: presenter.currentGitBranch,
                        selectedBranch: $presenter.sourceBranch,
                        isPresented: $showSourceBranchPopover
                    )
                }

                // Swap Branches Button
                Button {
                    withAnimation(.snappy) {
                        presenter.swapBranches()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: AppConstants.Icons.arrowClockwise)
                            .font(.system(size: 10, weight: .bold))
                        Text(AppStrings.CodeReview.swapBranches)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(CompanionTheme.glassLow))
                    .foregroundStyle(CompanionTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(presenter.sourceBranch.isEmpty && presenter.targetBranch.isEmpty)
                .preventSquish()

                Text(AppStrings.CodeReview.targetBranchLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .preventSquish()

                // Target Branch Searchable Popover Button
                Button {
                    showTargetBranchPopover.toggle()
                } label: {
                    branchButtonLabel(
                        selected: presenter.targetBranch,
                        placeholder: AppStrings.CodeReview.selectTargetBranchPlaceholder,
                        isCurrent: !presenter.targetBranch.isEmpty && presenter.targetBranch == presenter.currentGitBranch
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTargetBranchPopover, arrowEdge: .bottom) {
                    SearchableBranchPopover(
                        branches: presenter.availableBranches,
                        currentBranch: presenter.currentGitBranch,
                        selectedBranch: $presenter.targetBranch,
                        isPresented: $showTargetBranchPopover
                    )
                }

                Button(AppStrings.CodeReview.quickFillPRBranches) {
                    withAnimation(.snappy) {
                        presenter.quickFillCurrentToBaseBranches()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .preventSquish()

                Toggle(AppStrings.CodeReview.changedLinesOnly, isOn: $presenter.changedLinesOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .preventSquish()

                if let summary = presenter.branchComparisonSummary {
                    Text(AppStrings.CodeReview.prDiffSummary(summary.commits.count, summary.changedSwiftFiles.count))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CompanionTheme.amber)
                        .preventSquish()
                }
            }

            if let summary = presenter.branchComparisonSummary,
               (!summary.commits.isEmpty || !summary.changedSwiftFiles.isEmpty) {
                DisclosureGroup(AppStrings.CodeReview.commitsTitle) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(summary.commits.prefix(8), id: \.self) { commit in
                                Text(commit)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(summary.changedSwiftFiles.prefix(8), id: \.self) { file in
                                Text(file)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.mint)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanionTheme.textSecondary)
            }
        }
    }

    // MARK: - Searchable Module / Folder Section
    private var moduleFolderSelectorSection: some View {
        HStack(spacing: 10) {
            Text(AppStrings.CodeReview.modulePickerLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CompanionTheme.textSecondary)

            Button {
                showModulePopover.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: AppConstants.Icons.folder)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.accent)
                    if presenter.selectedModuleFolder.isEmpty {
                        Text(AppStrings.CodeReview.selectModulePlaceholder)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CompanionTheme.textMuted)
                            .lineLimit(1)
                    } else {
                        let split = CodeReviewEngine.splitModuleDisplay(presenter.selectedModuleFolder)
                        Text(split.leafName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                            .lineLimit(1)
                        if let parent = split.parentPath {
                            Text("(\(parent))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(CompanionTheme.textMuted)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                    Spacer()
                    Image(systemName: AppConstants.Icons.chevronRight)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CompanionTheme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 280)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CompanionTheme.glassLow)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModulePopover, arrowEdge: .bottom) {
                SearchableModulePopover(
                    modules: presenter.availableModules,
                    selectedModule: $presenter.selectedModuleFolder,
                    isPresented: $showModulePopover
                )
            }

            Button(AppStrings.CodeReview.browseFolder) {
                presenter.pickCustomModuleFolder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
    }

    private func branchButtonLabel(selected: String, placeholder: String, isCurrent: Bool) -> some View {
        HStack(spacing: 6) {
            Text(selected.isEmpty ? placeholder : selected)
                .font(.system(size: 11, weight: selected.isEmpty ? .regular : .semibold, design: .monospaced))
                .foregroundStyle(selected.isEmpty ? CompanionTheme.textMuted : CompanionTheme.textPrimary)
                .lineLimit(1)
            if isCurrent {
                Text(AppStrings.CodeReview.currentBranchBadge)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(CompanionTheme.mint.opacity(0.22))
                    .foregroundStyle(CompanionTheme.mint)
                    .clipShape(Capsule())
            }
            Spacer()
            Image(systemName: AppConstants.Icons.chevronRight)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CompanionTheme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(CompanionTheme.glassLow)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
        )
    }

    private func viewModeButton(title: String, isGrouped: Bool) -> some View {
        let active = presenter.groupByFile == isGrouped
        return Button(title) {
            withAnimation(.snappy) {
                presenter.groupByFile = isGrouped
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: active ? .bold : .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(active ? CompanionTheme.glassHigh : .clear)
        .foregroundStyle(active ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func fileGroupCard(_ group: CodeReviewFileGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: AppConstants.Icons.docText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CompanionTheme.accent)
                Text(group.fileName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(CompanionTheme.textPrimary)
                if group.hasNew {
                    Text(AppStrings.Performance.newBadge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CompanionTheme.mint.opacity(0.22))
                        .foregroundStyle(CompanionTheme.mint)
                        .clipShape(Capsule())
                }
                Spacer()
                if group.criticalCount > 0 {
                    badgePill("P0: \(group.criticalCount)", color: CompanionTheme.coral)
                }
                if group.warningCount > 0 {
                    badgePill("P1: \(group.warningCount)", color: CompanionTheme.amber)
                }
                if group.suggestionCount > 0 {
                    badgePill("P2: \(group.suggestionCount)", color: CompanionTheme.mint)
                }
                if let firstFinding = group.findings.first {
                    Button(AppStrings.Performance.openInXcode) {
                        Task { await presenter.openInXcode(firstFinding) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(!presenter.hasProjectURL)
                }
            }

            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(group.findings.prefix(ProgressiveListChunker.defaultPageSize)) { item in
                    findingRowCard(item)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(CompanionTheme.glassLow)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
        )
    }

    private func findingRowCard(_ item: CodeReviewFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                Text("\(item.severity.priorityBadge) \(item.severity.rawValue.uppercased())")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(severityColor(item.severity).opacity(0.2))
                    .foregroundStyle(severityColor(item.severity))
                    .clipShape(Capsule())
                    .preventSquish()
                if item.isNew {
                    Text(AppStrings.Performance.newBadge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CompanionTheme.mint.opacity(0.22))
                        .foregroundStyle(CompanionTheme.mint)
                        .clipShape(Capsule())
                        .preventSquish()
                }
                Text("\(item.fileName):\(item.lineNumber)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CompanionTheme.textPrimary)
                    .preventSquish()
                Text(item.category.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(CompanionTheme.textMuted)
                    .preventSquish()

                Button(AppStrings.Performance.openInXcode) {
                    Task { await presenter.openInXcode(item) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!presenter.hasProjectURL)
                .preventSquish()

                Button(AppStrings.Performance.applyPatch) {
                    presenter.applyQuickFix(for: item)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .preventSquish()

                Button(AppStrings.Performance.copyAntigravityPrompt) {
                    presenter.copyAntigravityPrompt(for: item)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .preventSquish()

                Button {
                    presenter.selectedFindingForDetail = item
                } label: {
                    HStack(spacing: 3) {
                        Text("Detail")
                        Image(systemName: AppConstants.Icons.chevronRight)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .preventSquish()
            }
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CompanionTheme.textPrimary)
                .lineLimit(2)
            Text(item.detail)
                .font(.system(size: 11))
                .foregroundStyle(CompanionTheme.textSecondary)
                .lineLimit(2)
            XcodeCodeText(code: item.codeSnippet, fontSize: 11)
                .lineLimit(3)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(CompanionTheme.glassLow)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            presenter.selectedFindingForDetail = item
        }
    }

    @ViewBuilder
    private func findingDetailSheet(_ item: CodeReviewFinding) -> some View {
        let proposal = presenter.detailFixProposal(for: item)
        let compactPrompt = presenter.detailCompactPrompt(for: item)
        let sourceContext = presenter.detailSourceContext(for: item)
        let estTokens = max(1, (compactPrompt.count + 3) / 4)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(item.severity.priorityBadge) \(item.severity.rawValue.uppercased())")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(severityColor(item.severity).opacity(0.22))
                            .foregroundStyle(severityColor(item.severity))
                            .clipShape(Capsule())
                        Text(item.category.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(CompanionTheme.accent.opacity(0.16))
                            .foregroundStyle(CompanionTheme.accent)
                            .clipShape(Capsule())
                        Text("\(item.fileName):\(item.lineNumber)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CompanionTheme.textPrimary)
                    }
                    Text(item.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CompanionTheme.textPrimary)
                }
                Spacer()
                Button("Close") {
                    presenter.selectedFindingForDetail = nil
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .textSelection(.enabled)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(sourceContext != nil ? "Source Context (\(item.fileName):\(item.lineNumber))" : "Offending Snippet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        XcodeCodeText(code: sourceContext ?? item.codeSnippet, fontSize: 11)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if proposal.newSnippet != proposal.oldSnippet {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Local Deterministic Fix (0 AI Tokens)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CompanionTheme.mint)
                            Text("- \(proposal.oldSnippet)\n+ \(proposal.newSnippet)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(CompanionTheme.textPrimary)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CompanionTheme.mint.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if !proposal.manualSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppStrings.Performance.manualStepsTitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CompanionTheme.textPrimary)
                            ForEach(Array(proposal.manualSteps.enumerated()), id: \.offset) { idx, step in
                                Text("\(idx + 1). \(step)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Compact AI Prompt")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CompanionTheme.textPrimary)
                            Text("~\(estTokens) tokens")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(CompanionTheme.accent.opacity(0.18))
                                .foregroundStyle(CompanionTheme.accent)
                                .clipShape(Capsule())
                        }
                        Text(compactPrompt)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            HStack(spacing: 8) {
                Button(AppStrings.Performance.openInXcode) {
                    Task { await presenter.openInXcode(item) }
                }
                .buttonStyle(.bordered)
                .disabled(!presenter.hasProjectURL)

                Button(AppStrings.Performance.applyPatch) {
                    presenter.applyQuickFix(for: item)
                }
                .buttonStyle(.borderedProminent)

                Button(AppStrings.Performance.copyAntigravityPrompt) {
                    presenter.copyAntigravityPrompt(for: item)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 680, height: 560)
        .background(CompanionTheme.windowBackground)
    }

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func scopeIcon(for mode: CodeReviewScopeMode) -> String {
        switch mode {
        case .branchDiff: AppConstants.Icons.arrowClockwise
        case .moduleFolder: AppConstants.Icons.folder
        case .allProject: AppConstants.Icons.shieldCheck
        }
    }

    private func severityColor(_ severity: CodeReviewFinding.Severity) -> Color {
        switch severity {
        case .critical: CompanionTheme.coral
        case .warning: CompanionTheme.amber
        case .suggestion: CompanionTheme.mint
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
}

// MARK: - Searchable Branch Popover (Supports Repos with 100+ Branches)
private struct SearchableBranchPopover: View {
    let branches: [String]
    let currentBranch: String
    @Binding var selectedBranch: String
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var filterKind: GitBranchFilterKind = .all

    private var filteredBranches: [String] {
        CodeReviewEngine.filterBranches(
            branches,
            kind: filterKind,
            query: searchText,
            currentBranch: currentBranch
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: AppConstants.Icons.magnifyingGlass)
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionTheme.textMuted)
                TextField(AppStrings.CodeReview.searchBranchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(CompanionTheme.glassLow)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
            )

            HStack(spacing: 6) {
                ForEach(GitBranchFilterKind.allCases) { kind in
                    let active = filterKind == kind
                    Button(kind.rawValue) {
                        filterKind = kind
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: active ? .bold : .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(active ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                    .foregroundStyle(active ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                    .clipShape(Capsule())
                }
                Spacer()
                Text("\(filteredBranches.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CompanionTheme.textMuted)
            }

            RecycledVirtualList(
                items: filteredBranches.map { RecycledStringItem(value: $0) },
                rowSpacing: 4
            ) { entry in
                let branch = entry.value
                let isSelected = selectedBranch == branch
                let isCurrent = branch == currentBranch
                Button {
                    selectedBranch = branch
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Text(branch)
                            .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(CompanionTheme.textPrimary)
                            .lineLimit(1)
                        if isCurrent {
                            Text(AppStrings.CodeReview.currentBranchBadge)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(CompanionTheme.mint.opacity(0.22))
                                .foregroundStyle(CompanionTheme.mint)
                                .clipShape(Capsule())
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
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(height: 240)
        }
        .padding(12)
        .frame(width: 340)
    }
}

// MARK: - Searchable Module / Folder Popover
private struct SearchableModulePopover: View {
    let modules: [String]
    @Binding var selectedModule: String
    @Binding var isPresented: Bool
    @State private var searchText = ""

    private var filteredModules: [String] {
        CodeReviewEngine.filterModules(modules, query: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: AppConstants.Icons.magnifyingGlass)
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionTheme.textMuted)
                TextField(AppStrings.CodeReview.searchModulePlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Text("\(filteredModules.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CompanionTheme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(CompanionTheme.glassLow)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
            )

            RecycledVirtualList(
                items: filteredModules.map { RecycledStringItem(value: $0) },
                rowSpacing: 4
            ) { entry in
                let mod = entry.value
                let isSelected = selectedModule == mod
                let display = CodeReviewEngine.splitModuleDisplay(mod)
                Button {
                    selectedModule = mod
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: AppConstants.Icons.folder)
                            .font(.system(size: 12))
                            .foregroundStyle(CompanionTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display.leafName)
                                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                                .foregroundStyle(CompanionTheme.textPrimary)
                                .lineLimit(1)
                            if let parent = display.parentPath {
                                Text(parent)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
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
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(height: 270)
        }
        .padding(12)
        .frame(width: 400)
    }
}

import SwiftUI
import DevCompanionCore

struct UnitTestStudioView: View {
    @Bindable var presenter: UnitTestPresenter
    var onChooseProject: (() -> Void)?
    @State private var showTargetPopover = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppStrings.UnitTest.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        Text(AppStrings.UnitTest.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                    }
                    Spacer()
                    Picker(AppStrings.UnitTest.frameworkPicker, selection: $presenter.selectedFramework) {
                        ForEach(TestFrameworkKind.allCases) { fw in
                            Text(fw.rawValue).tag(fw)
                        }
                    }
                    .frame(width: 200)
                }

                if !presenter.hasProject, let onChooseProject {
                    GuidedRequirementBanner(
                        icon: AppConstants.Icons.folder,
                        message: AppStrings.Overview.needProjectBanner,
                        actionTitle: AppStrings.Common.selectXcodeProjectButton,
                        action: onChooseProject
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 12) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                FlowLayout(spacing: 8) {
                                    Text(AppStrings.UnitTest.sourceFileTitle(presenter.displaySourceFileName))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                        .preventSquish()

                                    if presenter.hasProject {
                                        Button {
                                            showTargetPopover.toggle()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: AppConstants.Icons.folder)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(CompanionTheme.accent)
                                                if presenter.selectedRelativeTarget.isEmpty {
                                                    Text("Select in Project…")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(CompanionTheme.textSecondary)
                                                } else {
                                                    let split = CodeReviewEngine.splitModuleDisplay(presenter.selectedRelativeTarget)
                                                    Text(split.leafName)
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundStyle(CompanionTheme.textPrimary)
                                                        .lineLimit(1)
                                                }
                                                Image(systemName: "chevron.down")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(CompanionTheme.textMuted)
                                            }
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(CompanionTheme.glassLow)
                                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .preventSquish()
                                        .popover(isPresented: $showTargetPopover, arrowEdge: .bottom) {
                                            UnitTestTargetSearchPopover(
                                                targets: presenter.availableProjectTargets,
                                                selectedTarget: presenter.selectedRelativeTarget,
                                                isPresented: $showTargetPopover
                                            ) { chosen in
                                                presenter.selectProjectRelativeTarget(chosen)
                                            }
                                        }
                                    }

                                    Button("Browse File / Folder…") {
                                        presenter.pickSwiftFile()
                                    }
                                    .buttonStyle(.bordered)
                                    .preventSquish()
                                }

                                TextField(AppStrings.UnitTest.moduleNamePlaceholder, text: $presenter.testModuleName)
                                    .textFieldStyle(.roundedBorder)

                                TextEditor(text: $presenter.testSourceCode)
                                    .font(.system(size: 11, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 160)

                                FlowLayout(spacing: 8) {
                                    Button(AppStrings.UnitTest.buildPlan) {
                                        presenter.buildPlacementPlan()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!presenter.canBuildPlan)
                                    .preventSquish()

                                    Button(AppStrings.Performance.copyAntigravityPrompt) {
                                        presenter.copyAntigravityTestPrompt()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!presenter.canBuildPlan)
                                    .preventSquish()

                                    Button(presenter.isResolvingDependencies ? AppStrings.Common.scanning : AppStrings.Enhancements.resolveDeps) {
                                        presenter.resolveCrossFileDependencies()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!presenter.hasProject || !presenter.canBuildPlan || presenter.isResolvingDependencies)
                                    .preventSquish()
                                }

                                if !presenter.resolvedDependencies.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(AppStrings.Enhancements.crossFileDeps) (\(presenter.resolvedDependencies.count))")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(CompanionTheme.accent)
                                        FlowLayout(spacing: 6) {
                                            ForEach(presenter.resolvedDependencies) { dep in
                                                HStack(spacing: 4) {
                                                    Text("H\(dep.hopDepth)")
                                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                        .foregroundStyle(CompanionTheme.mint)
                                                    Text(dep.typeName)
                                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                        .foregroundStyle(CompanionTheme.textPrimary)
                                                    if !dep.methods.isEmpty {
                                                        Text("(\(dep.methods.count) fn)")
                                                            .font(.system(size: 9))
                                                            .foregroundStyle(CompanionTheme.textMuted)
                                                    }
                                                }
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(RoundedRectangle(cornerRadius: 5).fill(CompanionTheme.glassLow))
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }

                        if let plan = presenter.placementPlan {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(AppStrings.UnitTest.reviewPlanTitle(plan.targetName))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textPrimary)

                                    RecycledVirtualList(items: plan.operations, rowSpacing: 6) { op in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(op.action.rawValue)
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(CompanionTheme.glassHigh)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    .preventSquish()
                                                Text(op.relativePath)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(CompanionTheme.textPrimary)
                                            }
                                            Text(op.summary)
                                                .font(.system(size: 10))
                                                .foregroundStyle(CompanionTheme.textSecondary)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(CompanionTheme.glassLow)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .frame(minHeight: 120, maxHeight: 220)

                                    FlowLayout(spacing: 8) {
                                        Button(AppStrings.UnitTest.approveAndWrite) {
                                            presenter.approveAndWritePlan()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(!presenter.hasProject)
                                        .preventSquish()

                                        Button(AppStrings.Common.copyCode) {
                                            presenter.copyGeneratedCode()
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(presenter.generatedTestCode.isEmpty)
                                        .preventSquish()
                                    }
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppStrings.UnitTest.previewTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CompanionTheme.textPrimary)

                            ScrollView {
                                if presenter.generatedTestCode.isEmpty {
                                    Text(AppStrings.UnitTest.previewEmpty)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    XcodeCodeText(code: presenter.generatedTestCode, fontSize: 11)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(minHeight: 330)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.UnitTest.runSectionTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)

                        FlowLayout(spacing: 8) {
                            TextField(AppStrings.UnitTest.projectPathPlaceholder, text: $presenter.xcodeProjectPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 240, maxWidth: 420)
                            Button(AppStrings.UnitTest.detectSchemes) {
                                Task { await presenter.discoverSchemes() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(presenter.xcodeProjectPath.isEmpty || presenter.isDiscoveringSchemes)
                            .preventSquish()

                            if !presenter.discoveredSchemes.isEmpty {
                                Picker(AppStrings.UnitTest.schemePlaceholder, selection: $presenter.schemeName) {
                                    ForEach(presenter.discoveredSchemes, id: \.self) { scheme in
                                        Text(scheme).tag(scheme)
                                    }
                                }
                                .frame(width: AppConstants.Layout.schemeFieldWidth)
                                .fixedSize(horizontal: true, vertical: false)
                            } else {
                                TextField(AppStrings.UnitTest.schemePlaceholder, text: $presenter.schemeName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: AppConstants.Layout.schemeFieldWidth)
                            }
                        }

                        FlowLayout(spacing: 8) {
                            TextField(AppStrings.UnitTest.destinationPlaceholder, text: $presenter.destination)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 240, maxWidth: 420)
                            Button(AppStrings.UnitTest.runXcodebuildTest) {
                                Task { await presenter.runXcodeTests() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(presenter.xcodeProjectPath.isEmpty || presenter.schemeName.isEmpty || presenter.isRunningTests)
                            .preventSquish()
                        }

                        if !presenter.testRunOutput.isEmpty {
                            ScrollView {
                                Text(presenter.testRunOutput)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 130)
                        }
                    }
                }

                coverageInspectorCard
            }
            .padding(20)
        }
    }

    private var coverageInspectorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 10) {
                    Text(AppStrings.Enhancements.coverageTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textPrimary)
                        .preventSquish()

                    Picker(AppStrings.Enhancements.coverageScope, selection: $presenter.coverageScope) {
                        ForEach(CoverageScopeKind.allCases) { scope in
                            Text(AppStrings.Enhancements.coverageScopeLabel(scope)).tag(scope)
                        }
                    }
                    .frame(width: 185)

                    Picker(AppStrings.Enhancements.coverageTarget, selection: $presenter.targetCoveragePercent) {
                        Text("70%").tag(70)
                        Text("80%").tag(80)
                        Text("90%").tag(90)
                        Text("95%").tag(95)
                    }
                    .frame(width: 115)

                    if presenter.coverageScope == .file {
                        Button(presenter.selectedCoverageFilePath.isEmpty ? AppStrings.Enhancements.chooseFile : URL(fileURLWithPath: presenter.selectedCoverageFilePath).lastPathComponent) {
                            presenter.pickCoverageFile()
                        }
                        .buttonStyle(.bordered)
                        .preventSquish()
                    } else if presenter.coverageScope == .directory {
                        Button(presenter.selectedCoverageDirectoryPath.isEmpty ? AppStrings.Enhancements.chooseDirectory : URL(fileURLWithPath: presenter.selectedCoverageDirectoryPath).lastPathComponent) {
                            presenter.pickCoverageDirectory()
                        }
                        .buttonStyle(.bordered)
                        .preventSquish()
                    }

                    Button(presenter.isCheckingCoverage ? AppStrings.Enhancements.checkingCoverage : AppStrings.Enhancements.checkCoverage) {
                        Task { await presenter.checkCoverage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!presenter.canCheckCoverage)
                    .preventSquish()
                }

                if let report = presenter.coverageReport {
                    HStack(spacing: 10) {
                        ProgressView(value: min(1.0, max(0.0, report.overallPercent / 100.0)))
                            .tint(report.overallPercent >= Double(presenter.targetCoveragePercent) ? CompanionTheme.mint : CompanionTheme.amber)
                        Text(String(format: "%.1f%% (%d/%d)", report.overallPercent, report.coveredLines, report.executableLines))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(report.overallPercent >= Double(presenter.targetCoveragePercent) ? CompanionTheme.mint : CompanionTheme.amber)
                            .preventSquish()
                    }

                    if !report.files.isEmpty {
                        RecycledVirtualList(items: report.files, rowSpacing: 5) { file in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.relativePath)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                        .lineLimit(1)
                                    if !file.uncoveredFunctions.isEmpty {
                                        Text("Uncovered: \(file.uncoveredFunctions.joined(separator: ", "))")
                                            .font(.system(size: 9))
                                            .foregroundStyle(CompanionTheme.textMuted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(String(format: "%.1f%%", file.lineCoveragePercent))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(file.lineCoveragePercent >= Double(presenter.targetCoveragePercent) ? CompanionTheme.mint : CompanionTheme.coral)
                                    .frame(width: 54, alignment: .trailing)

                                if file.lineCoveragePercent < Double(presenter.targetCoveragePercent) {
                                    Button(AppStrings.Enhancements.generateForUncovered) {
                                        presenter.loadUncoveredFileForTesting(file)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .frame(minHeight: 130, maxHeight: 240)
                    }
                } else {
                    Text(AppStrings.Enhancements.coverageEmpty)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.textSecondary)
                }
            }
        }
    }
}

private struct UnitTestTargetSearchPopover: View {
    let targets: [String]
    let selectedTarget: String
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void
    @State private var searchText = ""

    private var filteredTargets: [String] {
        CodeReviewEngine.filterModules(targets, query: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: AppConstants.Icons.magnifyingGlass)
                    .font(.system(size: 11))
                    .foregroundStyle(CompanionTheme.textMuted)
                TextField("Search file (.swift) or folder…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Text("\(filteredTargets.count)")
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
                items: filteredTargets.map { RecycledStringItem(value: $0) },
                rowSpacing: 4
            ) { entry in
                let target = entry.value
                let isSelected = selectedTarget == target
                let isSwiftFile = target.hasSuffix(".swift")
                let display = CodeReviewEngine.splitModuleDisplay(target)
                Button {
                    onSelect(target)
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSwiftFile ? "swift" : AppConstants.Icons.folder)
                            .font(.system(size: 12))
                            .foregroundStyle(isSwiftFile ? CompanionTheme.mint : CompanionTheme.accent)
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
        .frame(width: 410)
    }
}

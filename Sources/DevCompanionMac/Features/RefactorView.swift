import SwiftUI
import DevCompanionCore

struct RefactorView: View {
    @Bindable var presenter: RefactorPresenter
    var onChooseProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerCard
            if !presenter.hasProjectURL {
                emptyProjectCard
            } else {
                filterBar
                HStack(alignment: .top, spacing: 14) {
                    opportunityListPane
                        .frame(width: 340)
                    detailPane
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.Refactor.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textPrimary)
                    Text(AppStrings.Refactor.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.textSecondary)
                }

                Spacer()

                if presenter.localFixCount > 0 {
                    Text("\(presenter.localFixCount) \(AppStrings.Refactor.zeroTokenLocal)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(CompanionTheme.mint.opacity(0.18))
                        .foregroundStyle(CompanionTheme.mint)
                        .clipShape(Capsule())
                }

                TextField(AppStrings.Refactor.moduleFilterPlaceholder, text: $presenter.moduleFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: 150)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))

                Button {
                    presenter.scanProject()
                } label: {
                    HStack(spacing: 6) {
                        if presenter.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: AppConstants.Icons.refactor)
                        }
                        Text(presenter.isScanning ? AppStrings.Common.scanning : AppStrings.Refactor.scanButton)
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!presenter.hasProjectURL || presenter.isScanning)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(title: "\(AppStrings.Performance.priorityAll) (\(presenter.opportunities.count))", isSelected: presenter.selectedRule == nil) {
                    presenter.selectedRule = nil
                }
                ForEach(RefactorRuleKind.allCases) { rule in
                    let count = presenter.count(for: rule)
                    filterChip(title: "\(rule.rawValue) (\(count))", isSelected: presenter.selectedRule == rule) {
                        presenter.selectedRule = rule
                    }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : CompanionTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? CompanionTheme.accent.opacity(0.85) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    private var opportunityListPane: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: AppConstants.Icons.magnifyingGlass)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.textSecondary)
                    TextField(AppStrings.Refactor.searchPlaceholder, text: $presenter.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))

                if presenter.filteredOpportunities.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: AppConstants.Icons.refactor)
                            .font(.system(size: 24))
                            .foregroundStyle(CompanionTheme.textSecondary.opacity(0.6))
                        Text(presenter.hasScanned ? AppStrings.Refactor.noOpportunities : AppStrings.Refactor.readyPrompt)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(presenter.filteredOpportunities) { item in
                                opportunityRow(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func opportunityRow(_ item: RefactorOpportunity) -> some View {
        let isSelected = presenter.selectedOpportunity?.id == item.id
        return Button {
            presenter.selectedOpportunityID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.severity.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((item.severity == .high ? CompanionTheme.coral : CompanionTheme.amber).opacity(0.22))
                        .foregroundStyle(item.severity == .high ? CompanionTheme.coral : CompanionTheme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text("\(item.fileName):\(item.startLine)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CompanionTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if item.hasLocalFix {
                        Text("0T")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(CompanionTheme.mint.opacity(0.2))
                            .foregroundStyle(CompanionTheme.mint)
                            .clipShape(Capsule())
                    }
                }

                Text("\(item.rule.rawValue) • \(item.symbolName)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CompanionTheme.accent)
                    .lineLimit(1)

                Text(item.metricSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? CompanionTheme.accent.opacity(0.18) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? CompanionTheme.accent.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var detailPane: some View {
        GlassCard {
            if let opp = presenter.selectedOpportunity,
               let bundle = presenter.activeCompactPromptAndBudget {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(opp.fileName):\(opp.startLine)–\(opp.endLine)")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Text("\(opp.rule.rawValue) • \(opp.metricSummary)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                            }
                            Spacer()
                            Button(AppStrings.Performance.openInXcode) {
                                Task { await presenter.openInXcode() }
                            }
                            .buttonStyle(.bordered)
                        }

                        if opp.hasLocalFix, let title = opp.localFixTitle, let old = opp.localOldSnippet, let new = opp.localNewSnippet {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.mint)
                                    Spacer()
                                    if presenter.lastRevertRecord != nil {
                                        Button(AppStrings.Performance.undoPatch) {
                                            presenter.revertLastLocalFix()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    Button(AppStrings.Refactor.applyLocalFix) {
                                        presenter.applyLocalFix()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                CodeSurfaceContainer(padding: 10) {
                                    Text("- \(old)\n+ \(new)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineSpacing(3)
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(CompanionTheme.mint.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CompanionTheme.mint.opacity(0.25), lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(AppStrings.Refactor.compactPromptTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)

                                Text("~\(bundle.budget.compactTokens) tokens (vs ~\(bundle.budget.verboseTokens) full-file • Save \(bundle.budget.savedPercent)%)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(CompanionTheme.accent.opacity(0.18))
                                    .foregroundStyle(CompanionTheme.accent)
                                    .clipShape(Capsule())

                                Spacer()

                                Button(AppStrings.Refactor.copyCompactPrompt) {
                                    presenter.copyCompactPrompt()
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            TextField(AppStrings.Refactor.customGoalPlaceholder, text: $presenter.customGoal)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))

                            CodeSurfaceContainer(padding: 10) {
                                Text(bundle.prompt)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineSpacing(3)
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(4)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: AppConstants.Icons.refactor)
                        .font(.system(size: 28))
                        .foregroundStyle(CompanionTheme.textSecondary.opacity(0.5))
                    Text(AppStrings.Refactor.selectPrompt)
                        .font(.system(size: 12))
                        .foregroundStyle(CompanionTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyProjectCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: AppConstants.Icons.folder)
                    .font(.system(size: 32))
                    .foregroundStyle(CompanionTheme.accent)
                Text(AppStrings.Common.selectProjectFirst)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CompanionTheme.textPrimary)
                Button(AppStrings.Common.selectXcodeProjectButton, action: onChooseProject)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

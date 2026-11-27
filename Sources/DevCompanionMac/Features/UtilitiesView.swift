import SwiftUI
import DevCompanionCore

struct UtilitiesView: View {
    @Bindable var presenter: UtilitiesPresenter
    var onChooseProject: (() -> Void)?
    @State private var showCleanConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppStrings.Utilities.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CompanionTheme.textPrimary)

                if !presenter.hasProject, let onChooseProject {
                    GuidedRequirementBanner(
                        icon: AppConstants.Icons.folder,
                        message: AppStrings.Overview.needProjectBanner,
                        actionTitle: AppStrings.Common.selectXcodeProjectButton,
                        action: onChooseProject
                    )
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppStrings.Utilities.colorTokenTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)

                        FlowLayout(spacing: 10) {
                            TextField(AppStrings.Utilities.tokenNamePlaceholder, text: $presenter.tokenName)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 160, maxWidth: 320)
                            TextField(AppStrings.Utilities.tokenHexPlaceholder, text: $presenter.tokenHex)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: AppConstants.Layout.hexFieldWidth)
                            Button(AppStrings.Utilities.generate) {
                                presenter.generateColorToken()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!presenter.canGenerateColorToken)
                            .preventSquish()
                            Button(AppStrings.Common.copy) {
                                presenter.copyGeneratedTokenCode()
                            }
                            .buttonStyle(.bordered)
                            .disabled(presenter.generatedTokenCode.isEmpty)
                            .preventSquish()
                        }

                        if !presenter.generatedTokenCode.isEmpty {
                            XcodeCodeText(code: presenter.generatedTokenCode, fontSize: 11)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            FlowLayout(spacing: 8) {
                                Text(AppStrings.Utilities.l10nTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                    .preventSquish()
                                if !presenter.missingLocalizations.isEmpty {
                                    Button(AppStrings.Performance.copyAntigravityPrompt) {
                                        presenter.copyAntigravityL10nPrompt()
                                    }
                                    .buttonStyle(.bordered)
                                    .preventSquish()
                                }
                                Button(AppStrings.Common.scanProject) {
                                    presenter.scanLocalizations()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!presenter.hasProject || presenter.isScanningL10n)
                                .preventSquish()
                            }

                            if presenter.missingLocalizations.isEmpty {
                                Text(AppStrings.Utilities.l10nEmptyPrompt)
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                            } else {
                                RecycledVirtualList(items: presenter.missingLocalizations, rowSpacing: 4) { item in
                                    HStack {
                                        Text(item.key)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(CompanionTheme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(AppStrings.Utilities.missingLanguages(item.missingLanguages.joined(separator: ", ")))
                                            .font(.system(size: 10))
                                            .foregroundStyle(CompanionTheme.amber)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 3)
                                }
                                .frame(minHeight: 160, maxHeight: 360)
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(AppStrings.Utilities.derivedDataTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CompanionTheme.textPrimary)

                            if let summary = presenter.derivedDataSummary {
                                Text(summary.formattedSize)
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: summary.formattedSize)
                                Text(AppStrings.Utilities.derivedDataCount(summary.projectCount))
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                            }

                            FlowLayout(spacing: 8) {
                                Button(AppStrings.Utilities.refreshSize) {
                                    presenter.refreshDerivedData()
                                }
                                .buttonStyle(.bordered)
                                .preventSquish()

                                Button(AppStrings.Utilities.cleanDerivedData) {
                                    showCleanConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .disabled(presenter.isRefreshingDerivedData || !presenter.canCleanDerivedData)
                                .preventSquish()

                                Button(AppStrings.Enhancements.pruneSims) {
                                    presenter.cleanUnavailableSimulators()
                                }
                                .buttonStyle(.bordered)
                                .preventSquish()
                                .help("Remove unavailable Xcode simulator devices")
                            }
                        }
                    }
                    .frame(minWidth: 220, idealWidth: AppConstants.Layout.derivedDataCardWidth, maxWidth: 300)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppStrings.Enhancements.buildSigning)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Text("Inspect recent DerivedData .xcactivitylog target timings & local .mobileprovision expiry")
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                            }
                            Spacer()
                            Button(presenter.isScanningBuildAndSigning ? AppStrings.Common.scanning : AppStrings.Enhancements.inspectBuilds) {
                                presenter.scanBuildAndSigning()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(presenter.isScanningBuildAndSigning)
                        }

                        if !presenter.buildTimings.isEmpty || !presenter.provisioningProfiles.isEmpty {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Slowest Build Targets (\(presenter.buildTimings.count))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textSecondary)
                                    if presenter.buildTimings.isEmpty {
                                        Text("No recent .xcactivitylog build timings found.")
                                            .font(.system(size: 11))
                                            .foregroundStyle(CompanionTheme.textMuted)
                                    } else {
                                        ForEach(presenter.buildTimings.prefix(8)) { target in
                                            HStack {
                                                Text(target.targetName)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(CompanionTheme.textPrimary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(target.formattedDuration)
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(target.durationSeconds >= 5 ? CompanionTheme.amber : CompanionTheme.mint)
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Provisioning Profiles (\(presenter.provisioningProfiles.count))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CompanionTheme.textSecondary)
                                    if presenter.provisioningProfiles.isEmpty {
                                        Text("No local .mobileprovision files found.")
                                            .font(.system(size: 11))
                                            .foregroundStyle(CompanionTheme.textMuted)
                                    } else {
                                        ForEach(presenter.provisioningProfiles.prefix(8)) { profile in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(profile.name)
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundStyle(CompanionTheme.textPrimary)
                                                        .lineLimit(1)
                                                    Text("\(profile.teamName) • \(profile.entitlementsCount) entitlements")
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(CompanionTheme.textMuted)
                                                }
                                                Spacer()
                                                Text(profile.isExpired ? "EXPIRED" : "\(profile.daysRemaining)d")
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(profile.isExpired ? CompanionTheme.coral : (profile.daysRemaining <= 14 ? CompanionTheme.amber : CompanionTheme.mint))
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppStrings.Enhancements.unusedAssets)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Text("Detect .imageset resources not referenced in Swift/Storyboard/XIB files")
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                            }
                            Spacer()
                            Button(presenter.isScanningUnusedAssets ? AppStrings.Common.scanning : AppStrings.Enhancements.auditAssets) {
                                presenter.scanUnusedAssets()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!presenter.hasProject || presenter.isScanningUnusedAssets)
                        }

                        if !presenter.unusedAssets.isEmpty {
                            RecycledVirtualList(items: presenter.unusedAssets, rowSpacing: 4) { asset in
                                HStack {
                                    Text(asset.name)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.amber)
                                    Spacer()
                                    Text(asset.relativePath)
                                        .font(.system(size: 10))
                                        .foregroundStyle(CompanionTheme.textMuted)
                                        .lineLimit(1)
                                }
                            }
                            .frame(minHeight: 100, maxHeight: 200)
                        }
                    }
                }
            }
            .padding(20)
        }
        .alert(AppStrings.Utilities.cleanDerivedData, isPresented: $showCleanConfirmation) {
            Button(AppStrings.Utilities.cleanDerivedData, role: .destructive) {
                presenter.cleanDerivedData()
            }
            Button(AppStrings.Common.clearProject, role: .cancel) {}
        }
        .onAppear {
            presenter.onAppear()
        }
    }
}

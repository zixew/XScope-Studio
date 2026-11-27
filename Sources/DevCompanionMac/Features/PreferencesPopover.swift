import SwiftUI
import DevCompanionCore

struct PreferencesPopover: View {
    @Binding var preferences: AppPreferences
    let onSave: (AppPreferences) -> Void

    private var currentIntervalTitle: String {
        switch preferences.telemetryIntervalSeconds {
        case ..<1.2:
            return AppStrings.Enhancements.intervalFast
        case 1.2..<2.5:
            return AppStrings.Enhancements.intervalBalanced
        default:
            return AppStrings.Enhancements.intervalLowPower
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CompanionTheme.accent)
                    Text(AppStrings.Enhancements.preferences)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CompanionTheme.textPrimary)
                    Spacer()
                }

                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                // Section 1: Telemetry Polling Interval
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(AppStrings.Enhancements.telemetryInterval)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Spacer()
                        Text(currentIntervalTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanionTheme.textPrimary)
                    }

                    HStack(spacing: 8) {
                        optionCard(
                            title: AppStrings.Enhancements.intervalFast,
                            icon: "bolt.fill",
                            isSelected: preferences.telemetryIntervalSeconds <= 1.0
                        ) {
                            preferences.telemetryIntervalSeconds = 1.0
                        }

                        optionCard(
                            title: AppStrings.Enhancements.intervalBalanced,
                            icon: "gauge.with.needle.fill",
                            isSelected: abs(preferences.telemetryIntervalSeconds - 1.5) < 0.1
                        ) {
                            preferences.telemetryIntervalSeconds = 1.5
                        }

                        optionCard(
                            title: AppStrings.Enhancements.intervalLowPower,
                            icon: "leaf.fill",
                            isSelected: preferences.telemetryIntervalSeconds >= 3.0
                        ) {
                            preferences.telemetryIntervalSeconds = 3.0
                        }
                    }
                }

                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                // Section 2: Simulator Log Ring Buffer
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(AppStrings.Enhancements.logBuffer)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Spacer()
                        Text("\(preferences.logBufferCapacity) lines")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(CompanionTheme.textPrimary)
                    }

                    HStack(spacing: 8) {
                        optionCard(
                            title: "250",
                            icon: "doc.text",
                            isSelected: preferences.logBufferCapacity == 250
                        ) {
                            preferences.logBufferCapacity = 250
                        }

                        optionCard(
                            title: "500",
                            icon: "doc.text.fill",
                            isSelected: preferences.logBufferCapacity == 500
                        ) {
                            preferences.logBufferCapacity = 500
                        }

                        optionCard(
                            title: "1000",
                            icon: "tray.full.fill",
                            isSelected: preferences.logBufferCapacity == 1000
                        ) {
                            preferences.logBufferCapacity = 1000
                        }
                    }
                }

                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                // Section 3: Language Override
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(AppStrings.Enhancements.language)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Spacer()
                        Text(preferences.languageOverride.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanionTheme.textPrimary)
                    }

                    HStack(spacing: 8) {
                        ForEach(AppLanguageOverride.allCases) { lang in
                            optionCard(
                                title: lang.displayName,
                                icon: lang == .system ? "globe" : "character.bubble",
                                isSelected: preferences.languageOverride == lang
                            ) {
                                preferences.languageOverride = lang
                            }
                        }
                    }
                }

                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                // Section 4: Background Notifications
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Enhancements.bgNotifications)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    notificationCardRow(
                        title: AppStrings.Enhancements.notifyCrash,
                        icon: "flame.fill",
                        tintColor: CompanionTheme.coral,
                        isOn: $preferences.notifyOnCrash
                    )

                    notificationCardRow(
                        title: AppStrings.Enhancements.notifyHang,
                        icon: "hourglass",
                        tintColor: CompanionTheme.amber,
                        isOn: $preferences.notifyOnHang
                    )

                    notificationCardRow(
                        title: AppStrings.Enhancements.notifyTask,
                        icon: "checkmark.circle.fill",
                        tintColor: CompanionTheme.mint,
                        isOn: $preferences.notifyOnTaskComplete
                    )
                }
            }
            .padding(16)
        }
        .frame(width: 380, height: 460)
        .onChange(of: preferences) { _, newValue in
            onSave(newValue)
        }
    }

    private func optionCard(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? CompanionTheme.accent : CompanionTheme.textSecondary)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(CompanionTheme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? CompanionTheme.accentTint : CompanionTheme.glassLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                isSelected ? CompanionTheme.accent.opacity(0.7) : CompanionTheme.hairlineBorder,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func notificationCardRow(
        title: String,
        icon: String,
        tintColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(tintColor)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanionTheme.textPrimary)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isOn.wrappedValue ? CompanionTheme.accent : CompanionTheme.textMuted)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn.wrappedValue ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(CompanionTheme.hairlineBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

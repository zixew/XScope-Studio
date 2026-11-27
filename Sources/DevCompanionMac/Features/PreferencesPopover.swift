import SwiftUI
import DevCompanionCore

struct PreferencesPopover: View {
    @Binding var preferences: AppPreferences
    let onSave: (AppPreferences) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.Enhancements.preferences)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CompanionTheme.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.Enhancements.telemetryInterval)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textSecondary)
                Picker("", selection: $preferences.telemetryIntervalSeconds) {
                    Text(AppStrings.Enhancements.intervalFast).tag(1.0)
                    Text(AppStrings.Enhancements.intervalBalanced).tag(1.5)
                    Text(AppStrings.Enhancements.intervalLowPower).tag(3.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.Enhancements.logBuffer)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textSecondary)
                Picker("", selection: $preferences.logBufferCapacity) {
                    Text("250").tag(250)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.Enhancements.language)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textSecondary)
                Picker("", selection: $preferences.languageOverride) {
                    ForEach(AppLanguageOverride.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.Enhancements.bgNotifications)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textSecondary)
                Toggle(AppStrings.Enhancements.notifyCrash, isOn: $preferences.notifyOnCrash)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Toggle(AppStrings.Enhancements.notifyHang, isOn: $preferences.notifyOnHang)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Toggle(AppStrings.Enhancements.notifyTask, isOn: $preferences.notifyOnTaskComplete)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }
        }
        .padding(16)
        .frame(width: 370)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: preferences) { _, newValue in
            onSave(newValue)
        }
    }
}

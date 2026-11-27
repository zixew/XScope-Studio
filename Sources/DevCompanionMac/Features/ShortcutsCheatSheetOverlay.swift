import SwiftUI

struct ShortcutsCheatSheetOverlay: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shortcuts: [(keys: String, label: String)] {
        [
            ("⌘K", AppStrings.Enhancements.scPalette),
            ("⌘1 – ⌘7", AppStrings.Enhancements.scModules),
            ("⌘R", AppStrings.Enhancements.scScan),
            ("⌘W", AppStrings.Enhancements.scHide),
            ("⌘/", AppStrings.Enhancements.scShortcuts),
            ("⌘Q", AppStrings.Enhancements.scQuit)
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CompanionTheme.accent)
                    Text(AppStrings.Enhancements.keyboardShortcuts)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CompanionTheme.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(CompanionTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                VStack(spacing: 8) {
                    ForEach(shortcuts, id: \.keys) { item in
                        HStack {
                            Text(item.label)
                                .font(.system(size: 12))
                                .foregroundStyle(CompanionTheme.textPrimary)
                            Spacer()
                            Text(item.keys)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CompanionTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(CompanionTheme.glassLow))
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: 400)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CompanionTheme.glassMid.opacity(0.65)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func dismiss() {
        withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
            isPresented = false
        }
    }
}

import SwiftUI
import DevCompanionCore

struct CommandPaletteOverlay: View {
    @Binding var isPresented: Bool
    let items: [CommandPaletteItem]
    let onSelect: (CommandPaletteItem) -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filteredItems: [CommandPaletteItem] {
        CommandPaletteMatcher.filter(items: items, query: query)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CompanionTheme.accent)

                    TextField("Jump to module, action, or device…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(CompanionTheme.textPrimary)
                        .focused($isSearchFocused)
                        .onSubmit { executeSelected() }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(CompanionTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("ESC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CompanionTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(CompanionTheme.glassLow))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                if filteredItems.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18))
                            .foregroundStyle(CompanionTheme.textMuted)
                        Text("No matching commands")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CompanionTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                    paletteRow(item: item, isSelected: index == selectedIndex)
                                        .id(item.id)
                                        .onTapGesture {
                                            onSelect(item)
                                            dismiss()
                                        }
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedIndex) { _, newValue in
                            if filteredItems.indices.contains(newValue) {
                                withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
                                    proxy.scrollTo(filteredItems[newValue].id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CompanionTheme.glassMid.opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(CompanionTheme.hairlineBorder, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
            .padding(.top, 70)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            selectedIndex = 0
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if !filteredItems.isEmpty {
                selectedIndex = (selectedIndex - 1 + filteredItems.count) % filteredItems.count
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !filteredItems.isEmpty {
                selectedIndex = (selectedIndex + 1) % filteredItems.count
            }
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func paletteRow(item: CommandPaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? CompanionTheme.accent : CompanionTheme.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? CompanionTheme.accent.opacity(0.16) : CompanionTheme.glassLow)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textPrimary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(CompanionTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.category.rawValue)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CompanionTheme.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(CompanionTheme.glassLow))

            if let hint = item.shortcutHint {
                Text(hint)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CompanionTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(CompanionTheme.glassLow))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? CompanionTheme.accent.opacity(0.14) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? CompanionTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }

    private func executeSelected() {
        guard filteredItems.indices.contains(selectedIndex) else { return }
        onSelect(filteredItems[selectedIndex])
        dismiss()
    }

    private func dismiss() {
        withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
            isPresented = false
        }
    }
}

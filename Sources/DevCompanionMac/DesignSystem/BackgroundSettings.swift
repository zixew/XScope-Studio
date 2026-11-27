import SwiftUI
import AppKit
import ImageIO
import DevCompanionCore

enum BackgroundPreset: String, CaseIterable, Identifiable {
    case solid = "Solid Theme"
    case custom = "Custom Image"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: AppStrings.Background.presetSolid
        case .custom: AppStrings.Background.presetCustom
        }
    }
}

@MainActor
@Observable
final class BackgroundSettings {
    var theme: AppThemePreset {
        didSet { preferencesStore.set(theme.rawValue, forKey: AppConstants.StorageKeys.themePreset) }
    }
    var preset: BackgroundPreset {
        didSet {
            preferencesStore.set(preset.rawValue, forKey: AppConstants.StorageKeys.backgroundPreset)
            reloadCachedImage()
        }
    }
    var customImagePath: String {
        didSet {
            preferencesStore.set(customImagePath, forKey: AppConstants.StorageKeys.customBackgroundPath)
            reloadCachedImage()
        }
    }
    var dimOpacity: Double {
        didSet { preferencesStore.set(dimOpacity, forKey: AppConstants.StorageKeys.backgroundDimOpacity) }
    }
    var blurRadius: Double {
        didSet { preferencesStore.set(blurRadius, forKey: AppConstants.StorageKeys.backgroundBlurRadius) }
    }
    private(set) var cachedImage: NSImage?

    private let preferencesStore: any PreferencesStoring

    init(preferencesStore: any PreferencesStoring = UserDefaultsStore()) {
        self.preferencesStore = preferencesStore
        let savedTheme = preferencesStore.string(forKey: AppConstants.StorageKeys.themePreset) ?? AppThemePreset.dark.rawValue
        self.theme = AppThemePreset(rawValue: savedTheme) ?? .dark

        let savedPreset = preferencesStore.string(forKey: AppConstants.StorageKeys.backgroundPreset) ?? BackgroundPreset.solid.rawValue
        self.preset = BackgroundPreset(rawValue: savedPreset) ?? .solid
        self.customImagePath = preferencesStore.string(forKey: AppConstants.StorageKeys.customBackgroundPath) ?? ""
        self.dimOpacity = preferencesStore.double(forKey: AppConstants.StorageKeys.backgroundDimOpacity) ?? AppConstants.Defaults.defaultScrimOpacity
        self.blurRadius = preferencesStore.double(forKey: AppConstants.StorageKeys.backgroundBlurRadius) ?? AppConstants.Defaults.defaultBlurRadius
        reloadCachedImage()
    }

    var resolvedNSImage: NSImage? {
        cachedImage
    }

    private func reloadCachedImage() {
        switch preset {
        case .solid:
            cachedImage = nil
        case .custom:
            let path = customImagePath
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
                cachedImage = nil
                return
            }
            Task {
                let cgImage = await Task.detached(priority: .userInitiated) {
                    Self.loadDownsampledCGImage(atPath: path, maxPixelSize: 1920)
                }.value
                if self.customImagePath == path && self.preset == .custom {
                    if let cgImage {
                        self.cachedImage = NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height)
                        )
                    } else {
                        self.cachedImage = NSImage(contentsOfFile: path)
                    }
                }
            }
        }
    }

    nonisolated private static func loadDownsampledCGImage(atPath path: String, maxPixelSize: CGFloat) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    var scrimColor: Color {
        switch theme {
        case .dark:
            Color.black.opacity(dimOpacity)
        case .midnight:
            Color(red: 0.02, green: 0.02, blue: 0.03).opacity(min(0.95, dimOpacity + 0.12))
        case .light:
            Color(red: 0.96, green: 0.96, blue: 0.97).opacity(dimOpacity)
        }
    }

    var baseSolidColor: Color {
        switch theme {
        case .dark: Color(red: 0.067, green: 0.071, blue: 0.094)
        case .midnight: Color(red: 0.025, green: 0.025, blue: 0.035)
        case .light: Color(red: 0.949, green: 0.953, blue: 0.965)
        }
    }

    func pickCustomImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use Background"
        if panel.runModal() == .OK, let url = panel.url {
            customImagePath = url.path
            preset = .custom
        }
    }
}

struct CustomBackgroundLayer: View {
    let settings: BackgroundSettings

    var body: some View {
        ZStack {
            settings.baseSolidColor

            if let nsImage = settings.resolvedNSImage {
                GeometryReader { geo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: settings.blurRadius)
                        .clipped()
                        .drawingGroup()
                }
                settings.scrimColor
            }
        }
        .ignoresSafeArea()
    }
}

struct BackgroundSettingsPopover: View {
    @Bindable var settings: BackgroundSettings
    @Bindable private var appearance = ThemeAppearanceModel.shared
    private let accentPresets = ["#10B981", "#F59E0B", "#38BDF8", "#EC4899"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section 1: Theme Preset Swatches
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(AppStrings.Background.themeTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Spacer()
                        Text(settings.theme.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanionTheme.textPrimary)
                    }

                    HStack(spacing: 8) {
                        ForEach(AppThemePreset.allCases) { item in
                            themeSwatchCard(for: item)
                        }
                    }
                }

                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                // Section 2: Workspace Background & Blur
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Background.workspaceBgTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    HStack(spacing: 8) {
                        ForEach(BackgroundPreset.allCases) { item in
                            let isSelected = settings.preset == item
                            Button {
                                if item == .custom && settings.customImagePath.isEmpty {
                                    settings.pickCustomImage()
                                } else {
                                    settings.preset = item
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: item == .solid ? "square.fill" : "photo")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(isSelected ? CompanionTheme.accent : CompanionTheme.textSecondary)
                                    Text(item.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 10)
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
                    }

                    if settings.preset == .custom {
                        HStack(spacing: 8) {
                            if let thumb = settings.resolvedNSImage {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 26, height: 26)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(CompanionTheme.hairlineBorder, lineWidth: 1)
                                    )
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                    .frame(width: 26, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(CompanionTheme.glassLow))
                            }

                            Text(customImageDisplayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CompanionTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button(AppStrings.Background.chooseCustomImage) {
                                settings.pickCustomImage()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(CompanionTheme.glassMid)
                                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                            )
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(CompanionTheme.glassLow))
                    }
                }

                // Image Scrim & Blur
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(AppStrings.Background.scrimOpacity)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CompanionTheme.textSecondary)
                            Spacer()
                            Text("\(Int(settings.dimOpacity * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(CompanionTheme.textPrimary)
                        }
                        Slider(value: $settings.dimOpacity, in: 0.0...0.85)
                            .controlSize(.small)
                            .disabled(settings.preset == .solid)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(AppStrings.Background.blur)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CompanionTheme.textSecondary)
                            Spacer()
                            Text("\(Int(settings.blurRadius))px")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(CompanionTheme.textPrimary)
                        }
                        Slider(value: $settings.blurRadius, in: 0...40)
                            .controlSize(.small)
                            .disabled(settings.preset == .solid)
                    }
                }
                .opacity(settings.preset == .custom ? 1.0 : 0.45)

                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                // Section 3: Accent Color, Corner Radius & Surface Opacity (VoltGuard-style)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Accent Color")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textSecondary)
                        Spacer()
                        ForEach(accentPresets, id: \.self) { hex in
                            let isSelected = appearance.accentHex.caseInsensitiveCompare(hex) == .orderedSame
                            Button {
                                appearance.accentHex = hex
                            } label: {
                                Circle()
                                    .fill(swatchColor(for: hex))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("#38BDF8", text: $appearance.accentHex)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 82)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Corner Radius")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CompanionTheme.textSecondary)
                            Spacer()
                            Text("\(Int(appearance.cornerRadius))px")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(CompanionTheme.textPrimary)
                        }
                        Slider(value: $appearance.cornerRadius, in: 4...20, step: 1)
                            .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Surface Opacity")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CompanionTheme.textSecondary)
                            Spacer()
                            Text("\(Int(appearance.surfaceOpacity * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(CompanionTheme.textPrimary)
                        }
                        Slider(value: $appearance.surfaceOpacity, in: 0.02...0.35)
                            .controlSize(.small)
                    }
                }

                Rectangle().fill(CompanionTheme.hairlineBorder).frame(height: 1)

                // Section 4: Bar & Layout
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bar & Layout")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textSecondary)

                    HStack {
                        Text("Menu Bar Icon")
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                        Spacer()
                        Picker("", selection: $appearance.menuBarConfig.iconStyle) {
                            ForEach(MenuBarIconStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    Toggle("Show Target Badge", isOn: $appearance.menuBarConfig.showTargetBadge)
                        .font(.system(size: 11))
                    Toggle("Show Live CPU & Memory", isOn: $appearance.menuBarConfig.showLiveMetrics)
                        .font(.system(size: 11))

                    HStack {
                        Text("Popover Density")
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                        Spacer()
                        Picker("", selection: $appearance.menuBarConfig.density) {
                            ForEach(MenuBarPopoverDensity.allCases) { d in
                                Text(d.displayName).tag(d)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }

                    VStack(spacing: 6) {
                        ForEach(Array(appearance.menuBarConfig.sections.enumerated()), id: \.element.id) { idx, section in
                            HStack(spacing: 8) {
                                Toggle(section.kind.displayName, isOn: $appearance.menuBarConfig.sections[idx].isEnabled)
                                    .font(.system(size: 11))
                                Spacer()
                                Button {
                                    appearance.menuBarConfig.moveSection(at: idx, offset: -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .disabled(idx == 0)

                                Button {
                                    appearance.menuBarConfig.moveSection(at: idx, offset: 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .disabled(idx == appearance.menuBarConfig.sections.count - 1)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .frame(width: 390, height: 500)
    }

    private func swatchColor(for hex: String) -> Color {
        switch hex.uppercased() {
        case "#10B981": Color(red: 0.063, green: 0.725, blue: 0.506)
        case "#F59E0B": Color(red: 0.961, green: 0.620, blue: 0.043)
        case "#EC4899": Color(red: 0.925, green: 0.282, blue: 0.600)
        default: Color(red: 0.220, green: 0.741, blue: 0.973)
        }
    }

    private var customImageDisplayName: String {
        guard !settings.customImagePath.isEmpty else { return "No image selected" }
        return URL(fileURLWithPath: settings.customImagePath).lastPathComponent
    }

    @ViewBuilder
    private func themeSwatchCard(for item: AppThemePreset) -> some View {
        let isSelected = settings.theme == item
        let bgColor: Color = switch item {
        case .dark: Color(red: 0.067, green: 0.071, blue: 0.094)
        case .midnight: Color(red: 0.025, green: 0.025, blue: 0.035)
        case .light: Color(red: 0.949, green: 0.953, blue: 0.965)
        }
        let railColor: Color = item.isLight
            ? Color.black.opacity(0.06)
            : Color.white.opacity(0.06)
        let lineColor: Color = item.isLight
            ? Color.black.opacity(0.18)
            : Color.white.opacity(0.22)
        let shortLabel: String = switch item {
        case .dark: "Dark"
        case .light: "Light"
        case .midnight: "Midnight"
        }

        Button {
            settings.theme = item
        } label: {
            VStack(spacing: 6) {
                // Mini workspace preview swatch
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(bgColor)

                    HStack(spacing: 0) {
                        // Mini left rail
                        Rectangle()
                            .fill(railColor)
                            .frame(width: 20)
                            .overlay(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(CompanionTheme.accent)
                                        .frame(width: 12, height: 3)
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(lineColor)
                                        .frame(width: 10, height: 2.5)
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(lineColor)
                                        .frame(width: 12, height: 2.5)
                                }
                                .padding(4)
                            }

                        // Mini main pane
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                Circle().fill(lineColor).frame(width: 3, height: 3)
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(lineColor)
                                    .frame(width: 24, height: 2.5)
                                Spacer()
                            }
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(railColor)
                                .frame(height: 16)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(CompanionTheme.accent.opacity(0.85))
                                        .frame(width: 16, height: 2.5)
                                        .padding(.leading, 4)
                                }
                        }
                        .padding(5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isSelected ? CompanionTheme.accent : CompanionTheme.hairlineBorder,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )

                HStack(spacing: 4) {
                    Text(shortLabel)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(CompanionTheme.accent)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? CompanionTheme.accentTint : CompanionTheme.glassLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSelected ? CompanionTheme.accent.opacity(0.45) : CompanionTheme.hairlineBorder,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Callout banner explaining why actions are disabled when a required connection (Xcode project or booted Simulator) is missing.
struct GuidedRequirementBanner: View {
    let icon: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CompanionTheme.amber)
                .frame(width: 26, height: 26)
                .background(Circle().fill(CompanionTheme.amber.opacity(0.16)))

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanionTheme.textPrimary)

            Spacer()

            Button(actionTitle) {
                action()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CompanionTheme.amber.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CompanionTheme.amber.opacity(0.42), lineWidth: 1)
                )
        )
    }
}


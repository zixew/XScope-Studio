import AppKit
import CoreGraphics
import DevCompanionCore

/// macOS pasteboard implementation of `ClipboardManaging`.
struct MacOSClipboard: ClipboardManaging {
    func copyString(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyImage(at url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([image])
    }
}

/// Centralized non-textual constants (layout metrics, storage keys, icons, telemetry, paths).
enum AppConstants {
    enum Layout {
        static let minWindowWidth: CGFloat = 920
        static let minWindowHeight: CGFloat = 620
        static let topBarHeight: CGFloat = 48
        static let leftRailWidth: CGFloat = 200
        static let menuBarWidth: CGFloat = 300
        static let backgroundPopoverWidth: CGFloat = 336
        static let leaksLeftColumnWidth: CGFloat = 320
        static let schemeFieldWidth: CGFloat = 140
        static let hexFieldWidth: CGFloat = 140
        static let derivedDataCardWidth: CGFloat = 260
    }

    enum Telemetry {
        static let historyCapacity: Int = 40
        static let pollIntervalMs: Int = 500
        static let minMemoryScaleMB: Double = 256
        static let minCPUScalePercent: Double = 100
        static let memoryHeadroomMultiplier: Double = 1.2
        static let freezeCPUThresholdPercent: Double = 80.0
        static let maxCapturedFreezeEvents: Int = 24
        static let percentUnit = "%"
        static let megabyteUnit = " MB"
    }

    enum StorageKeys {
        static let themePreset = "dc_theme_preset"
        static let backgroundPreset = "dc_bg_preset"
        static let customBackgroundPath = "dc_bg_custom_path"
        static let backgroundDimOpacity = "dc_bg_dim"
        static let backgroundBlurRadius = "dc_bg_blur"
        static let lastProjectPath = "dc_last_project_path"
        static let ollamaModel = "dc_ollama_model"
    }

    enum Defaults {
        static let defaultOllamaModel = "qwen2.5-coder:7b"
        static let defaultSimulatorUDID = "booted"
        static let defaultDestination = "platform=iOS Simulator,name=iPhone 16"
        static let defaultScrimOpacity: Double = 0.35
        static let defaultBlurRadius: Double = 0
        static let instrumentsAppPath = "/Applications/Xcode.app/Contents/Applications/Instruments.app"
    }

    enum Icons {
        static let terminal = "terminal"
        static let folder = "folder"
        static let paintbrush = "paintbrush"
        static let playFill = "play.fill"
        static let iphone = "iphone.gen3"
        static let warning = "exclamationmark.triangle"
        static let shieldCheck = "checkmark.shield"
        static let chevronRight = "chevron.right"
        static let checkmark = "checkmark"
        static let overview = "macwindow"
        static let crashlytics = "flame.fill"
        static let performance = "gauge.with.dots.needle.67percent"
        static let unitTests = "testtube.2"
        static let utilities = "wrench.and.screwdriver"
        static let waveform = "waveform.path.ecg"
        static let arrowClockwise = "arrow.clockwise"
        static let magnifyingGlass = "magnifyingglass"
        static let docText = "doc.text"
        static let sparkles = "sparkles"
    }
}

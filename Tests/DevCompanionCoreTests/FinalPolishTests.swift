import Foundation
import Testing
@testable import DevCompanionCore

@Suite("Final Polish Tests")
struct FinalPolishTests {
    @Test("AppPreferencesStore persists and loads preferences")
    func testAppPreferencesStore() {
        let suite = "xscope.test.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppPreferencesStore(defaults: defaults, key: "prefs")
        let custom = AppPreferences(
            telemetryIntervalSeconds: 3.0,
            logBufferCapacity: 1000,
            notifyOnCrash: false,
            notifyOnHang: true,
            notifyOnTaskComplete: false,
            languageOverride: .id
        )
        store.save(custom)
        let loaded = store.load()
        #expect(loaded == custom)
    }

    @Test("SimulatorSandboxService parses UserDefaults plist safely")
    func testParseUserDefaultsPlist() throws {
        let dict: [String: Any] = ["isDarkMode": true, "launchCount": 5, "username": "dev"]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        let entries = SimulatorSandboxService.parseUserDefaultsPlist(data: data)
        #expect(entries.count == 3)
        #expect(entries.first(where: { $0.key == "username" })?.value == "dev")
    }

    @Test("AssetAndDeadCodeAuditor detects unreferenced imagesets")
    func testAssetAndDeadCodeAuditor() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xscope_asset_audit_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let assetsDir = tempRoot.appendingPathComponent("Assets.xcassets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir.appendingPathComponent("UsedIcon.imageset"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsDir.appendingPathComponent("OrphanBanner.imageset"), withIntermediateDirectories: true)

        let swiftFile = tempRoot.appendingPathComponent("HomeView.swift")
        try "let img = Image(\"UsedIcon\")".write(to: swiftFile, atomically: true, encoding: .utf8)

        let auditor = AssetAndDeadCodeAuditor()
        let unused = auditor.findUnusedImageAssets(in: tempRoot)
        #expect(unused.count == 1)
        #expect(unused.first?.name == "OrphanBanner")
    }

    @Test("CodeReviewEngine.filterModules prioritizes leaf name over deep subfolder paths and splits display")
    func testFilterModulesLeafPriorityAndSplitDisplay() {
        let modules = [
            "BrimoApplication/Modules/Junior/CreateAccount/View",
            "BrimoApplication/Modules/Junior/Dashboard",
            "BrimoApplication/Modules/Junior",
            "brimo-native/Common/UIView/JuniorReceiptView"
        ]
        let filtered = CodeReviewEngine.filterModules(modules, query: "junior")
        #expect(filtered.first == "BrimoApplication/Modules/Junior")
        #expect(filtered.dropFirst().first == "brimo-native/Common/UIView/JuniorReceiptView")

        let split = CodeReviewEngine.splitModuleDisplay("BrimoApplication/Modules/Junior/Dashboard")
        #expect(split.leafName == "Dashboard")
        #expect(split.parentPath == "BrimoApplication/Modules/Junior")
    }

    @Test("MenuBarLayoutStore persists icon, density, and section order")
    func testMenuBarLayoutStore() {
        let suite = "xscope.test.menubar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MenuBarLayoutStore(defaults: defaults, key: "layout")
        var cfg = MenuBarLayoutConfig(iconStyle: .bolt, showTargetBadge: false, showLiveMetrics: true, density: .compact)
        cfg.moveSection(at: 0, offset: 1)
        store.save(cfg)

        let loaded = store.load()
        #expect(loaded.iconStyle == .bolt)
        #expect(loaded.density == .compact)
        #expect(loaded.showTargetBadge == false)
        #expect(loaded.sections.first?.kind == .running)
    }
}

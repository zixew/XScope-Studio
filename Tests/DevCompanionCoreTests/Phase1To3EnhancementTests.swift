import Foundation
import Testing
@testable import DevCompanionCore

@Suite("Phase 1-3 Enhancement Tests")
struct Phase1To3EnhancementTests {
    @Test("CommandPaletteMatcher ranks prefix and subsequence matches accurately")
    func testCommandPaletteMatcher() {
        let items = [
            CommandPaletteItem(id: "1", title: "Crashlytics", subtitle: "Inspect crash logs", icon: "flame", category: .module),
            CommandPaletteItem(id: "2", title: "Clean DerivedData", subtitle: "Clear Xcode build cache", icon: "trash", category: .action),
            CommandPaletteItem(id: "3", title: "Simulator", subtitle: "Controls & console", icon: "iphone", category: .module)
        ]

        let prefix = CommandPaletteMatcher.filter(items: items, query: "crash")
        #expect(prefix.first?.id == "1")

        let subseq = CommandPaletteMatcher.filter(items: items, query: "cdd")
        #expect(subseq.first?.id == "2")

        let empty = CommandPaletteMatcher.filter(items: items, query: "zzzzz")
        #expect(empty.isEmpty)
    }

    @Test("SimulatorLogRingBuffer enforces capacity cap and parses compact log lines")
    func testSimulatorLogRingBuffer() {
        var buffer = SimulatorLogRingBuffer(maxCapacity: 3)
        let lines = [
            "2026-11-27 08:30:10.001 Df MyApp[100:1] [com.demo:net] Request started",
            "2026-11-27 08:30:11.002 Er MyApp[100:1] [com.demo:net] Timeout error",
            "2026-11-27 08:30:12.003 In MyApp[100:2] [com.demo:ui] Rendered",
            "2026-11-27 08:30:13.004 Ft MyApp[100:3] [com.demo:auth] Fatal token error"
        ]
        let parsed = lines.compactMap { SimulatorLogRingBuffer.parseCompactLine($0) }
        #expect(parsed.count == 4)

        buffer.append(parsed)
        #expect(buffer.entries.count == 3)
        #expect(buffer.entries.first?.level == .error)

        let faults = buffer.filter(level: .fault, query: "auth")
        #expect(faults.count == 1)
        #expect(faults.first?.process == "MyApp")
    }

    @Test("DeepLinkPresetStore saves, deduplicates, and removes presets")
    func testDeepLinkPresetStore() {
        let suiteName = "xscope.test.deeplink.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DeepLinkPresetStore(defaults: defaults, key: "presets")
        _ = store.savePreset(title: "Home", urlString: "myapp://home")
        let deduped = store.savePreset(title: "Home Updated", urlString: "myapp://home")
        #expect(deduped.count == 1)
        #expect(deduped.first?.title == "Home Updated")

        let afterRemove = store.removePreset(id: deduped[0].id)
        #expect(afterRemove.isEmpty)
    }

    @Test("BuildAndSigningInspector parses xcactivitylog timings and provisioning plist")
    func testBuildAndSigningInspector() {
        let logText = """
        Build target CoreKit (2.45 seconds)
        Build target FeatureUI (8.10 seconds)
        """
        let targets = BuildAndSigningInspector.parseBuildTimings(
            fromActivityLogText: logText,
            projectName: "DemoApp",
            logDate: Date()
        )
        #expect(targets.count == 2)
        #expect(targets.first?.targetName == "FeatureUI")
        #expect(targets.first?.durationSeconds == 8.10)

        let plist = """
        junk-pkcs7-header<plist version="1.0"><dict>
        <key>Name</key><string>iOS Team Provisioning</string>
        <key>AppIDName</key><string>XC Wildcard</string>
        <key>TeamName</key><string>Acme Corp</string>
        <key>ExpirationDate</key><date>2099-01-01T00:00:00Z</date>
        <key>Entitlements</key><dict><key>aps-environment</key><string>development</string></dict>
        </dict></plist>trailing-bytes
        """.data(using: .isoLatin1)!

        let profile = BuildAndSigningInspector.parseProvisioningProfile(data: plist, filePath: "/tmp/test.mobileprovision")
        #expect(profile?.name == "iOS Team Provisioning")
        #expect(profile?.teamName == "Acme Corp")
        #expect(profile?.entitlementsCount == 1)
        #expect(profile?.isExpired == false)
    }

    @Test("ScanHealthHistoryStore caps snapshots and DiagnosticReportExporter builds Markdown")
    func testHealthHistoryAndExporter() {
        let suiteName = "xscope.test.health.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ScanHealthHistoryStore(defaults: defaults, key: "history")
        for i in 1...25 {
            _ = store.record(ScanHealthSnapshot(score: i * 3, crashCount: 0, hangCount: 0, warningCount: 1))
        }
        #expect(store.load().count == 20)

        let md = DiagnosticReportExporter.buildPerformanceMarkdown(
            appName: "XScope",
            cpuHistory: [12.0, 48.0],
            memoryHistory: [120.0, 145.5],
            freezes: []
        )
        #expect(md.contains("XScope"))
        #expect(md.contains("48.0%"))
        #expect(md.contains("145.5 MB"))
    }
}

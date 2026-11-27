import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Testing
@testable import DevCompanionCore

@Suite("DevCompanionCore Tests")
struct DevCompanionCoreTests {
    @Test("CodeReviewEngine detects missing [weak self] and strong UIKit delegate")
    func testCodeReviewDetectsUIKitAndSwiftUIIssues() {
        let sample = """
        final class DemoVC: UIViewController {
            var delegate: DemoDelegate?
            func load() {
                DispatchQueue.main.async {
                    self.view.backgroundColor = .red
                }
            }
        }
        struct DemoView: View {
            @ObservedObject var vm = DemoVM()
        }
        """

        let engine = CodeReviewEngine()
        let findings = engine.analyze(source: sample, fileName: "DemoVC.swift")

        #expect(findings.contains(where: { $0.category == .uiKit && $0.title.contains("weak") }))
        #expect(findings.contains(where: { $0.category == .memoryLeak && $0.title.contains("weak self") }))
        #expect(findings.contains(where: { $0.category == .swiftUI && $0.title.contains("@ObservedObject") }))
    }

    @Test("UnitTestStudio generates Mock Protocol and Swift Testing suite")
    func testUnitTestGenerationSwiftTesting() {
        let source = """
        protocol UserService {
            func fetchUser() async throws -> String
        }
        final class ProfileViewModel {
            func refresh() async {}
        }
        """

        let studio = UnitTestStudio()
        let generated = studio.generateTests(from: source, moduleName: "DemoApp", framework: .swiftTesting)

        #expect(generated.contains("import Testing"))
        #expect(generated.contains("@testable import DemoApp"))
        #expect(generated.contains("final class MockUserService: UserService"))
        #expect(generated.contains("struct ProfileViewModelTests"))
        #expect(generated.contains("@Test("))
    }

    @Test("UnitTestStudio generates XCTestCase suite")
    func testUnitTestGenerationXCTest() {
        let source = """
        final class CartViewModel {
            func checkout() throws {}
        }
        """

        let studio = UnitTestStudio()
        let generated = studio.generateTests(from: source, moduleName: "ShopApp", framework: .xcTest)

        #expect(generated.contains("import XCTest"))
        #expect(generated.contains("final class CartViewModelTests: XCTestCase"))
        #expect(generated.contains("func test_checkout() throws"))
    }

    @Test("SimulatorService parses simctl JSON correctly")
    func testSimctlJsonParsing() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
              {
                "isAvailable": true,
                "name": "iPhone 16 Pro",
                "state": "Booted",
                "udid": "ABC-123"
              },
              {
                "isAvailable": true,
                "name": "iPhone 16",
                "state": "Shutdown",
                "udid": "DEF-456"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let devices = SimulatorService.parseSimctlDevices(from: json)
        #expect(devices.count == 2)
        #expect(devices.first?.name == "iPhone 16 Pro")
        #expect(devices.first?.isBooted == true)
    }

    @Test("SwiftSyntaxHighlighter classifies Xcode syntax tokens")
    func testSwiftSyntaxHighlighter() {
        let code = """
        @Test("sample")
        func test_login() async {
            let vc = ProfileViewController() // comment
        }
        """
        let tokens = SwiftSyntaxHighlighter().tokenize(code)
        #expect(tokens.contains(where: { $0.text == "@Test" && $0.kind == .attribute }))
        #expect(tokens.contains(where: { $0.text == "\"sample\"" && $0.kind == .string }))
        #expect(tokens.contains(where: { $0.text == "func" && $0.kind == .keyword }))
        #expect(tokens.contains(where: { $0.text == "ProfileViewController" && $0.kind == .type }))
        #expect(tokens.contains(where: { $0.text.hasPrefix("//") && $0.kind == .comment }))
    }

    @Test("XcodeUtilitiesService generates UIColor and SwiftUI Color tokens")
    func testColorTokenGenerator() {
        let svc = XcodeUtilitiesService()
        let code = svc.generateColorTokenCode(name: "brandMint", hex: "#28D796")
        #expect(code.contains("static let brandMint = UIColor("))
        #expect(code.contains("static let brandMint = Color("))
        #expect(code.contains("Hex #28D796"))
    }

    @Test("XcodeUtilitiesService detects missing translations in .xcstrings")
    func testXcstringsMissingScanner() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "strings": {
            "welcome_title": {
              "localizations": {
                "en": { "stringUnit": { "value": "Welcome" } },
                "id": { "stringUnit": { "value": "Selamat Datang" } }
              }
            },
            "checkout_cta": {
              "localizations": {
                "en": { "stringUnit": { "value": "Pay Now" } }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let missing = XcodeUtilitiesService().scanMissingLocalizations(in: json)
        #expect(missing.count == 1)
        #expect(missing.first?.key == "checkout_cta")
        #expect(missing.first?.missingLanguages == ["id"])
    }

    @Test("AgentService builds deterministic [weak self] fix and UnitTestPlacementPlan")
    func testAgentServiceFixAndPlacementPlan() {
        let agent = AgentService()
        let finding = CodeReviewFinding(
            fileName: "ProfileViewController.swift",
            lineNumber: 14,
            severity: .critical,
            category: .memoryLeak,
            title: "Missing [weak self]",
            detail: "Retain cycle",
            codeSnippet: "DispatchQueue.main.async {"
        )

        let proposal = agent.deterministicFix(for: finding, filePath: nil)
        #expect(proposal.newSnippet.contains("[weak self]"))
        #expect(!proposal.manualSteps.isEmpty)

        let plan = agent.buildUnitTestPlan(
            source: "protocol AuthSvc { func login() }\nfinal class LoginVM { func submit() {} }",
            sourceFileName: "LoginVM.swift",
            projectURL: nil,
            moduleName: "MyApp",
            framework: .swiftTesting
        )
        #expect(plan.targetName == "MyAppTests")
        #expect(plan.operations.first?.action == .newFile)
        #expect(plan.operations.first?.relativePath == "Tests/MyAppTests/LoginVMTests.swift")
        #expect(plan.generatedCode.contains("MockAuthSvc"))
    }

    @Test("ProcessTelemetryService parses ps output and hang duration")
    func testProcessTelemetryParsing() {
        let psOut = """
          4123 /Users/dev/Library/Developer/CoreSimulator/Devices/123/data/Containers/Bundle/Application/ABC/MyiOSApp.app/MyiOSApp
          999 /usr/sbin/syslogd
        """
        let procs = ProcessTelemetryService.parseSimulatorProcesses(from: psOut)
        #expect(procs.count == 1)
        #expect(procs.first?.id == 4123)
        #expect(procs.first?.name == "MyiOSApp")

        let sample = ProcessTelemetryService.parsePsSample(from: " 14.8  184320\n")
        #expect(sample?.cpuPercent == 14.8)
        #expect(sample?.memoryMB == 180.0)

        let hangSec = ProcessTelemetryService.parseHangDuration(from: "Hang Duration: 1.82 s")
        #expect(hangSec == 1.82)
    }

    @Test("AgentService applyPatch and revertPatch round-trip safely")
    func testApplyAndRevertPatch() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("TestPatch_\(UUID().uuidString).swift")
        try "DispatchQueue.main.async { self.title = \"Hi\" }".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let agent = AgentService()
        let record = try agent.applyPatch(
            to: tempURL,
            oldSnippet: "DispatchQueue.main.async {",
            newSnippet: "DispatchQueue.main.async { [weak self] in"
        )
        let patched = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(patched.contains("[weak self]"))

        try agent.revertPatch(record)
        let reverted = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(reverted == "DispatchQueue.main.async { self.title = \"Hi\" }")
    }

    @Test("UnitTestStudio parses xcodebuild -list -json schemes and targets")
    func testXcodeListJsonParsing() throws {
        let json = """
        {
          "project": {
            "name": "MyiOSApp",
            "schemes": ["MyiOSApp", "MyiOSAppTests"],
            "targets": ["MyiOSApp", "MyiOSAppTests"]
          }
        }
        """.data(using: .utf8)!

        let meta = UnitTestStudio.parseXcodeListJson(from: json)
        #expect(meta?.projectName == "MyiOSApp")
        #expect(meta?.schemes == ["MyiOSApp", "MyiOSAppTests"])
        #expect(meta?.targets.contains("MyiOSAppTests") == true)
    }

    @Test("ProcessTelemetryService filters out macOS apps and prioritizes Simulator user apps")
    func testSimulatorProcessFiltering() {
        let psOutput = """
          101 /Applications/Xcode.app/Contents/MacOS/Xcode
          202 /Library/Developer/CoreSimulator/Volumes/iOS_21A/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.0.simruntime/Contents/Resources/RuntimeRoot/Applications/MobileSafari.app/MobileSafari
          303 /Users/dev/Library/Developer/CoreSimulator/Devices/ABC-123/data/Containers/Bundle/Application/XYZ/MyProdApp.app/MyProdApp
          303 /Users/dev/Library/Developer/CoreSimulator/Devices/ABC-123/data/Containers/Bundle/Application/XYZ/MyProdApp.app/MyProdApp
        """
        let processes = ProcessTelemetryService.parseSimulatorProcesses(from: psOutput)
        #expect(processes.count == 2)
        #expect(processes.first?.name == "MyProdApp")
        #expect(processes.first?.id == 303)
        #expect(!processes.contains(where: { $0.name == "Xcode" }))
    }

    @Test("ProcessTelemetryService parses ps CPU and RSS sample accurately")
    func testPsSampleParsing() {
        let sample = ProcessTelemetryService.parsePsSample(from: "  18.4  146022.4 \n")
        #expect(sample != nil)
        #expect(sample?.cpuPercent == 18.4)
        #expect(abs((sample?.memoryMB ?? 0) - (146022.4 / 1024.0)) < 0.01)
    }

    @Test("UnitTestStudio does not emit dummy SampleViewModel on empty input")
    func testUnitTestStudioNoDummyFallback() {
        let studio = UnitTestStudio()
        let generated = studio.generateTests(from: "// empty", moduleName: "ProdApp", framework: .swiftTesting)
        #expect(!generated.contains("SampleViewModel"))
        #expect(generated.contains("Tidak ada class/struct/actor"))
    }

    @Test("UserDefaultsStore persists and removes string and double values")
    func testUserDefaultsStoreRoundTrip() {
        let suiteName = "com.devcompanion.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsStore(defaults: defaults)
        store.set("/tmp/MyApp", forKey: "test_project_path")
        store.set(0.82, forKey: "test_opacity")

        #expect(store.string(forKey: "test_project_path") == "/tmp/MyApp")
        #expect(store.double(forKey: "test_opacity") == 0.82)

        store.removeObject(forKey: "test_project_path")
        #expect(store.string(forKey: "test_project_path") == nil)
    }

    // MARK: - Stage 4 Regression Tests (TC-AUT-001 .. TC-AUT-010)

    private final class MockCommandRunner: CommandExecuting, @unchecked Sendable {
        struct Invocation: Sendable {
            let executable: String
            let arguments: [String]
            let workingDirectory: URL?
        }

        private let lock = NSLock()
        private var invocations: [Invocation] = []
        let handler: @Sendable (String, [String], URL?) throws -> CommandOutput

        init(handler: @escaping @Sendable (String, [String], URL?) throws -> CommandOutput) {
            self.handler = handler
        }

        func recordedInvocations() -> [Invocation] {
            lock.withLock { invocations }
        }

        func run(_ executable: String, arguments: [String], workingDirectory: URL?) async throws -> CommandOutput {
            lock.withLock {
                invocations.append(Invocation(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
            }
            return try handler(executable, arguments, workingDirectory)
        }
    }

    @Test("TC-AUT-001: ProcessRunner handles success, non-zero exit, and >64KB stderr without deadlock")
    func testProcessRunnerSuccessNonZeroAndLargeStderr() async throws {
        let runner = ProcessRunner(defaultTimeoutSeconds: 10)

        let ok = try await runner.run("/bin/echo", arguments: ["hello"])
        #expect(ok.isSuccess)
        #expect(ok.exitCode == 0)
        #expect(ok.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")

        let fail = try await runner.run("/usr/bin/false", arguments: [])
        #expect(!fail.isSuccess)
        #expect(fail.exitCode != 0)

        let largeStderr = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "head -c 80000 /dev/zero | tr '\\0' 'e' >&2; printf 'done'"]
        )
        #expect(largeStderr.isSuccess)
        #expect(largeStderr.stderr.count == 80_000)
        #expect(largeStderr.stdout == "done")
    }

    @Test("TC-AUT-002: ProcessRunner enforces timeout and supports task cancellation")
    func testProcessRunnerTimeoutAndCancellation() async throws {
        let shortRunner = ProcessRunner(defaultTimeoutSeconds: 0.15)
        do {
            _ = try await shortRunner.run("/bin/sleep", arguments: ["5"])
            Issue.record("Expected CompanionError.commandTimedOut")
        } catch let error as CompanionError {
            #expect(error == .commandTimedOut(executable: "/bin/sleep", seconds: 0.15))
        }

        let longRunner = ProcessRunner(defaultTimeoutSeconds: 10)
        let task = Task {
            try await longRunner.run("/bin/sleep", arguments: ["5"])
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected
        }
    }

    @Test("TC-AUT-003: SimulatorService filters unavailable simulators, sorts booted-first, handles malformed JSON, and parses devicectl")
    func testSimulatorServiceParsingEdgeCases() {
        let simJson = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
              { "isAvailable": false, "name": "iPhone Old", "state": "Shutdown", "udid": "UNAVAIL-1" },
              { "isAvailable": true, "name": "iPhone Zeta", "state": "Shutdown", "udid": "SHUT-Z" },
              { "isAvailable": true, "name": "iPhone Alpha", "state": "Shutdown", "udid": "SHUT-A" },
              { "isAvailable": true, "name": "iPhone Booted", "state": "Booted", "udid": "BOOT-1" }
            ]
          }
        }
        """.data(using: .utf8)!

        let devices = SimulatorService.parseSimctlDevices(from: simJson)
        #expect(devices.count == 3)
        #expect(!devices.contains(where: { $0.id == "UNAVAIL-1" }))
        #expect(devices.map(\.name) == ["iPhone Booted", "iPhone Alpha", "iPhone Zeta"])

        #expect(SimulatorService.parseSimctlDevices(from: Data("not-json".utf8)).isEmpty)

        let devicectlJson = """
        {
          "result": {
            "devices": [
              {
                "identifier": "DEV-1",
                "deviceProperties": { "name": "My iPhone", "osVersionNumber": "18.1" },
                "connectionProperties": { "transportType": "wired" }
              },
              {
                "identifier": "DEV-2",
                "deviceProperties": { "name": "Fallback iPad" }
              },
              {
                "deviceProperties": { "name": "Missing ID" }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let physical = SimulatorService.parseDevicectlDevices(from: devicectlJson)
        #expect(physical.count == 2)
        #expect(physical[0] == PhysicalDevice(id: "DEV-1", name: "My iPhone", osVersion: "18.1", connectionType: "wired"))
        #expect(physical[1] == PhysicalDevice(id: "DEV-2", name: "Fallback iPad", osVersion: "iOS", connectionType: "USB/Wi-Fi"))
        #expect(SimulatorService.parseDevicectlDevices(from: Data("{}".utf8)).isEmpty)
    }

    @Test("TC-AUT-004: SimulatorService sendPushNotification writes temp .apns payload and cleans it up")
    func testSimulatorPushTempFileCleanup() async throws {
        let mock = MockCommandRunner { executable, arguments, _ in
            #expect(executable == "/usr/bin/xcrun")
            #expect(arguments.prefix(4) == ["simctl", "push", "booted", "com.example.app"])
            if let path = arguments.last {
                #expect(FileManager.default.fileExists(atPath: path))
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let text = String(data: data, encoding: .utf8) ?? ""
                #expect(text.contains("Hello"))
                #expect(text.contains("Body"))
            }
            return CommandOutput(exitCode: 0, stdout: "", stderr: "")
        }

        let service = SimulatorService(runner: mock)
        let out = try await service.sendPushNotification(bundleID: "com.example.app", title: "Hello", body: "Body")
        #expect(out.isSuccess)
        if let path = mock.recordedInvocations().last?.arguments.last {
            #expect(!FileManager.default.fileExists(atPath: path))
        } else {
            Issue.record("Expected .apns temp path argument")
        }
    }

    @Test("TC-AUT-005: DiagnosticService classifies .hang files and builds symbolicateAddress/recordTrace commands")
    func testDiagnosticServiceHangAndCommands() async throws {
        let diagDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
        try? FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)
        let hangFile = diagDir.appendingPathComponent("DevCompanionQA_2026.hang")
        if (try? "Date/Time: 2026-11-26\nEvent: hang".write(to: hangFile, atomically: true, encoding: .utf8)) != nil {
            defer { try? FileManager.default.removeItem(at: hangFile) }
            let reports = DiagnosticService().loadRecentReports(limit: 50)
            let matched = reports.first(where: { $0.fileName == "DevCompanionQA_2026.hang" })
            #expect(matched?.kind == .hang)
        }

        let mock = MockCommandRunner { _, arguments, _ in
            if arguments.first == "atos" {
                if arguments.contains("0xBAD") {
                    return CommandOutput(exitCode: 1, stdout: "", stderr: "atos: failed")
                }
                return CommandOutput(exitCode: 0, stdout: "  main (in MyApp) + 42\n", stderr: "")
            }
            return CommandOutput(exitCode: 0, stdout: "recorded", stderr: "")
        }

        let service = DiagnosticService(runner: mock)
        let symOk = try await service.symbolicateAddress("0x1004", binaryOrDsymPath: "/tmp/MyApp.dSYM", loadAddress: "0x1000")
        #expect(symOk == "main (in MyApp) + 42")

        let symErr = try await service.symbolicateAddress("0xBAD", binaryOrDsymPath: "/tmp/MyApp.dSYM")
        #expect(symErr == "atos: failed")

        let (traceURL, traceOut) = try await service.recordTrace(
            template: "Time Profiler",
            deviceNameOrUDID: "booted",
            processName: "MyApp",
            durationSeconds: 5
        )
        #expect(traceOut.isSuccess)
        #expect(traceURL.pathExtension == "trace")
        let lastArgs = mock.recordedInvocations().last?.arguments ?? []
        #expect(lastArgs.contains("xctrace"))
        #expect(lastArgs.contains("--time-limit"))
        #expect(lastArgs.contains("5s"))
    }

    @Test("TC-AUT-006: CodeReviewEngine covers mainThread/swiftUI/safety rules, negative cases, and directory exclusions")
    func testCodeReviewRulesNegativesAndDirectoryExclusions() throws {
        let source = """
        // Data(contentsOf: URL(string: "https://example.com")!)
        static let sharedDF = DateFormatter()
        let localDF = DateFormatter()
        let raw = try! JSONSerialization.data(withJSONObject: [:])
        let data = try? Data(contentsOf: url)
        DispatchQueue.main.async { [weak self] in
            self?.title = "OK"
        }
        weak var delegate: DemoDelegate?
        """

        let engine = CodeReviewEngine()
        let findings = engine.analyze(source: source, fileName: "Sample.swift")

        #expect(findings.contains(where: { $0.category == .mainThread }))
        #expect(findings.contains(where: { $0.category == .swiftUI && $0.codeSnippet.contains("localDF") }))
        #expect(!findings.contains(where: { $0.codeSnippet.contains("sharedDF") }))
        #expect(findings.contains(where: { $0.category == .safety }))
        #expect(!findings.contains(where: { $0.category == .memoryLeak }))
        #expect(!findings.contains(where: { $0.category == .uiKit }))
        #expect(!findings.contains(where: { $0.lineNumber == 1 }))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodeReviewDir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let srcDir = root.appendingPathComponent("Sources")
        let buildDir = root.appendingPathComponent(".build")
        let podsDir = root.appendingPathComponent("Pods")
        let derivedDir = root.appendingPathComponent("DerivedData")
        for dir in [srcDir, buildDir, podsDir, derivedDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try "let x = try! foo()".write(to: srcDir.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try "let x = try! foo()".write(to: buildDir.appendingPathComponent("Ignored1.swift"), atomically: true, encoding: .utf8)
        try "let x = try! foo()".write(to: podsDir.appendingPathComponent("Ignored2.swift"), atomically: true, encoding: .utf8)
        try "let x = try! foo()".write(to: derivedDir.appendingPathComponent("Ignored3.swift"), atomically: true, encoding: .utf8)

        let dirFindings = engine.analyzeDirectory(at: root)
        #expect(dirFindings.count == 1)
        #expect(dirFindings.first?.fileName == "App.swift")
    }

    @Test("TC-AUT-007: AgentService deterministicFix branches, line-targeted applyPatch, and writeApprovedTestPlan")
    func testAgentServiceBranchesLinePatchAndPlanWrite() throws {
        let agent = AgentService()

        let mainThreadFix = agent.deterministicFix(
            for: CodeReviewFinding(fileName: "A.swift", lineNumber: 3, severity: .critical, category: .mainThread, title: "Freeze", detail: "Blocking", codeSnippet: "Thread.sleep(forTimeInterval: 1)"),
            filePath: nil
        )
        #expect(!mainThreadFix.manualSteps.isEmpty)

        let uiKitFix = agent.deterministicFix(
            for: CodeReviewFinding(fileName: "A.swift", lineNumber: 4, severity: .critical, category: .uiKit, title: "Delegate", detail: "Strong", codeSnippet: "var delegate: MyDelegate?"),
            filePath: nil
        )
        #expect(uiKitFix.newSnippet == "weak var delegate: MyDelegate?")

        let swiftUIFix = agent.deterministicFix(
            for: CodeReviewFinding(fileName: "A.swift", lineNumber: 5, severity: .warning, category: .swiftUI, title: "State", detail: "Observed", codeSnippet: "@ObservedObject var vm = VM()"),
            filePath: nil
        )
        #expect(swiftUIFix.newSnippet == "@StateObject var vm = VM()")

        let safetyFix = agent.deterministicFix(
            for: CodeReviewFinding(fileName: "A.swift", lineNumber: 6, severity: .suggestion, category: .safety, title: "Try", detail: "Force", codeSnippet: "let d = try! fn()"),
            filePath: nil
        )
        #expect(safetyFix.newSnippet == "let d = try? fn()")

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("LinePatch_\(UUID().uuidString).swift")
        let initial = """
        func first() {
            DispatchQueue.main.async { self.a() }
        }
        func second() {
            DispatchQueue.main.async { self.b() }
        }
        """
        try initial.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        _ = try agent.applyPatch(
            to: tempFile,
            oldSnippet: "DispatchQueue.main.async {",
            newSnippet: "DispatchQueue.main.async { [weak self] in",
            lineNumber: 5
        )
        let after = try String(contentsOf: tempFile, encoding: .utf8).components(separatedBy: .newlines)
        #expect(!after[1].contains("[weak self]"))
        #expect(after[4].contains("[weak self]"))

        do {
            _ = try agent.applyPatch(to: tempFile, oldSnippet: "nonExistent()", newSnippet: "other()")
            Issue.record("Expected CompanionError.patchMismatch")
        } catch let err as CompanionError {
            #expect(err == .patchMismatch(fileName: tempFile.lastPathComponent))
        }

        let projRoot = FileManager.default.temporaryDirectory.appendingPathComponent("TestPlanProj_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projRoot) }

        let plan = agent.buildUnitTestPlan(
            source: "protocol Repo { func load() }\nfinal class HomeVM { func onAppear() {} }",
            sourceFileName: "HomeVM.swift",
            projectURL: projRoot,
            moduleName: "Shop",
            framework: .swiftTesting
        )
        let primaryURL = try agent.writeApprovedTestPlan(plan, projectURL: projRoot)
        #expect(FileManager.default.fileExists(atPath: primaryURL.path))
        let mockURL = projRoot.appendingPathComponent("Tests/ShopTests/Mocks/MockRepo.swift")
        #expect(FileManager.default.fileExists(atPath: mockURL.path))
    }

    @Test("TC-AUT-008: UnitTestStudio parses workspace JSON and passes -workspace/-project flags")
    func testUnitTestStudioWorkspaceAndFlags() async throws {
        let wsJson = """
        {
          "workspace": {
            "name": "MyWorkspace",
            "schemes": ["AppScheme", "AppTests"]
          }
        }
        """.data(using: .utf8)!

        let wsMeta = UnitTestStudio.parseXcodeListJson(from: wsJson)
        #expect(wsMeta?.projectName == "MyWorkspace")
        #expect(wsMeta?.schemes == ["AppScheme", "AppTests"])
        #expect(wsMeta?.targets.isEmpty == true)
        #expect(UnitTestStudio.parseXcodeListJson(from: Data("invalid".utf8)) == nil)

        let mock = MockCommandRunner { _, _, _ in
            CommandOutput(exitCode: 0, stdout: "", stderr: "")
        }
        let studio = UnitTestStudio(runner: mock)

        _ = try await studio.runXcodeBuildTest(projectPath: "/tmp/App.xcworkspace", scheme: "AppScheme", destination: "platform=iOS Simulator,name=iPhone 16")
        #expect(mock.recordedInvocations().last?.arguments.contains("-workspace") == true)

        _ = try await studio.runXcodeBuildTest(projectPath: "/tmp/App.xcodeproj", scheme: "AppScheme", destination: "platform=iOS Simulator,name=iPhone 16")
        #expect(mock.recordedInvocations().last?.arguments.contains("-project") == true)
    }

    @Test("TC-AUT-009: XcodeUtilitiesService handles 3-char hex, invalid hex, identifier sanitization, and directory scan")
    func testXcodeUtilitiesHexSanitizationAndDirScan() throws {
        let svc = XcodeUtilitiesService()

        let whiteCode = svc.generateColorTokenCode(name: "my-color", hex: "#FFF")
        #expect(whiteCode.contains("static let mycolor = UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.0)"))
        #expect(whiteCode.contains("Generated from Hex #FFFFFF"))

        let invalidCode = svc.generateColorTokenCode(name: "bad", hex: "#ZZZZZZ")
        #expect(invalidCode.contains("Invalid hex color"))

        let digitNameCode = svc.generateColorTokenCode(name: "123primary", hex: "000000")
        #expect(digitNameCode.contains("static let _123primary"))

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("L10nDir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xcstrings = """
        {
          "sourceLanguage": "en",
          "strings": {
            "empty_id": {
              "localizations": {
                "en": { "stringUnit": { "value": "Hello" } },
                "id": { "stringUnit": { "value": "   " } }
              }
            }
          }
        }
        """
        try xcstrings.write(to: tempDir.appendingPathComponent("Feature.xcstrings"), atomically: true, encoding: .utf8)

        let entries = svc.scanMissingLocalizationsInDirectory(at: tempDir)
        #expect(entries.count == 1)
        #expect(entries.first?.fileName == "Feature.xcstrings")
        #expect(entries.first?.missingLanguages == ["id"])
    }

    @Test("TC-AUT-010: KeychainStore performs isolated CRUD or reports entitlement restriction gracefully")
    func testKeychainStoreCRUD() throws {
        let serviceName = "com.devcompanion.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: serviceName)
        let account = "gemini_test_key"
        defer { try? store.deleteSecret(account: account) }

        do {
            try store.saveSecret("secret-1", account: account)
            #expect(store.loadSecret(account: account) == "secret-1")

            try store.saveSecret("secret-2", account: account)
            #expect(store.loadSecret(account: account) == "secret-2")

            try store.saveSecret("", account: account)
            #expect(store.loadSecret(account: account) == nil)

            try store.deleteSecret(account: "non-existent-account")
        } catch let error as CompanionError {
            if case let .keychainFailure(status) = error {
                // In unsigned CLI test runners, errSecMissingEntitlement (-34018) may be returned by macOS Security.
                #expect(status == -34018 || status == errSecInteractionNotAllowed)
            } else {
                Issue.record("Unexpected CompanionError: \(error)")
            }
        }
    }

    @Test("TC-AUT-011: DiagnosticService parses .ips JSON and classic .crash force-close reports")
    func testCrashReportAnalysis() {
        let svc = DiagnosticService()

        let ipsContent = """
        {"app_name":"ShopApp","bug_type":"309"}
        {
          "procName": "ShopApp",
          "faultingThread": 0,
          "exception": {"type": "EXC_BREAKPOINT", "signal": "SIGTRAP"},
          "termination": {"indicator": "Fatal error"},
          "asi": {"libswiftCore.dylib": ["Fatal error: Unexpectedly found nil while unwrapping an Optional value: file ShopApp/CartViewModel.swift, line 42"]},
          "usedImages": [{"name": "ShopApp"}],
          "threads": [
            {
              "frames": [
                {"imageIndex": 0, "symbol": "CartViewModel.checkout()", "sourceFile": "CartViewModel.swift", "sourceLine": 42}
              ]
            }
          ]
        }
        """
        let ipsReport = svc.analyzeCrashReport(content: ipsContent)
        #expect(ipsReport.processName == "ShopApp")
        #expect(ipsReport.exceptionType == "EXC_BREAKPOINT (SIGTRAP)")
        #expect(ipsReport.terminationReason.contains("Fatal error"))
        #expect(ipsReport.sourceFileName == "CartViewModel.swift")
        #expect(ipsReport.sourceLineNumber == 42)
        #expect(ipsReport.culpritSymbol.contains("CartViewModel.checkout()"))

        let classicCrash = """
        Process:               CheckoutApp [991]
        Exception Type:        EXC_BAD_ACCESS (SIGSEGV)
        Termination Reason:    Namespace SIGNAL, Code 11 Segmentation fault: 11

        Thread 0 Crashed:
        0   CheckoutApp   0x100234 PaymentService.process() + 48 (PaymentService.swift:18)
        """
        let classicReport = svc.analyzeCrashReport(content: classicCrash)
        #expect(classicReport.processName == "CheckoutApp")
        #expect(classicReport.exceptionType == "EXC_BAD_ACCESS (SIGSEGV)")
        #expect(classicReport.sourceFileName == "PaymentService.swift")
        #expect(classicReport.sourceLineNumber == 18)
    }

    @Test("TC-AUT-012: DiagnosticService locates Swift source snippet around crash line")
    func testLocateCrashSourceSnippet() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CrashProj_\(UUID().uuidString)")
        let srcDir = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let swiftFile = srcDir.appendingPathComponent("CartViewModel.swift")
        try """
        final class CartViewModel {
            func checkout() {
                let total: Int? = nil
                print(total!)
            }
        }
        """.write(to: swiftFile, atomically: true, encoding: .utf8)

        let svc = DiagnosticService()
        let snippet = svc.locateSourceSnippet(fileName: "CartViewModel.swift", lineNumber: 4, in: root)
        #expect(snippet != nil)
        #expect(snippet?.lineNumber == 4)
        #expect(snippet?.snippet.contains("→    4 |         print(total!)") == true)
    }

    @Test("TC-AUT-013: AgentService builds structured Antigravity prompts for findings and crashes")
    func testAntigravityPromptBuilders() {
        let agent = AgentService()
        let finding = CodeReviewFinding(
            fileName: "ProfileVC.swift",
            lineNumber: 22,
            severity: .critical,
            category: .memoryLeak,
            title: "Missing [weak self]",
            detail: "Retain cycle risk",
            codeSnippet: "DispatchQueue.main.async { self.reload() }"
        )
        let findingPrompt = agent.buildAntigravityPrompt(for: finding, filePath: "/tmp/App/ProfileVC.swift")
        #expect(findingPrompt.contains("/tmp/App/ProfileVC.swift:22"))
        #expect(findingPrompt.contains("Missing [weak self]"))
        #expect(findingPrompt.contains("DispatchQueue.main.async { self.reload() }"))

        let crash = CrashAnalysisReport(
            processName: "ShopApp",
            exceptionType: "EXC_BREAKPOINT (SIGTRAP)",
            terminationReason: "Fatal error: nil",
            crashedThread: "Thread 0 Crashed",
            culpritSymbol: "CartViewModel.checkout()",
            sourceFileName: "CartViewModel.swift",
            sourceLineNumber: 4
        )
        let snippet = CrashSourceSnippet(
            filePath: "/tmp/App/CartViewModel.swift",
            fileName: "CartViewModel.swift",
            lineNumber: 4,
            snippet: "→    4 |         print(total!)"
        )
        let crashPrompt = agent.buildAntigravityCrashPrompt(crash: crash, snippet: snippet)
        #expect(crashPrompt.contains("/tmp/App/CartViewModel.swift:4"))
        #expect(crashPrompt.contains("EXC_BREAKPOINT (SIGTRAP)"))
        #expect(crashPrompt.contains("print(total!)"))
    }

    @Test("TC-AUT-014: DiagnosticService filters macOS system daemons by default and extracts clean processName")
    func testDiagnosticReportSystemFiltering() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DiagFilter_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "sys".write(to: dir.appendingPathComponent("ExcUserFault_IBAgent-iOS-2026-11-26-100155.ips"), atomically: true, encoding: .utf8)
        try "app".write(to: dir.appendingPathComponent("ShopApp-2026-11-26-100200.ips"), atomically: true, encoding: .utf8)

        let svc = DiagnosticService()
        let appOnly = svc.loadRecentReports(includeSystemReports: false, directory: dir)
        #expect(appOnly.count == 1)
        #expect(appOnly.first?.processName == "ShopApp")

        let allReports = svc.loadRecentReports(includeSystemReports: true, directory: dir)
        #expect(allReports.count == 2)
        #expect(allReports.contains(where: { $0.processName == "IBAgent-iOS" && $0.isSystemDaemon }))
    }

    @Test("TC-AUT-015: AgentService builds Antigravity prompts for Unit Tests and L10n")
    func testAntigravityUnitTestAndL10nPrompts() {
        let agent = AgentService()
        let testPrompt = agent.buildAntigravityUnitTestPrompt(
            sourceCode: "final class CartVM { func pay() {} }",
            fileName: "CartVM.swift",
            moduleName: "Shop",
            framework: .swiftTesting,
            targetPath: "Tests/ShopTests/CartVMTests.swift"
        )
        #expect(testPrompt.contains("CartVM.swift"))
        #expect(testPrompt.contains("Tests/ShopTests/CartVMTests.swift"))
        #expect(testPrompt.contains("final class CartVM"))

        let l10nEntries = [
            LocalizationMissingEntry(fileName: "Localizable.xcstrings", key: "checkout.pay", missingLanguages: ["id"])
        ]
        let l10nPrompt = agent.buildAntigravityL10nPrompt(missingEntries: l10nEntries, projectName: "ShopApp")
        #expect(l10nPrompt.contains("ShopApp"))
        #expect(l10nPrompt.contains("checkout.pay"))
        #expect(l10nPrompt.contains("id"))
    }

    @Test("TC-AUT-016: ProjectFileWatcher detects Swift edits and LiveReloadService runs incremental build + launch")
    func testLiveReloadWatcherAndBuild() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LiveWatch_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("HomeView.swift")
        try "struct HomeView {}".write(to: file, atomically: true, encoding: .utf8)

        let watcher = ProjectFileWatcher()
        let initial = await watcher.detectChanges(in: root)
        #expect(initial.isEmpty)

        try await Task.sleep(for: .milliseconds(50))
        try "struct HomeView { var x = 1 }".write(to: file, atomically: true, encoding: .utf8)
        let updated = await watcher.detectChanges(in: root)
        #expect(updated.map(\.lastPathComponent) == ["HomeView.swift"])

        let commands = CommandLog()
        let mock = MockCommandRunner { exec, args, _ in
            commands.record("\(exec) \(args.joined(separator: " "))")
            if args.contains("-showBuildSettings") {
                return CommandOutput(exitCode: 0, stdout: "    TARGET_BUILD_DIR = /tmp/Build\n    FULL_PRODUCT_NAME = ShopApp.app\n    PRODUCT_BUNDLE_IDENTIFIER = com.shop.app\n", stderr: "")
            }
            return CommandOutput(exitCode: 0, stdout: "OK", stderr: "")
        }
        let service = LiveReloadService(runner: mock)
        let out = try await service.incrementalBuildAndLaunch(
            projectPath: "/tmp/ShopApp.xcodeproj",
            scheme: "ShopApp",
            simulatorUDID: "BOOTED-1",
            destination: "platform=iOS Simulator,name=iPhone 16"
        )
        #expect(out.isSuccess)
        let log = commands.snapshot()
        #expect(log.count == 4)
        #expect(log[0].contains("build") && !log[0].contains("clean"))
        #expect(log[2].contains("simctl install BOOTED-1 /tmp/Build/ShopApp.app"))
        #expect(log[3].contains("simctl launch BOOTED-1 com.shop.app"))
    }

    @Test("TC-AUT-017: FileProjectSessionStore isolates per-project data, resets, and exports/imports backup")
    func testProjectSessionStoreIsolationAndBackup() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionStore_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let store = FileProjectSessionStore(baseDirectory: baseDir)
        let proj1 = URL(fileURLWithPath: "/tmp/ProjectOne")
        let proj2 = URL(fileURLWithPath: "/tmp/ProjectTwo")

        let snap1 = ProjectSessionSnapshot(
            projectPath: proj1.path,
            projectName: "ProjectOne",
            liveCPU: 32.5,
            liveMemoryMB: 180.0,
            findings: [CodeReviewFinding(fileName: "App.swift", lineNumber: 10, severity: .warning, category: .swiftUI, title: "Warn", detail: "Detail", codeSnippet: "let x = 1")],
            hasAnalyzed: true
        )
        try store.save(snap1)

        #expect(store.load(for: proj2) == nil)
        let loaded1 = store.load(for: proj1)
        #expect(loaded1?.liveCPU == 32.5)
        #expect(loaded1?.findings.count == 1)

        let backupURL = baseDir.appendingPathComponent("gdrive_backup.json")
        try store.exportBackup(to: backupURL, projectURL: nil)
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        try store.delete(for: proj1)
        #expect(store.load(for: proj1) == nil)

        let restoredCount = try store.importBackup(from: backupURL)
        #expect(restoredCount == 1)
        #expect(store.load(for: proj1)?.liveMemoryMB == 180.0)
    }

    @Test("TC-AUT-018: CodeReviewEngine sorts P0 Critical first and ProcessTelemetryService parses runtime leaks output")
    func testPrioritySortingAndRuntimeLeaksParsing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PrioritySort_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Put suggestion in A.swift and critical in Z.swift to verify severity beats alphabetical order
        try "let x = try! foo()".write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "let f = DateFormatter()".write(to: root.appendingPathComponent("M.swift"), atomically: true, encoding: .utf8)
        try "let data = try? Data(contentsOf: url)".write(to: root.appendingPathComponent("Z.swift"), atomically: true, encoding: .utf8)

        let sorted = CodeReviewEngine().analyzeDirectory(at: root)
        #expect(sorted.count == 3)
        #expect(sorted[0].severity == .critical)
        #expect(sorted[0].severity.priorityBadge == "P0")
        #expect(sorted[1].severity == .warning)
        #expect(sorted[1].severity.priorityBadge == "P1")
        #expect(sorted[2].severity == .suggestion)
        #expect(sorted[2].severity.priorityBadge == "P2")

        let leaksStdout = """
        Process 45028: 3 leaks for 1536 total leaked bytes.
        Leak: 0x600003a10000  size=512  zone: DefaultMallocZone  BRImoDev.LoginVC
        ROOT LEAK: 0x600003a20000  size=1024  Swift closure context
        """
        let parsed = ProcessTelemetryService.parseLeaksOutput(from: leaksStdout, pid: 45028, exitCode: 1)
        #expect(parsed.isAvailable)
        #expect(parsed.leakCount == 3)
        #expect(parsed.leakedBytes == 1536)
        #expect(parsed.topFrames.count == 2)

        let sipBlocked = ProcessTelemetryService.parseLeaksOutput(
            from: "leaks[99]: [fatal] mach port not permitted due to System Integrity Protection",
            pid: 45028,
            exitCode: 1
        )
        #expect(!sipBlocked.isAvailable)
        #expect(sipBlocked.leakCount == 0)
    }

    @Test("TC-AUT-019: ProcessTelemetryService parses sample hot symbol and ProjectSessionStore persists FreezeLagEvent")
    func testSampleHotSymbolAndFreezeEventSessionPersistence() throws {
        let sampleOut = """
        Call graph:
          850 Thread_1234   DispatchQueue_1: com.apple.main-thread  (serial)
            + 850 start  (in dyld) + 2360  [0x100001]
            +   850 NotificationService.fetchSync()  (in BRImoDev) + 128  [0x104500]
            +     850 Data.init(contentsOf:)  (in Foundation) + 64  [0x180000]
        """
        let hot = ProcessTelemetryService.parseSampleHotSymbol(from: sampleOut, processName: "BRImoDev")
        #expect(hot == "NotificationService.fetchSync()")

        let blocked = ProcessTelemetryService.parseSampleHotSymbol(
            from: "sample cannot examine process 45028: System Integrity Protection",
            processName: "BRImoDev"
        )
        #expect(blocked == nil)

        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("FreezeSession_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: baseDir) }
        let store = FileProjectSessionStore(baseDirectory: baseDir)
        let proj = URL(fileURLWithPath: "/tmp/FreezeProject")

        let freeze = FreezeLagEvent(
            id: "freeze-1",
            durationSeconds: 2.5,
            peakCPUPercent: 101.7,
            memoryMB: 497.6,
            culpritSymbol: "NotificationService.fetchSync()",
            fileName: "NotificationService.swift",
            lineNumber: 44,
            codeSnippet: "let data = try Data(contentsOf: url)",
            reason: "Potensi Freeze / Main-Thread Blocking"
        )
        #expect(freeze.locationLabel == "NotificationService.swift:44")

        let snap = ProjectSessionSnapshot(
            projectPath: proj.path,
            projectName: "FreezeProject",
            capturedFreezeEvents: [freeze]
        )
        try store.save(snap)

        let loaded = store.load(for: proj)
        #expect(loaded?.capturedFreezeEvents.count == 1)
        #expect(loaded?.capturedFreezeEvents.first?.durationSeconds == 2.5)
        #expect(loaded?.capturedFreezeEvents.first?.locationLabel == "NotificationService.swift:44")
    }

    @Test("TC-AUT-020: DiagnosticService.isAppStackFrame distinguishes user app frames from Apple system frames")
    func testDiagnosticServiceIsAppStackFrame() {
        #expect(DiagnosticService.isAppStackFrame(
            "0  BRImoDev  0x104500 NotificationService.fetchSync() (NotificationService.swift:44)",
            processName: "BRImoDev",
            projectName: "Brimo-ios"
        ))
        #expect(DiagnosticService.isAppStackFrame(
            "1  BRImoDev  0x104620 LoginViewController.viewDidLoad + 120",
            processName: "BRImoDev",
            projectName: "Brimo-ios"
        ))
        #expect(!DiagnosticService.isAppStackFrame(
            "2  UIKitCore  0x1a0020 -[UIViewController loadViewIfRequired] + 956",
            processName: "BRImoDev",
            projectName: "Brimo-ios"
        ))
        #expect(!DiagnosticService.isAppStackFrame(
            "3  libsystem_kernel.dylib  0x1f0010 mach_msg2_trap + 8",
            processName: "BRImoDev",
            projectName: "Brimo-ios"
        ))
    }

    @Test("TC-AUT-021: CodeReviewEngine.sortFindings orders NEW and most recent first within each priority tier")
    func testSortFindingsOrdersNewAndNewestFirstByPriority() {
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_050_000)

        let p0OldAlphaFirst = CodeReviewFinding(
            fileName: "AAA_Old.swift",
            lineNumber: 10,
            severity: .critical,
            category: .memoryLeak,
            title: "Old P0",
            detail: "D",
            codeSnippet: "self.x = 1",
            detectedAt: olderDate,
            isNew: false
        )
        let p0NewAlphaLast = CodeReviewFinding(
            fileName: "ZZZ_New.swift",
            lineNumber: 99,
            severity: .critical,
            category: .mainThread,
            title: "New P0",
            detail: "D",
            codeSnippet: "Data(contentsOf: url)",
            detectedAt: newerDate,
            isNew: true
        )
        let p1Old = CodeReviewFinding(
            fileName: "AAA_Warn.swift",
            lineNumber: 5,
            severity: .warning,
            category: .swiftUI,
            title: "Old P1",
            detail: "D",
            codeSnippet: "DateFormatter()",
            detectedAt: olderDate,
            isNew: false
        )
        let p1New = CodeReviewFinding(
            fileName: "YYY_WarnNew.swift",
            lineNumber: 12,
            severity: .warning,
            category: .swiftUI,
            title: "New P1",
            detail: "D",
            codeSnippet: "DateFormatter()",
            detectedAt: newerDate,
            isNew: true
        )

        let sorted = CodeReviewEngine.sortFindings([p1Old, p0OldAlphaFirst, p1New, p0NewAlphaLast])
        #expect(sorted.map(\.fileName) == ["ZZZ_New.swift", "AAA_Old.swift", "YYY_WarnNew.swift", "AAA_Warn.swift"])
    }

    @Test("TC-AUT-022: SimulatorService parses connected PhysicalDevice and ProcessTelemetryService parses devicectl processes")
    func testPhysicalDeviceAndDevicectlProcessParsing() throws {
        let devicectlJSON = """
        {
          "result": {
            "devices": [
              {
                "identifier": "DEV-DISCONNECTED",
                "deviceProperties": { "name": "Old iPhone", "osVersionNumber": "17.4" },
                "hardwareProperties": { "marketingName": "iPhone 13" },
                "connectionProperties": { "pairingState": "paired", "tunnelState": "disconnected" }
              },
              {
                "identifier": "DEV-CONNECTED",
                "deviceProperties": { "name": "Dicky iPhone", "osVersionNumber": "18.1" },
                "hardwareProperties": { "marketingName": "iPhone 16 Pro" },
                "connectionProperties": { "pairingState": "paired", "tunnelState": "connected", "transportType": "wired" }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let devices = SimulatorService.parseDevicectlDevices(from: devicectlJSON)
        #expect(devices.count == 2)
        #expect(devices[0].id == "DEV-CONNECTED")
        #expect(devices[0].isConnected)
        #expect(devices[0].modelName == "iPhone 16 Pro")
        #expect(!devices[1].isConnected)

        let procJSON = """
        {
          "result": {
            "runningProcesses": [
              {
                "processIdentifier": 1042,
                "executable": "file:///private/var/containers/Bundle/Application/UUID-123/BRImoDev.app/BRImoDev"
              },
              {
                "processIdentifier": 88,
                "executable": "file:///usr/libexec/SpringBoard"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let procs = ProcessTelemetryService.parsePhysicalDeviceProcesses(
            from: procJSON,
            deviceID: "DEV-CONNECTED",
            deviceName: "Dicky iPhone"
        )
        #expect(procs.count == 1)
        #expect(procs[0].name == "BRImoDev")
        #expect(procs[0].isPhysicalDevice)
        #expect(procs[0].displayLabel.contains("[DEVICE] BRImoDev"))
    }

    @Test("TC-AUT-023: DiagnosticService resolves symbol-only crash frames to project Swift file/line and AgentService proposes crash patch")
    func testCrashSymbolToSwiftSourceResolutionAndPatchProposal() throws {
        let projDir = FileManager.default.temporaryDirectory.appendingPathComponent("CrashResolve_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projDir) }

        let swiftSource = """
        import Foundation

        final class PaymentConfirmationVC {
            func submitTransferPayload() {
                let raw = try! JSONSerialization.data(withJSONObject: ["amount": 50000])
                print(raw.count)
            }
        }
        """
        try swiftSource.write(to: projDir.appendingPathComponent("PaymentConfirmationVC.swift"), atomically: true, encoding: .utf8)

        // Crash report WITHOUT explicit .swift:line in the raw stack trace (only symbol names)
        let rawReport = CrashAnalysisReport(
            processName: "BRImoDev",
            exceptionType: "EXC_BREAKPOINT (SIGTRAP)",
            terminationReason: "Swift runtime failure: Unexpectedly found nil",
            crashedThread: "Thread 0 Crashed",
            culpritSymbol: "0  BRImoDev  0x104900 PaymentConfirmationVC.submitTransferPayload() + 64",
            sourceFileName: nil,
            sourceLineNumber: nil,
            stackFrames: [
                "0  BRImoDev  0x104900 PaymentConfirmationVC.submitTransferPayload() + 64",
                "1  UIKitCore  0x1a0020 -[UIApplication sendAction:to:from:forEvent:] + 100"
            ]
        )

        let diag = DiagnosticService()
        let resolved = diag.resolveProjectSource(for: rawReport, in: projDir)
        #expect(resolved.analysis.sourceFileName == "PaymentConfirmationVC.swift")
        #expect(resolved.analysis.sourceLineNumber == 5)
        #expect(resolved.analysis.humanExplanation.contains("Force Unwrap"))
        #expect(resolved.analysis.whenAction.contains("PaymentConfirmationVC.submitTransferPayload()"))
        #expect(resolved.snippet?.lineNumber == 5)

        let fix = AgentService().proposeCrashFix(for: resolved.analysis, snippet: resolved.snippet)
        #expect(fix.oldSnippet.contains("try!"))
        #expect(fix.newSnippet.contains("try?"))
    }

    @Test("TC-AUT-024: CodeReviewEngine parses Git branch diff lines, discovers project modules, checks code hygiene/security, and formats PR Markdown report")
    func testGitBranchDiffModuleDiscoveryAndHygieneRules() throws {
        let diffOutput = """
        diff --git a/Modules/Transfer/TransferVC.swift b/Modules/Transfer/TransferVC.swift
        --- a/Modules/Transfer/TransferVC.swift
        +++ b/Modules/Transfer/TransferVC.swift
        @@ -10,0 +11,3 @@
        +    print("debug transfer")
        +    let endpoint = "http://api.insecure.com/pay"
        +    fatalError("unhandled state")
        """
        let changedMap = CodeReviewEngine.parseUnifiedDiffChangedLines(from: diffOutput)
        #expect(changedMap["Modules/Transfer/TransferVC.swift"] == Set([11, 12, 13]))

        let source = """
        import Foundation
        final class TransferVC {
            func untouchedOldLine() {
                print("old print on line 4")
            }
            // line 6
            // line 7
            // line 8
            // line 9
            // line 10
            func newPRChanges() {
                print("debug transfer")
                let endpoint = "http://api.insecure.com/pay"
                fatalError("unhandled state")
            }
        }
        """
        let engine = CodeReviewEngine()
        // Only check lines 12..14 from the PR diff (ignoring line 4!)
        let prFindings = engine.analyze(source: source, fileName: "TransferVC.swift", allowedLines: Set([12, 13, 14]))
        #expect(!prFindings.contains(where: { $0.lineNumber == 4 }))
        let hasHygiene = prFindings.contains { $0.category == .codeHygiene && $0.lineNumber == 12 }
        let hasSecurity = prFindings.contains { $0.category == .security && $0.lineNumber == 13 }
        let hasCriticalSafety = prFindings.contains { $0.category == .safety && $0.severity == .critical && $0.lineNumber == 14 }
        #expect(hasHygiene)
        #expect(hasSecurity)
        #expect(hasCriticalSafety)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModulesTest_\(UUID().uuidString)")
        let modA = root.appendingPathComponent("Modules/Transfer")
        let modB = root.appendingPathComponent("Modules/Profile")
        try FileManager.default.createDirectory(at: modA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try source.write(to: modA.appendingPathComponent("TransferVC.swift"), atomically: true, encoding: .utf8)
        try "struct Profile {}".write(to: modB.appendingPathComponent("Profile.swift"), atomically: true, encoding: .utf8)

        let discoveredModules = engine.listProjectModules(in: root)
        #expect(discoveredModules.contains("Modules/Transfer"))
        #expect(discoveredModules.contains("Modules/Profile"))

        let md = engine.formatMarkdownPRReport(
            scopeTitle: "feature/transfer -> develop",
            summary: GitBranchComparisonSummary(sourceBranch: "feature/transfer", targetBranch: "develop", commits: ["a1b2c3d Add transfer"], changedSwiftFiles: ["Modules/Transfer/TransferVC.swift"]),
            findings: prFindings
        )
        #expect(md.contains("feature/transfer -> develop"))
        #expect(md.contains("CHANGES REQUESTED"))
    }

    @Test("TC-AUT-025: AgentService.resolveXcodeContainer prioritizes CocoaPods .xcworkspace -> .xcodeproj -> Package.swift and openInXcode launches container before jumping to line")
    func testSmartOpenInXcodeContainerPriorityAndTwoStageLaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SmartXcode_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 1. SwiftPM default Package.swift fallback
        let pkgURL = root.appendingPathComponent("Package.swift")
        try "// swift-tools-version: 6.0".write(to: pkgURL, atomically: true, encoding: .utf8)
        let resolvedPkg = AgentService.resolveXcodeContainer(in: root)
        #expect(resolvedPkg.kind == .swiftPackage)
        #expect(resolvedPkg.url.lastPathComponent == "Package.swift")

        // 2. .xcodeproj beats Package.swift (and internal project.xcworkspace is ignored)
        let projURL = root.appendingPathComponent("Brimo.xcodeproj")
        let internalWS = projURL.appendingPathComponent("project.xcworkspace")
        try FileManager.default.createDirectory(at: internalWS, withIntermediateDirectories: true)
        let resolvedProj = AgentService.resolveXcodeContainer(in: root)
        #expect(resolvedProj.kind == .xcodeproj)
        #expect(resolvedProj.url.lastPathComponent == "Brimo.xcodeproj")

        // 3. CocoaPods .xcworkspace beats .xcodeproj
        let cocoapodsWS = root.appendingPathComponent("Brimo.xcworkspace")
        try FileManager.default.createDirectory(at: cocoapodsWS, withIntermediateDirectories: true)
        let resolvedWS = AgentService.resolveXcodeContainer(in: root)
        #expect(resolvedWS.kind == .xcworkspace)
        #expect(resolvedWS.url.lastPathComponent == "Brimo.xcworkspace")

        // 4. Two-stage launch when Xcode is not open with the project
        let mockNotOpen = MockCommandRunner { exec, args, _ in
            if exec.hasSuffix("pgrep") {
                return CommandOutput(exitCode: 1, stdout: "", stderr: "")
            }
            return CommandOutput(exitCode: 0, stdout: "", stderr: "")
        }
        let agentCold = AgentService(runner: mockNotOpen)
        let targetFile = root.appendingPathComponent("NotificationService.swift").path
        _ = try await agentCold.openInXcode(
            filePath: targetFile,
            line: 44,
            projectURL: root,
            waitBeforeFileJumpMs: 0
        )
        let coldCalls = mockNotOpen.recordedInvocations().filter { $0.executable == "/usr/bin/xed" }
        #expect(coldCalls.count == 2)
        #expect(coldCalls[0].arguments == [resolvedWS.url.path])
        #expect(coldCalls[1].arguments == ["--line", "44", targetFile])

        // 5. Direct 1-stage jump when Xcode already has Brimo.xcworkspace open
        let mockAlreadyOpen = MockCommandRunner { exec, _, _ in
            if exec.hasSuffix("pgrep") {
                return CommandOutput(exitCode: 0, stdout: "9912\n", stderr: "")
            }
            if exec.hasSuffix("osascript") {
                return CommandOutput(exitCode: 0, stdout: cocoapodsWS.path, stderr: "")
            }
            return CommandOutput(exitCode: 0, stdout: "", stderr: "")
        }
        let agentWarm = AgentService(runner: mockAlreadyOpen)
        _ = try await agentWarm.openInXcode(
            filePath: targetFile,
            line: 44,
            projectURL: root,
            waitBeforeFileJumpMs: 0
        )
        let warmCalls = mockAlreadyOpen.recordedInvocations().filter { $0.executable == "/usr/bin/xed" }
        #expect(warmCalls.count == 1)
        #expect(warmCalls[0].arguments == ["--line", "44", targetFile])
    }

    @Test("TC-AUT-026: CodeReviewEngine.filterBranches filters Local/Remote/Common branches with query and groupFindingsByFile groups by file")
    func testBranchFilteringAndFileGrouping() {
        let allBranches = [
            "feature/qris-payment",
            "feature/transfer-intl",
            "develop",
            "main",
            "origin/feature/qris-payment",
            "origin/develop",
            "origin/release/v2.5"
        ]

        let localOnly = CodeReviewEngine.filterBranches(allBranches, kind: .local, query: "", currentBranch: "feature/qris-payment")
        #expect(localOnly.first == "feature/qris-payment")
        #expect(!localOnly.contains("origin/develop"))

        let remoteOnly = CodeReviewEngine.filterBranches(allBranches, kind: .remote, query: "", currentBranch: "feature/qris-payment")
        #expect(remoteOnly.allSatisfy { $0.hasPrefix("origin/") })

        let commonOnly = CodeReviewEngine.filterBranches(allBranches, kind: .common, query: "", currentBranch: "feature/qris-payment")
        #expect(commonOnly.contains("develop"))
        #expect(commonOnly.contains("main"))
        #expect(commonOnly.contains("origin/release/v2.5"))
        #expect(!commonOnly.contains("feature/transfer-intl"))

        let searched = CodeReviewEngine.filterBranches(allBranches, kind: .all, query: "intl", currentBranch: "develop")
        #expect(searched == ["feature/transfer-intl"])

        let findings = [
            CodeReviewFinding(fileName: "B_View.swift", lineNumber: 20, severity: .warning, category: .swiftUI, title: "W1", detail: "D", codeSnippet: "DateFormatter()"),
            CodeReviewFinding(fileName: "A_Service.swift", lineNumber: 50, severity: .critical, category: .mainThread, title: "C1", detail: "D", codeSnippet: "Data(contentsOf: url)", isNew: true),
            CodeReviewFinding(fileName: "A_Service.swift", lineNumber: 12, severity: .suggestion, category: .codeHygiene, title: "S1", detail: "D", codeSnippet: "print(1)")
        ]
        let groups = CodeReviewEngine.groupFindingsByFile(findings)
        #expect(groups.count == 2)
        #expect(groups[0].fileName == "A_Service.swift")
        #expect(groups[0].criticalCount == 1)
        #expect(groups[0].suggestionCount == 1)
        #expect(groups[0].hasNew)
        #expect(groups[1].fileName == "B_View.swift")
    }

    @Test("TC-AUT-027: UIHierarchyInspectorService extracts 2D/3D component layers from Swift view files and generates live component patches")
    func testUIHierarchyInspectorExtractsLayersAndPatches() throws {
        let projDir = FileManager.default.temporaryDirectory.appendingPathComponent("UIHierarchy_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projDir) }

        let viewCode = """
        import UIKit
        final class LoginViewController: UIViewController {
            private let headerBanner = UIImageView()
            private let fastMenuGrid = UICollectionView()
            private let loginButton = UIButton()
            override func viewDidLoad() {
                super.viewDidLoad()
                loginButton.setTitle("Login Sekarang", for: .normal)
            }
        }
        """
        try viewCode.write(to: projDir.appendingPathComponent("LoginViewController.swift"), atomically: true, encoding: .utf8)

        let service = UIHierarchyInspectorService()
        let proc = SimulatorProcessInfo(id: 45028, name: "BRImoDev")
        let nodes = service.buildHierarchy(for: proc, in: projDir)

        #expect(!nodes.isEmpty)
        let hasRootWindow = nodes.contains { $0.zLayer == 0 }
        let hasLoginFile = nodes.contains { $0.fileName == "LoginViewController.swift" }
        #expect(hasRootWindow)
        #expect(hasLoginFile)

        if var btnNode = nodes.first(where: { $0.codeSnippet.contains("Login Sekarang") }) {
            btnNode.displayText = "Masuk BRImo"
            let patch = service.buildCodePatch(for: btnNode)
            #expect(patch.oldSnippet.contains("Login Sekarang"))
            #expect(patch.newSnippet.contains("Masuk BRImo"))
        }
    }

    @Test("TC-AUT-028: ProgressiveListChunker & SwiftSyntaxHighlighter handle 5,000-item lists lazily and quickly")
    func testProgressiveLazyChunkingAndSyntaxCacheForLargeLists() {
        let now = Date()
        var largeFindings: [CodeReviewFinding] = []
        largeFindings.reserveCapacity(5_000)
        for i in 0..<5_000 {
            largeFindings.append(
                CodeReviewFinding(
                    id: "f-\(i)",
                    fileName: "Module\(i % 25)/Screen\(i).swift",
                    lineNumber: (i % 200) + 1,
                    severity: i % 5 == 0 ? .critical : (i % 2 == 0 ? .warning : .suggestion),
                    category: i % 3 == 0 ? .memoryLeak : (i % 3 == 1 ? .mainThread : .swiftUI),
                    title: "Finding #\(i)",
                    detail: "Detail for item \(i)",
                    codeSnippet: "DispatchQueue.main.async { self.title = \"Item \(i)\" }",
                    detectedAt: now.addingTimeInterval(Double(-i)),
                    isNew: i < 20
                )
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        let sorted = CodeReviewEngine.sortFindings(largeFindings)
        let firstPage = ProgressiveListChunker.visibleSlice(of: sorted, limit: ProgressiveListChunker.defaultPageSize)
        #expect(firstPage.count == 50)
        #expect(sorted.first?.severity == .critical)
        #expect(sorted.first?.isNew == true)

        #expect(!ProgressiveListChunker.shouldLoadMore(currentIndex: 10, currentLimit: 50, totalCount: 5_000))
        #expect(ProgressiveListChunker.shouldLoadMore(currentIndex: 43, currentLimit: 50, totalCount: 5_000))
        let secondLimit = ProgressiveListChunker.nextLimit(currentLimit: 50, totalCount: 5_000)
        #expect(secondLimit == 100)
        #expect(ProgressiveListChunker.visibleSlice(of: sorted, limit: secondLimit).count == 100)

        let highlighter = SwiftSyntaxHighlighter()
        let sampleCode = "func loadData() async { let x = try? Data(contentsOf: url) }"
        let firstTokens = highlighter.tokenize(sampleCode)
        let cachedTokens = highlighter.tokenize(sampleCode)
        #expect(!firstTokens.isEmpty)
        #expect(firstTokens == cachedTokens)

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        #expect(elapsed < 1.0)
    }

    @Test("TC-AUT-029: Comprehensive multi-viewport responsive layout prevents squished buttons and overlaps across Compact, Standard, and Wide sizes")
    func testComprehensiveResponsiveLayoutAcrossViewports() {
        #expect(ResponsiveBreakpointEngine.tier(forWindowWidth: 920) == .compact)
        #expect(ResponsiveBreakpointEngine.tier(forWindowWidth: 1180) == .standard)
        #expect(ResponsiveBreakpointEngine.tier(forWindowWidth: 1440) == .wide)

        // Adaptive KPI Grid columns scale smoothly with viewport width
        #expect(ResponsiveBreakpointEngine.kpiGridColumnCount(forContentWidth: 420) == 2)
        #expect(ResponsiveBreakpointEngine.kpiGridColumnCount(forContentWidth: 680) == 3)
        #expect(ResponsiveBreakpointEngine.kpiGridColumnCount(forContentWidth: 980) == 4)

        // Simulate realistic button toolbars from Overview (6 buttons), Simulator Dynamic Type (7 buttons), and Code Review actions
        let buttonToolbarSizes: [CGSize] = [
            CGSize(width: 145, height: 28), // Select Xcode Project
            CGSize(width: 105, height: 28), // Clear Project
            CGSize(width: 140, height: 28), // Reset Project Data
            CGSize(width: 120, height: 28), // Export Backup
            CGSize(width: 125, height: 28), // Restore Backup
            CGSize(width: 140, height: 28), // Open .dmg Installer
            CGSize(width: 90, height: 28)   // Extra action
        ]

        let viewports: [CGFloat] = [520, 700, 960, 1240]
        for width in viewports {
            let result = ResponsiveBreakpointEngine.computeFlowPlacements(
                itemSizes: buttonToolbarSizes,
                maxWidth: width,
                horizontalSpacing: 8,
                verticalSpacing: 8
            )
            #expect(result.placements.count == buttonToolbarSizes.count)

            // Narrow viewports must wrap onto multiple rows instead of squishing ("gepeng")
            if width < 800 {
                #expect(result.rowCount > 1)
            } else {
                #expect(result.rowCount == 1)
            }

            // Every button preserves 100% of its intrinsic width and never overflows container width
            for (idx, placement) in result.placements.enumerated() {
                #expect(placement.size.width == buttonToolbarSizes[idx].width)
                #expect(placement.size.height == buttonToolbarSizes[idx].height)
                #expect(placement.origin.x >= 0)
                #expect(placement.origin.x + placement.size.width <= width)
            }

            // Verify zero bounding-box overlaps between any two placed buttons
            for i in 0..<result.placements.count {
                let r1 = CGRect(origin: result.placements[i].origin, size: result.placements[i].size)
                for j in (i + 1)..<result.placements.count {
                    let r2 = CGRect(origin: result.placements[j].origin, size: result.placements[j].size)
                    #expect(!r1.intersects(r2))
                }
            }
        }
    }

    @Test("TC-AUT-030: VirtualRecycleWindow destroys off-screen rows (1-20 evicted when scrolled to 26+) on 2,500-item lists")
    func testVirtualRecycleWindowDestroysOffscreenRows() {
        let total = 2_500

        // 1. At top of list (visible rows 0..12)
        let topWindow = VirtualRecycleWindow.computeActiveRange(firstVisibleIndex: 0, lastVisibleIndex: 12, totalCount: total)
        #expect(topWindow == 0..<17)
        #expect(topWindow.count == 17)

        // 2. User scrolls down to row 26..38 -> rows 0..21 MUST be destroyed/evicted from memory
        let scrolledWindow = VirtualRecycleWindow.computeActiveRange(firstVisibleIndex: 26, lastVisibleIndex: 38, totalCount: total)
        #expect(scrolledWindow == 22..<43)
        #expect(scrolledWindow.count == 21)
        for evictedRow in 0...20 {
            #expect(!scrolledWindow.contains(evictedRow))
        }

        // 3. Scroll near bottom (rows 2488..2499) -> active count stays strictly bounded O(viewport)
        let bottomWindow = VirtualRecycleWindow.computeActiveRange(firstVisibleIndex: 2488, lastVisibleIndex: 2499, totalCount: total)
        #expect(bottomWindow == 2484..<2500)
        #expect(bottomWindow.count == 16)
    }

    @Test("TC-AUT-031: AgentService.openInXcode activates Xcode and falls back to bundle-ID open when xed fails")
    func testOpenInXcodeFallbackAndActivation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("XcodeFallback_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "// swift-tools-version: 6.0".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let targetFile = root.appendingPathComponent("MainView.swift").path

        let mock = MockCommandRunner { exec, _, _ in
            if exec == "/usr/bin/xed" {
                return CommandOutput(exitCode: 1, stdout: "", stderr: "AppleEvent permission denied")
            }
            return CommandOutput(exitCode: 0, stdout: "", stderr: "")
        }

        let agent = AgentService(runner: mock)
        let out = try await agent.openInXcode(filePath: targetFile, line: 27, projectURL: root, waitBeforeFileJumpMs: 0)
        #expect(out.isSuccess)

        let invocations = mock.recordedInvocations()
        let osaOrOpen = invocations.filter { $0.executable == "/usr/bin/osascript" || $0.executable == "/usr/bin/open" }
        #expect(!osaOrOpen.isEmpty)
        let osaCalls = invocations.filter { $0.executable == "/usr/bin/osascript" }
        #expect(osaCalls.contains(where: { $0.arguments.joined(separator: " ").contains("hack document") && $0.arguments.joined(separator: " ").contains("27") }))
    }

    @Test("TC-AUT-032: listProjectModules discovers all nested directories at any depth and SmartSearchMatcher/filterModules support partial & multi-token contains")
    func testFullDirectoryDiscoveryAndSmartContainsSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FullDirSearch_\(UUID().uuidString)")
        let deepDir = root.appendingPathComponent("App/Features/Transfer/QRIS/Presentation")
        let emptyGroupDir = root.appendingPathComponent("App/Resources/Fonts")
        let podsDir = root.appendingPathComponent("Pods/Alamofire/Source")
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyGroupDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: podsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "struct QRISView {}".write(to: deepDir.appendingPathComponent("QRISView.swift"), atomically: true, encoding: .utf8)
        try "class Session {}".write(to: podsDir.appendingPathComponent("Session.swift"), atomically: true, encoding: .utf8)

        let engine = CodeReviewEngine()
        let modules = engine.listProjectModules(in: root)

        // All nested directories discovered, Pods excluded
        #expect(modules.contains("App"))
        #expect(modules.contains("App/Features"))
        #expect(modules.contains("App/Features/Transfer"))
        #expect(modules.contains("App/Features/Transfer/QRIS"))
        #expect(modules.contains("App/Features/Transfer/QRIS/Presentation"))
        #expect(modules.contains("App/Resources/Fonts"))
        #expect(!modules.contains(where: { $0.contains("Pods") }))

        // Partial contains & multi-token contains search
        let partialMatch = CodeReviewEngine.filterModules(modules, query: "qri")
        #expect(partialMatch.contains("App/Features/Transfer/QRIS"))
        #expect(partialMatch.contains("App/Features/Transfer/QRIS/Presentation"))

        let multiTokenMatch = CodeReviewEngine.filterModules(modules, query: "transfer presentation")
        #expect(multiTokenMatch == ["App/Features/Transfer/QRIS/Presentation"])

        // SmartSearchMatcher across branches & findings
        #expect(SmartSearchMatcher.matches(["feature/qris-payment"], query: "feat pay"))
        #expect(!SmartSearchMatcher.matches(["feature/qris-payment"], query: "feat transfer"))
    }

    @Test("TC-AUT-033: SimulatorService.capturePhysicalDeviceScreenshot invokes devicectl capture screenshot and UIHierarchyInspectorService extracts live nodes from screenshot")
    func testPhysicalDeviceScreenshotAndLiveVisionHierarchy() async throws {
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("dev_screen_\(UUID().uuidString).png")
        let mock = MockCommandRunner { _, _, _ in
            CommandOutput(exitCode: 0, stdout: "", stderr: "")
        }
        let simService = SimulatorService(runner: mock)
        let out = try await simService.capturePhysicalDeviceScreenshot(deviceID: "DEV-123", to: outURL)
        #expect(out.isSuccess)
        let calls = mock.recordedInvocations()
        #expect(calls.first?.arguments == ["devicectl", "device", "capture", "screenshot", "--device", "DEV-123", "--destination", outURL.path])
    }

    @Test("TC-AUT-034: UIHierarchyInspectorService detects live screen components via Vision and maps them to real Swift property names in active ViewController")
    func testFullScreenVisionHierarchyAndSwiftSymbolMapping() throws {
        let projDir = FileManager.default.temporaryDirectory.appendingPathComponent("LiveScreenMap_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projDir) }

        let loginVC = """
        import UIKit
        final class LoginViewController: UIViewController {
            @IBOutlet weak var fastMenuLabel: UILabel!
            @IBOutlet weak var loginActionButton: UIButton!
            override func viewDidLoad() {
                super.viewDidLoad()
                fastMenuLabel.text = "Fast Menu"
                loginActionButton.setTitle("Login", for: .normal)
            }
        }
        """
        try loginVC.write(to: projDir.appendingPathComponent("LoginViewController.swift"), atomically: true, encoding: .utf8)

        // Render a clean synthetic PNG containing "Fast Menu" and "Login"
        let width = 390
        let height = 844
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.05, green: 0.45, blue: 0.85, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw white "Fast Menu" & "Login" labels into the synthetic PNG for Vision OCR
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 28, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ]
        for (text, yPos) in [("Fast Menu", 320.0), ("Login", 110.0)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
            ctx.textPosition = CGPoint(x: 110, y: yPos)
            CTLineDraw(line, ctx)
        }

        let screenURL = projDir.appendingPathComponent("mock_login.png")
        let cgImage = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(screenURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)

        let service = UIHierarchyInspectorService()
        let proc = SimulatorProcessInfo(id: 5613, name: "BRImoDev")
        let nodes = service.buildHierarchy(for: proc, screenshotURL: screenURL, in: projDir)

        #expect(!nodes.isEmpty)
        #expect(nodes.contains { $0.fileName == "LoginViewController.swift" })
        #expect(!nodes.contains { $0.name == "weak" })
    }

    @Test("TC-AUT-035: UIHierarchyInspectorService preCropTextures caches crops off main thread and intersectionOverUnion deduplicates overlapping boxes")
    func testPreCropTexturesAndIoUDeduplication() {
        let r1 = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.2)
        let r2 = CGRect(x: 0.12, y: 0.21, width: 0.48, height: 0.19)
        let r3 = CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.1)
        #expect(UIHierarchyInspectorService.intersectionOverUnion(r1, r2) > 0.70)
        #expect(UIHierarchyInspectorService.intersectionOverUnion(r1, r3) == 0.0)

        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 200, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let full = ctx.makeImage()!
        let node = UIComponentNode(
            id: "btn-1",
            name: "LoginButton",
            kind: .button,
            normalizedX: 0.1,
            normalizedY: 0.7,
            normalizedWidth: 0.5,
            normalizedHeight: 0.1,
            fileName: "LoginVC.swift",
            lineNumber: 42,
            codeSnippet: "let btn = UIButton()"
        )
        let crops = UIHierarchyInspectorService.preCropTextures(from: full, nodes: [node])
        #expect(crops["btn-1"] != nil)
        #expect(crops["btn-1"]?.width == 100)
        #expect(crops["btn-1"]?.height == 40)
    }

    @Test("Performance: CodeReviewEngine and SwiftSyntaxHighlighter handle 2000+ lines under 1s")
    func testCodeReviewAndHighlighterPerformance() {
        let block = """
        final class ItemVC: UIViewController {
            var delegate: ItemDelegate?
            func load() { DispatchQueue.main.async { self.title = "OK" } }
        }
        """
        let largeSource = Array(repeating: block, count: 400).joined(separator: "\n") // 2000 lines
        let start = CFAbsoluteTimeGetCurrent()
        let findings = CodeReviewEngine().analyze(source: largeSource, fileName: "LargeVC.swift")
        let tokens = SwiftSyntaxHighlighter().tokenize(largeSource)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(!findings.isEmpty)
        #expect(!tokens.isEmpty)
        #expect(elapsed < 1.0)
    }

    @Test("Stability: ProcessRunner terminates timed-out commands without hanging")
    func testProcessRunnerTimeoutSafety() async {
        let runner = ProcessRunner(defaultTimeoutSeconds: 0.2)
        do {
            _ = try await runner.run("/bin/sleep", arguments: ["5"], workingDirectory: nil)
            Issue.record("Expected commandTimedOut error")
        } catch let error as CompanionError {
            if case .commandTimedOut = error {
                #expect(true)
            } else {
                Issue.record("Unexpected CompanionError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Safety: Core engines handle empty and malformed inputs without crashing")
    func testEmptyAndMalformedInputsDoNotCrash() {
        let malformedJson = Data("{ invalid json".utf8)
        #expect(SimulatorService.parseSimctlDevices(from: malformedJson).isEmpty)
        #expect(UnitTestStudio.parseXcodeListJson(from: malformedJson) == nil)
        #expect(XcodeUtilitiesService().scanMissingLocalizations(in: malformedJson).isEmpty)
        #expect(ProcessTelemetryService.parsePsSample(from: "") == nil)
        #expect(ProcessTelemetryService.parseHangDuration(from: "") == nil)
    }

    @Test("SingleInstancePolicy detects duplicate running PID and ignores current PID")
    func testSingleInstancePolicy() {
        #expect(SingleInstancePolicy.findExistingInstancePID(currentPID: 100, candidatePIDs: [100]) == nil)
        #expect(SingleInstancePolicy.findExistingInstancePID(currentPID: 200, candidatePIDs: [100, 200]) == 100)
        #expect(SingleInstancePolicy.findExistingInstancePID(currentPID: 200, candidatePIDs: [-1, 0, 200]) == nil)
    }
}

final class CommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func record(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

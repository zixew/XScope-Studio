import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import DevCompanionCore

@Suite("Simulator XIB Inspector, Constraints & Action Runner Tests")
struct SimulatorXIBAndActionTests {
    @Test("UIHierarchyInspectorService parses AutoLayout & SnapKit constraints and patches constants")
    func parsesAndPatchesConstraints() {
        let source = """
        final class PromoCardView: UIView {
            func setup() {
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16).isActive = true
                titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12).isActive = true
                titleLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
                ctaButton.cornerRadius = 8
            }
        }
        """
        let service = UIHierarchyInspectorService()
        let parsed = service.parseConstraints(in: source)
        #expect(parsed.leading == 16)
        #expect(parsed.top == 12)
        #expect(parsed.height == 44)

        var node = UIComponentNode(
            name: "titleLabel",
            kind: .label,
            normalizedX: 0.1,
            normalizedY: 0.1,
            normalizedWidth: 0.8,
            normalizedHeight: 0.1,
            fileName: "PromoCardView.swift",
            lineNumber: 3,
            codeSnippet: "titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16).isActive = true",
            constraints: ComponentConstraints(leading: 24)
        )
        node.constraints.leading = 24
        let patch = service.buildCodePatch(for: node)
        #expect(patch.newSnippet.contains("constant: 24"))
        #expect(!patch.newSnippet.contains("constant: 16"))
    }

    @Test("UIHierarchyInspectorService discovers @IBAction, addTarget #selector, gestures, and SwiftUI Button actions")
    func discoversComponentActions() {
        let source = """
        final class LoginVC: UIViewController {
            override func viewDidLoad() {
                loginButton.addTarget(self, action: #selector(handleLoginTap), for: .touchUpInside)
                cardView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleCardTap)))
            }

            @IBAction func didTapForgotPassword(_ sender: UIButton) {
                presenter.openForgotPassword()
            }
        }
        struct QuickRow: View {
            var body: some View {
                Button("Continue") {
                    print("next")
                }
            }
        }
        """
        let actions = UIHierarchyInspectorService().discoverActions(in: source)
        #expect(actions.contains(where: { $0.kind == .addTarget && $0.selectorName == "handleLoginTap" }))
        #expect(actions.contains(where: { $0.kind == .gesture && $0.selectorName == "handleCardTap" }))
        #expect(actions.contains(where: { $0.kind == .ibAction && $0.selectorName == "didTapForgotPassword" }))
        #expect(actions.contains(where: { $0.kind == .swiftUIButton && $0.name == "Continue" }))

        // Non-interactive views (e.g. UILabel / UIImageView) must NOT show unrelated ViewController actions
        let labelActions = UIHierarchyInspectorService().discoverActions(in: source, componentName: "titleLabel", displayText: "BRIVA", kind: .label)
        #expect(labelActions.isEmpty)
    }

    @Test("UIHierarchyInspectorService bidirectional live component code updates node properties and constraints")
    func bidirectionalLiveComponentCode() {
        let service = UIHierarchyInspectorService()
        let node = UIComponentNode(
            name: "loginButton",
            kind: .button,
            normalizedX: 0.1,
            normalizedY: 0.8,
            normalizedWidth: 0.8,
            normalizedHeight: 0.08,
            fileName: "LoginVC.swift",
            lineNumber: 42,
            codeSnippet: "let loginButton = UIButton()",
            displayText: "Login",
            accentHex: "#007AFF",
            cornerRadius: 12,
            fontSize: 14,
            opacity: 1.0
        )
        let generated = service.generateLiveComponentCode(for: node)
        #expect(generated.contains("view.text = \"Login\""))
        #expect(generated.contains("view.layer.cornerRadius = 12"))

        let editedCode = generated
            .replacingOccurrences(of: "view.text = \"Login\"", with: "view.text = \"Masuk Sekarang\"")
            .replacingOccurrences(of: "view.layer.cornerRadius = 12", with: "view.layer.cornerRadius = 22")
            .replacingOccurrences(of: "constraint.top = nil", with: "constraint.top = 36")

        let updated = service.applyLiveComponentCode(editedCode, to: node)
        #expect(updated.displayText == "Masuk Sekarang")
        #expect(updated.cornerRadius == 22)
        #expect(updated.constraints.top == 36)
    }

    @Test("XScopeDebugBridgeService generates #if DEBUG bridge with invoke, mutate, and hierarchy endpoints")
    func generatesDebugBridge() {
        let code = XScopeDebugBridgeService.generateBridgeSwiftSource(port: 49876)
        #expect(code.contains("#if DEBUG"))
        #expect(code.contains("final class XScopeDebugBridge"))
        #expect(code.contains("GET /hierarchy"))
        #expect(code.contains("POST /invoke"))
        #expect(code.contains("POST /mutate"))
        #expect(code.contains("#endif"))
    }

    @Test("UIHierarchyInspectorService builds root-to-leaf tree including UITableView, UICollectionView, UIStackView, and Cells")
    func buildsFullHierarchyTree() {
        let nodes = [
            UIComponentNode(id: "win", name: "AppWindow", kind: .window, zLayer: 0, normalizedX: 0, normalizedY: 0, normalizedWidth: 1, normalizedHeight: 1, fileName: "App.swift", lineNumber: 1, codeSnippet: "UIWindow()"),
            UIComponentNode(id: "tbl", name: "mainTableView", kind: .tableView, zLayer: 1, normalizedX: 0.05, normalizedY: 0.1, normalizedWidth: 0.9, normalizedHeight: 0.8, fileName: "HomeVC.swift", lineNumber: 12, codeSnippet: "let mainTableView = UITableView()"),
            UIComponentNode(id: "cell", name: "LoanRowCell", kind: .cell, zLayer: 2, normalizedX: 0.08, normalizedY: 0.15, normalizedWidth: 0.84, normalizedHeight: 0.12, fileName: "LoanRowCell.swift", lineNumber: 8, codeSnippet: "class LoanRowCell: UITableViewCell"),
            UIComponentNode(id: "lbl", name: "amountLabel", kind: .label, zLayer: 3, normalizedX: 0.1, normalizedY: 0.17, normalizedWidth: 0.4, normalizedHeight: 0.05, fileName: "LoanRowCell.swift", lineNumber: 14, codeSnippet: "let amountLabel = UILabel()")
        ]
        let tree = UIHierarchyInspectorService.buildHierarchyTree(from: nodes)
        #expect(tree.count == 4)
        #expect(tree[0].id == "win" && tree[0].depth == 0 && tree[0].parentID == nil)
        #expect(tree[1].id == "tbl" && tree[1].depth == 1 && tree[1].parentID == "win")
        #expect(tree[2].id == "cell" && tree[2].depth == 2 && tree[2].parentID == "tbl")
        #expect(tree[3].id == "lbl" && tree[3].depth == 3 && tree[3].parentID == "cell")

        // Verify stepped non-colliding planeIndex from back containers to foreground leaf
        #expect(tree[0].planeIndex < tree[1].planeIndex)
        #expect(tree[1].planeIndex < tree[2].planeIndex)
        #expect(tree[2].planeIndex < tree[3].planeIndex)

        // Verify breadcrumb jump bar chain
        let crumbs = UIHierarchyInspectorService.ancestorBreadcrumb(for: "lbl", in: tree)
        #expect(crumbs.map(\.id) == ["win", "tbl", "cell", "lbl"])
    }

    @Test("ProcessTelemetryService 2-step filter requires target device first and shows only opened user app")
    func filtersOpenedAppPerTargetDevice() {
        let psOut = """
          501 /Users/dev/Library/Developer/CoreSimulator/Devices/SIM-111/data/Containers/Bundle/Application/A1/BRImoDev.app/BRImoDev
          502 /Users/dev/Library/Developer/CoreSimulator/Devices/SIM-111/data/Containers/Bundle/Application/A1/BRImoDev.app/PlugIns/Widget.appex/Widget
          503 /Library/Developer/CoreSimulator/Volumes/iOS_21A/RuntimeRoot/Applications/MobileSafari.app/MobileSafari
          601 /Users/dev/Library/Developer/CoreSimulator/Devices/SIM-222/data/Containers/Bundle/Application/B2/OtherSimApp.app/OtherSimApp
        """
        var allProcs = ProcessTelemetryService.parseSimulatorProcesses(from: psOut)
        allProcs.append(SimulatorProcessInfo(id: 901, name: "BRImoDev", deviceID: "IPHONE-1", deviceName: "iPhone 16", isUserApp: true))

        // Before selecting any target device/simulator -> empty
        let noneSelected = ProcessTelemetryService.filterOpenedAppsForTarget(allProcs, targetID: nil, isPhysicalDevice: false)
        #expect(noneSelected.isEmpty)

        // Step 1: Select Simulator SIM-111 -> only BRImoDev (excludes Widget.appex, MobileSafari system app, and SIM-222 / iPhone apps)
        let sim111Apps = ProcessTelemetryService.filterOpenedAppsForTarget(allProcs, targetID: "SIM-111", isPhysicalDevice: false, projectName: "Brimo-ios")
        #expect(sim111Apps.count == 1)
        #expect(sim111Apps.first?.id == 501)
        #expect(sim111Apps.first?.name == "BRImoDev")

        // Step 1: Select Physical Device IPHONE-1 -> only PID 901 on IPHONE-1
        let deviceApps = ProcessTelemetryService.filterOpenedAppsForTarget(allProcs, targetID: "IPHONE-1", isPhysicalDevice: true)
        #expect(deviceApps.count == 1)
        #expect(deviceApps.first?.id == 901)
    }

    @Test("ProcessTelemetryService filters out non-developer background apps (Discord, WhatsApp, Photos) and PhysicalDevice distinguishes USB vs Wi-Fi")
    func filtersDeveloperAppsAndWiredUSB() {
        let appsJSON = """
        {
          "result": {
            "apps": [
              { "builtByDeveloper": true, "name": "BRImoOCP", "url": "file:///private/var/containers/Bundle/Application/111/BRImoOCP.app/" },
              { "builtByDeveloper": false, "name": "WhatsApp", "url": "file:///private/var/containers/Bundle/Application/222/WhatsApp.app/" }
            ]
          }
        }
        """.data(using: .utf8)!
        let allowed = ProcessTelemetryService.parseDeveloperAppNames(from: appsJSON)
        #expect(allowed.contains("brimoocp"))
        #expect(!allowed.contains("whatsapp"))

        let procsJSON = """
        {
          "result": {
            "runningProcesses": [
              { "processIdentifier": 9247, "executable": "file:///private/var/containers/Bundle/Application/A/Discord.app/Discord" },
              { "processIdentifier": 9298, "executable": "file:///private/var/containers/Bundle/Application/B/Photos.app/Photos" },
              { "processIdentifier": 9242, "executable": "file:///private/var/containers/Bundle/Application/C/WhatsApp.app/WhatsApp" },
              { "processIdentifier": 9500, "executable": "file:///private/var/containers/Bundle/Application/111/BRImoOCP.app/BRImoOCP" }
            ]
          }
        }
        """.data(using: .utf8)!

        let filtered = ProcessTelemetryService.parsePhysicalDeviceProcesses(
            from: procsJSON,
            deviceID: "DEV-1",
            deviceName: "iPhone 11",
            allowedDeveloperApps: allowed
        )
        #expect(filtered.count == 1)
        #expect(filtered.first?.name == "BRImoOCP")

        let usbDev = PhysicalDevice(id: "U1", name: "iPhone 15", osVersion: "18.1", connectionType: "wired")
        let wifiDev = PhysicalDevice(id: "W1", name: "BRI iPhone 11", osVersion: "16.1", connectionType: "localNetwork")
        #expect(usbDev.isWiredUSB == true && usbDev.connectionBadge == "USB")
        #expect(wifiDev.isWiredUSB == false && wifiDev.connectionBadge == "Wi-Fi")
    }

    @Test("UIHierarchyInspectorService detects iOS SpringBoard Home Screen and ProcessTelemetryService detects display backlight off")
    func detectsHomeScreenAndDisplayBacklight() {
        let homeTexts = ["Find My", "Shortcuts", "Files", "Contacts", "WhatsApp", "BCA mobile", "Shopee", "ChatGPT", "Music"]
        #expect(UIHierarchyInspectorService.isSpringBoardHomeScreen(visibleTexts: homeTexts) == true)

        let inAppTexts = ["Fast Menu", "QRIS", "BRIZZI", "E Wallet", "BRIVA", "Login"]
        #expect(UIHierarchyInspectorService.isSpringBoardHomeScreen(visibleTexts: inAppTexts) == false)

        let offJSON = #"{"result":{"backlightState":"off"}}"#.data(using: .utf8)!
        let onJSON = #"{"result":{"backlightState":"on"}}"#.data(using: .utf8)!
        #expect(ProcessTelemetryService.parseDisplayBacklightOn(from: offJSON) == false)
        #expect(ProcessTelemetryService.parseDisplayBacklightOn(from: onJSON) == true)
    }

    @Test("Privacy Guard enforces fail-closed Xcode-built/debugged apps and blocks non-Xcode/private foreground screens")
    func enforcesXcodeOnlyPrivacyGuard() {
        let procsJSON = """
        {
          "result": {
            "runningProcesses": [
              { "processIdentifier": 410, "executable": "file:///Developer/usr/libexec/debugserver" },
              { "processIdentifier": 9242, "executable": "file:///private/var/containers/Bundle/Application/C/WhatsApp.app/WhatsApp" },
              { "processIdentifier": 9301, "executable": "file:///private/var/containers/Bundle/Application/D/PrivateBankApp.app/PrivateBankApp" },
              { "processIdentifier": 9500, "executable": "file:///private/var/containers/Bundle/Application/111/BRImoDev.app/BRImoDev" }
            ]
          }
        }
        """.data(using: .utf8)!

        // 1. Fail-closed: when allowedDeveloperApps is empty, zero apps leak through (even if not in static blocklist)
        let failClosed = ProcessTelemetryService.parsePhysicalDeviceProcesses(
            from: procsJSON,
            deviceID: "DEV-1",
            deviceName: "iPhone 12",
            allowedDeveloperApps: []
        )
        #expect(failClosed.isEmpty)

        // 2. When BRImoDev is builtByDeveloper == true and debugserver is active, only BRImoDev is returned and tagged [XCODE DEBUG]
        let verified = ProcessTelemetryService.parsePhysicalDeviceProcesses(
            from: procsJSON,
            deviceID: "DEV-1",
            deviceName: "iPhone 12",
            allowedDeveloperApps: ["brimodev"]
        )
        #expect(verified.count == 1)
        #expect(verified.first?.name == "BRImoDev")
        #expect(verified.first?.isBuiltByXcode == true)
        #expect(verified.first?.isBeingDebuggedByXcode == true)
        #expect(verified.first?.xcodePrivacyBadge == "[XCODE DEBUG]")

        // 3. If open Xcode project is "Brimo-ios", an unrelated app on the target without debugserver is blocked
        let mixedProcs = [
            SimulatorProcessInfo(id: 1, name: "UnrelatedDevApp", deviceID: "DEV-1", deviceName: "iPhone 12", isUserApp: true, isBuiltByXcode: true, isBeingDebuggedByXcode: false),
            SimulatorProcessInfo(id: 2, name: "BRImoDev", deviceID: "DEV-1", deviceName: "iPhone 12", isUserApp: true, isBuiltByXcode: true, isBeingDebuggedByXcode: false)
        ]
        let scoped = ProcessTelemetryService.filterOpenedAppsForTarget(
            mixedProcs,
            targetID: "DEV-1",
            isPhysicalDevice: true,
            projectName: "Brimo-ios"
        )
        #expect(scoped.map(\.name) == ["BRImoDev"])

        // 4. Xcode Object & Size Inspector helpers: class inheritance chain, point frame/bounds, and subtree isolation
        let chain = UIHierarchyInspectorService.classInheritanceChain(for: .button, className: "ActionButton")
        #expect(chain == ["ActionButton", "UIButton", "UIControl", "UIView", "UIResponder", "NSObject"])

        let sampleNode = UIComponentNode(
            id: "root",
            name: "LoginButton",
            kind: .button,
            normalizedX: 0.1,
            normalizedY: 0.5,
            normalizedWidth: 0.8,
            normalizedHeight: 0.1,
            fileName: "LoginVC.swift",
            lineNumber: 10,
            codeSnippet: "UIButton()"
        )
        let metrics = UIHierarchyInspectorService.pointFrameAndBounds(for: sampleNode, screenWidthPt: 390, screenHeightPt: 844)
        #expect(metrics.frame.origin.x == 39)
        #expect(metrics.frame.origin.y == 422)
        #expect(metrics.bounds.origin.x == 0 && metrics.bounds.origin.y == 0)

        let treeNodes = [
            sampleNode,
            UIComponentNode(id: "child-1", parentID: "root", name: "TitleLabel", kind: .label, normalizedX: 0.2, normalizedY: 0.5, normalizedWidth: 0.4, normalizedHeight: 0.05, fileName: "LoginVC.swift", lineNumber: 12, codeSnippet: "UILabel()"),
            UIComponentNode(id: "other", parentID: nil, name: "OtherView", kind: .cardContainer, normalizedX: 0, normalizedY: 0, normalizedWidth: 1, normalizedHeight: 0.2, fileName: "LoginVC.swift", lineNumber: 20, codeSnippet: "UIView()")
        ]
        let subtree = UIHierarchyInspectorService.subtreeNodeIDs(rootedAt: "root", in: treeNodes)
        #expect(subtree == Set(["root", "child-1"]))
    }

    @Test("UIHierarchyInspectorService.decodeImageInMemory retains full pixel data after temp screenshot file is deleted")
    func decodeImageInMemorySurvivesFileDeletion() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("xscope_mem_test_\(UUID().uuidString).png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 40,
            height: 80,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let sampleCG = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, "public.png" as CFString, 1, nil)
        else {
            Issue.record("Failed to create test PNG")
            return
        }
        CGImageDestinationAddImage(dest, sampleCG, nil)
        #expect(CGImageDestinationFinalize(dest))

        let decoded = UIHierarchyInspectorService.decodeImageInMemory(from: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        #expect(decoded != nil)
        #expect(decoded?.width == 40)
        #expect(decoded?.height == 80)
        #expect(decoded?.dataProvider?.data != nil)

        let leaf = UIComponentNode(
            id: "leaf-1",
            name: "CTA",
            kind: .button,
            normalizedX: 0.1,
            normalizedY: 0.1,
            normalizedWidth: 0.8,
            normalizedHeight: 0.5,
            fileName: "Test.swift",
            lineNumber: 1,
            codeSnippet: "UIButton()"
        )
        let crops = decoded.map { UIHierarchyInspectorService.preCropTextures(from: $0, nodes: [leaf]) } ?? [:]
        #expect(crops["leaf-1"] != nil)
    }

    @Test("TC-AUT-027: DiagnosticService filters out consumer third-party apps (WhatsApp, Discord) for Developer Apps Only policy")
    func testDiagnosticServiceFiltersThirdPartyApps() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DevAppsOnly_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "crash".write(to: dir.appendingPathComponent("WhatsApp-2026-11-27-100000.ips"), atomically: true, encoding: .utf8)
        try "crash".write(to: dir.appendingPathComponent("Discord-2026-11-27-100001.ips"), atomically: true, encoding: .utf8)
        try "crash".write(to: dir.appendingPathComponent("BRImoDev-2026-11-27-100002.ips"), atomically: true, encoding: .utf8)

        let svc = DiagnosticService()
        // When includeSystemReports is false, WhatsApp and Discord are in nonDeveloperAppBlocklist and get excluded
        let filtered = svc.loadRecentReports(
            projectName: "Brimo-ios",
            simulatorAppNames: ["BRImoDev"],
            allowedDeveloperAppNames: ["brimodev"],
            includeSystemReports: false,
            directory: dir
        )
        #expect(filtered.count == 1)
        #expect(filtered.first?.processName == "BRImoDev")
    }

    @Test("TC-AUT-028: UIHierarchyInspectorService detects SpringBoard Home Screen with token matching and prevents privacy leakage")
    func testSpringBoardHomeScreenFuzzyDetection() {
        // Sample OCR tokens typical of iOS Home Screen (as shown in user screenshot)
        let homeScreenTokens = [
            "Find My", "WhatsApp", "Shopee", "Google Calendar", "BCA mobile",
            "Access By KAI", "ChatGPT", "Photos", "App Store"
        ]
        #expect(UIHierarchyInspectorService.isSpringBoardHomeScreen(visibleTexts: homeScreenTokens))

        // Single isolated match should NOT trigger false positive
        let inAppTokens = ["OpenDPLKConfirmationVC Window", "SectionCardContainer", "Konfirmasi", "Lanjut", "Nominal Rp 50.000"]
        #expect(!UIHierarchyInspectorService.isSpringBoardHomeScreen(visibleTexts: inAppTokens))
    }
}

import Foundation
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
        let actions = UIHierarchyInspectorService().discoverActions(in: source, componentName: "loginButton")
        #expect(actions.contains(where: { $0.kind == .addTarget && $0.selectorName == "handleLoginTap" }))
        #expect(actions.contains(where: { $0.kind == .gesture && $0.selectorName == "handleCardTap" }))
        #expect(actions.contains(where: { $0.kind == .ibAction && $0.selectorName == "didTapForgotPassword" }))
        #expect(actions.contains(where: { $0.kind == .swiftUIButton && $0.name == "Continue" }))
    }

    @Test("XScopeDebugBridgeService generates #if DEBUG bridge with invoke and mutate endpoints")
    func generatesDebugBridge() {
        let code = XScopeDebugBridgeService.generateBridgeSwiftSource(port: 49876)
        #expect(code.contains("#if DEBUG"))
        #expect(code.contains("final class XScopeDebugBridge"))
        #expect(code.contains("POST /invoke"))
        #expect(code.contains("POST /mutate"))
        #expect(code.contains("#endif"))
    }
}

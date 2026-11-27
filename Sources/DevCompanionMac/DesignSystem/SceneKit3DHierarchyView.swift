import SwiftUI
import SceneKit
import AppKit
import DevCompanionCore

public enum HierarchyDisplayMode: String, CaseIterable, Sendable, Identifiable {
    case wireframes = "Wireframes"
    case wireframesAndContents = "Both"
    case contents = "Contents"

    public var id: String { rawValue }
}

/// Metal GPU-accelerated 120fps 3D Debug View Hierarchy modeled after Xcode's View Debugger:
/// - Stepped structural container backing planes (matte light/slate cards + dark Top Header Tab with C/V icon) — never duplicating full-screen screenshot pixels.
/// - Intermediate wireframe subview layout grid planes.
/// - Isolated foreground leaf visual elements rendering their cropped pixel content + Xcode sky-blue selection outline.
struct SceneKit3DHierarchyView: NSViewRepresentable {
    let nodes: [UIComponentNode]
    let fullScreenImage: CGImage?
    let croppedTextures: [String: CGImage]
    let selectedNodeID: String?
    let layerSpacing: Double
    let displayMode: HierarchyDisplayMode
    let showLabels: Bool
    let zoomScale: Double
    let minDepthRatio: Double
    let maxDepthRatio: Double
    let resetTrigger: Int
    let onSelectNode: (UIComponentNode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectNode: onSelectNode)
    }

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.rendersContinuously = false

        let scene = SCNScene()
        scnView.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 36
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 120
        cameraNode.position = SCNVector3(0, 0, 12.5)
        scene.rootNode.addChildNode(cameraNode)
        context.coordinator.cameraNode = cameraNode

        let pivot = SCNNode()
        // Signature Xcode View Debugger angled isometric-perspective stance
        pivot.eulerAngles = SCNVector3(CGFloat(0.08), CGFloat(-0.52), 0)
        scene.rootNode.addChildNode(pivot)
        context.coordinator.pivotNode = pivot
        context.coordinator.scnView = scnView

        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(pan)

        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(click)

        let mag = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        scnView.addGestureRecognizer(mag)

        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectNode = onSelectNode
        coordinator.nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        if coordinator.lastResetTrigger != resetTrigger {
            coordinator.lastResetTrigger = resetTrigger
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            coordinator.pivotNode?.eulerAngles = SCNVector3(CGFloat(0.08), CGFloat(-0.52), 0)
            let resetZ = CGFloat(12.5) / max(0.5, CGFloat(zoomScale))
            coordinator.cameraNode?.position = SCNVector3(0, 0, resetZ)
            SCNTransaction.commit()
        } else {
            let targetZ = CGFloat(12.5) / max(0.5, CGFloat(zoomScale))
            let currentZ = coordinator.cameraNode?.position.z ?? CGFloat(12.5)
            if abs(currentZ - targetZ) > 0.05 {
                coordinator.cameraNode?.position = SCNVector3(0, 0, targetZ)
            }
        }

        let needsRebuild = coordinator.lastNodes != nodes
            || coordinator.lastImagePtr != fullScreenImage.map { Unmanaged.passUnretained($0).toOpaque() }
            || coordinator.lastDisplayMode != displayMode
            || coordinator.lastShowLabels != showLabels
            || abs(coordinator.lastLayerSpacing - layerSpacing) > 0.4
            || abs(coordinator.lastMinDepth - minDepthRatio) > 0.01
            || abs(coordinator.lastMaxDepth - maxDepthRatio) > 0.01
            || coordinator.lastSelectedID != selectedNodeID

        if needsRebuild {
            coordinator.lastNodes = nodes
            coordinator.lastImagePtr = fullScreenImage.map { Unmanaged.passUnretained($0).toOpaque() }
            coordinator.lastDisplayMode = displayMode
            coordinator.lastShowLabels = showLabels
            coordinator.lastLayerSpacing = layerSpacing
            coordinator.lastMinDepth = minDepthRatio
            coordinator.lastMaxDepth = maxDepthRatio
            coordinator.lastSelectedID = selectedNodeID
            coordinator.rebuildHierarchyPlanes(
                nodes: nodes,
                fullImage: fullScreenImage,
                croppedTextures: croppedTextures,
                selectedID: selectedNodeID,
                layerSpacing: layerSpacing,
                displayMode: displayMode,
                showLabels: showLabels,
                minDepthRatio: minDepthRatio,
                maxDepthRatio: maxDepthRatio
            )
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var scnView: SCNView?
        weak var pivotNode: SCNNode?
        weak var cameraNode: SCNNode?
        var onSelectNode: (UIComponentNode) -> Void

        var nodesByID: [String: UIComponentNode] = [:]
        var lastNodes: [UIComponentNode] = []
        var lastImagePtr: UnsafeMutableRawPointer?
        var lastDisplayMode: HierarchyDisplayMode = .wireframesAndContents
        var lastShowLabels = true
        var lastLayerSpacing: Double = 32
        var lastMinDepth: Double = 0.0
        var lastMaxDepth: Double = 1.0
        var lastSelectedID: String?
        var lastResetTrigger = 0

        private var panStartEuler: SCNVector3 = SCNVector3Zero
        private var pinchStartZ: CGFloat = 12.5

        init(onSelectNode: @escaping (UIComponentNode) -> Void) {
            self.onSelectNode = onSelectNode
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let pivot = pivotNode, let view = scnView else { return }
            let t = gesture.translation(in: view)
            if gesture.state == .began {
                panStartEuler = pivot.eulerAngles
            }
            let rawYaw = panStartEuler.y + t.x * 0.009
            let rawPitch = panStartEuler.x - t.y * 0.008
            let yaw = max(CGFloat(-1.42), min(CGFloat(1.42), rawYaw))
            let pitch = max(CGFloat(-0.85), min(CGFloat(0.85), rawPitch))
            pivot.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        @objc func handlePinch(_ gesture: NSMagnificationGestureRecognizer) {
            guard let cam = cameraNode else { return }
            if gesture.state == .began {
                pinchStartZ = cam.position.z
            }
            let scale = max(CGFloat(0.4), 1.0 + gesture.magnification)
            let newZ = max(CGFloat(5.0), min(CGFloat(22.0), pinchStartZ / scale))
            cam.position = SCNVector3(0, 0, newZ)
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = scnView else { return }
            let loc = gesture.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                var current: SCNNode? = hit.node
                while let n = current {
                    if let name = n.name, let matched = nodesByID[name] {
                        onSelectNode(matched)
                        return
                    }
                    current = n.parent
                }
            }
        }

        func rebuildHierarchyPlanes(
            nodes: [UIComponentNode],
            fullImage: CGImage?,
            croppedTextures: [String: CGImage],
            selectedID: String?,
            layerSpacing: Double,
            displayMode: HierarchyDisplayMode,
            showLabels: Bool,
            minDepthRatio: Double,
            maxDepthRatio: Double
        ) {
            guard let pivot = pivotNode else { return }
            pivot.childNodes.forEach { $0.removeFromParentNode() }

            let visible = nodes.filter { !$0.isHidden }
            guard !visible.isEmpty else { return }

            let maxPlane = max(1, visible.map(\.planeIndex).max() ?? 1)
            let minAllowedPlane = Int((Double(maxPlane) * min(minDepthRatio, maxDepthRatio)).rounded(.down))
            let maxAllowedPlane = Int((Double(maxPlane) * max(minDepthRatio, maxDepthRatio)).rounded(.up))

            let stageW: CGFloat = 2.95
            let stageH: CGFloat = 6.15
            let zStep = CGFloat(layerSpacing) * 0.011
            let midPlane = CGFloat(maxPlane) * 0.5

            let showContents = (displayMode != .wireframes)
            let showWireframes = (displayMode != .contents)

            var containerOrder = 0

            for node in visible {
                guard node.planeIndex >= minAllowedPlane && node.planeIndex <= maxAllowedPlane else {
                    continue
                }
                let isSelected = (node.id == selectedID)
                let zPos = (CGFloat(node.planeIndex) - midPlane) * zStep

                let w = max(0.20, CGFloat(node.normalizedWidth) * stageW)
                let h = max(0.14, CGFloat(node.normalizedHeight) * stageH)
                let cx = (CGFloat(node.normalizedX) + CGFloat(node.normalizedWidth) * 0.5 - 0.5) * stageW
                let cy = (0.5 - (CGFloat(node.normalizedY) + CGFloat(node.normalizedHeight) * 0.5)) * stageH

                let isContainer = node.kind.isStructuralContainer
                let plane = SCNPlane(width: w, height: h)
                plane.cornerRadius = node.kind == .window ? 0.22 : (isContainer ? 0.16 : min(0.10, CGFloat(node.cornerRadius) * 0.007))

                let mat = SCNMaterial()
                mat.isDoubleSided = true
                mat.lightingModel = .constant

                if isContainer {
                    // Xcode-style stepped matte backing card for structural containers (NEVER duplicating child screenshot pixels!)
                    if showContents {
                        let shade = max(0.72, 0.95 - Double(containerOrder) * 0.055)
                        mat.diffuse.contents = NSColor(srgbRed: shade, green: shade + 0.01, blue: min(1.0, shade + 0.03), alpha: 0.94)
                    } else {
                        mat.diffuse.contents = NSColor.white.withAlphaComponent(0.03)
                    }
                    containerOrder += 1
                } else if node.isEdited {
                    mat.diffuse.contents = Self.renderEditedTexture(node: node, size: CGSize(width: max(140, w * 90), height: max(48, h * 90)))
                    mat.transparency = CGFloat(node.opacity)
                } else if showContents, let tex = croppedTextures[node.id] {
                    mat.diffuse.contents = tex
                    mat.transparency = CGFloat(node.opacity)
                } else if showContents {
                    let accent = Self.nsColor(hex: node.accentHex)
                    mat.diffuse.contents = accent.withAlphaComponent(isSelected ? 0.35 : 0.16)
                } else {
                    mat.diffuse.contents = NSColor.white.withAlphaComponent(0.02)
                }

                plane.materials = [mat]
                let scnNode = SCNNode(geometry: plane)
                scnNode.name = node.id
                scnNode.position = SCNVector3(cx, cy, zPos + (isSelected ? 0.02 : 0.0))

                // Wireframe outline / Xcode sky-blue selection highlight
                if isSelected || showWireframes || isContainer {
                    let xcodeBlue = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
                    let borderColor: NSColor = isSelected
                        ? xcodeBlue
                        : (isContainer
                            ? NSColor(srgbRed: 0.55, green: 0.62, blue: 0.72, alpha: 0.65)
                            : NSColor(srgbRed: 0.64, green: 0.72, blue: 0.82, alpha: 0.52))
                    let thickness: CGFloat = isSelected ? 0.028 : (isContainer ? 0.011 : 0.008)
                    let borderNode = Self.makeBorderNode(width: w, height: h, color: borderColor, thickness: thickness)
                    borderNode.position = SCNVector3(0, 0, 0.004)
                    scnNode.addChildNode(borderNode)
                }

                // Xcode Top Header Tab Banner above structural containers (UIWindow, ViewController, UITableView, UIStackView, etc.)
                if (showLabels || isContainer) && (isContainer || isSelected) {
                    let tabH: CGFloat = 0.21
                    let tabW: CGFloat = min(w, max(1.35, CGFloat(node.name.count) * 0.072 + 0.45))
                    let tabPlane = SCNPlane(width: tabW, height: tabH)
                    tabPlane.cornerRadius = 0.04
                    let tabMat = SCNMaterial()
                    tabMat.lightingModel = .constant
                    tabMat.isDoubleSided = true
                    tabMat.diffuse.contents = Self.renderHeaderTabTexture(
                        title: isContainer ? "\(node.className) — \(node.name)" : node.name,
                        isController: node.kind == .window || node.kind == .cardContainer || node.kind == .navigationBar,
                        isSelected: isSelected,
                        size: CGSize(width: 340, height: 38)
                    )
                    tabPlane.materials = [tabMat]
                    let tabNode = SCNNode(geometry: tabPlane)
                    tabNode.name = node.id
                    tabNode.position = SCNVector3(-w * 0.5 + tabW * 0.5, h * 0.5 + tabH * 0.52, 0.005)
                    scnNode.addChildNode(tabNode)
                }

                pivot.addChildNode(scnNode)
            }
        }

        private static func renderHeaderTabTexture(
            title: String,
            isController: Bool,
            isSelected: Bool,
            size: CGSize
        ) -> NSImage {
            let img = NSImage(size: size)
            img.lockFocus()
            let rect = NSRect(origin: .zero, size: size)
            let bg = isSelected
                ? NSColor(srgbRed: 0.06, green: 0.36, blue: 0.78, alpha: 0.96)
                : NSColor(srgbRed: 0.14, green: 0.16, blue: 0.20, alpha: 0.95)
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            bg.setFill()
            path.fill()

            // Left badge circle (Xcode yellow 'C' for controller/window, sky-blue 'V' for view/container)
            let badgeRect = NSRect(x: 10, y: (size.height - 20) * 0.5, width: 20, height: 20)
            let badgeColor = isController
                ? NSColor(srgbRed: 0.96, green: 0.72, blue: 0.18, alpha: 1.0)
                : NSColor(srgbRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
            badgeColor.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()

            let badgeChar: NSString = isController ? "C" : "V"
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.black
            ]
            let bSize = badgeChar.size(withAttributes: badgeAttrs)
            badgeChar.draw(
                at: NSPoint(x: badgeRect.midX - bSize.width * 0.5, y: badgeRect.midY - bSize.height * 0.5),
                withAttributes: badgeAttrs
            )

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let nsTitle = title as NSString
            let tSize = nsTitle.size(withAttributes: textAttrs)
            let textRect = NSRect(
                x: 36,
                y: (size.height - tSize.height) * 0.5,
                width: size.width - 44,
                height: tSize.height + 2
            )
            nsTitle.draw(in: textRect, withAttributes: textAttrs)
            img.unlockFocus()
            return img
        }

        private static func makeBorderNode(width: CGFloat, height: CGFloat, color: NSColor, thickness: CGFloat) -> SCNNode {
            let parent = SCNNode()
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.lightingModel = .constant
            mat.isDoubleSided = true

            let top = SCNPlane(width: width, height: thickness)
            top.materials = [mat]
            let topN = SCNNode(geometry: top)
            topN.position = SCNVector3(0, height * 0.5, 0)

            let bot = SCNPlane(width: width, height: thickness)
            bot.materials = [mat]
            let botN = SCNNode(geometry: bot)
            botN.position = SCNVector3(0, -height * 0.5, 0)

            let left = SCNPlane(width: thickness, height: height)
            left.materials = [mat]
            let leftN = SCNNode(geometry: left)
            leftN.position = SCNVector3(-width * 0.5, 0, 0)

            let right = SCNPlane(width: thickness, height: height)
            right.materials = [mat]
            let rightN = SCNNode(geometry: right)
            rightN.position = SCNVector3(width * 0.5, 0, 0)

            parent.addChildNode(topN)
            parent.addChildNode(botN)
            parent.addChildNode(leftN)
            parent.addChildNode(rightN)
            return parent
        }

        private static func renderEditedTexture(node: UIComponentNode, size: CGSize) -> NSImage {
            let img = NSImage(size: size)
            img.lockFocus()
            let rect = NSRect(origin: .zero, size: size)
            let path = NSBezierPath(roundedRect: rect, xRadius: CGFloat(node.cornerRadius), yRadius: CGFloat(node.cornerRadius))
            nsColor(hex: node.accentHex).withAlphaComponent(0.92).setFill()
            path.fill()

            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: max(11, CGFloat(node.fontSize))),
                .foregroundColor: NSColor.white,
                .paragraphStyle: para
            ]
            let textSize = (node.displayText as NSString).size(withAttributes: attrs)
            let textRect = NSRect(
                x: 6,
                y: max(2, (size.height - textSize.height) * 0.5),
                width: max(10, size.width - 12),
                height: textSize.height + 4
            )
            (node.displayText as NSString).draw(in: textRect, withAttributes: attrs)
            img.unlockFocus()
            return img
        }

        private static func nsColor(hex: String) -> NSColor {
            let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: cleaned).scanHexInt64(&int)
            let r, g, b: UInt64
            switch cleaned.count {
            case 3:
                (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6:
                (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
            default:
                (r, g, b) = (10, 132, 255)
            }
            return NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
        }
    }
}

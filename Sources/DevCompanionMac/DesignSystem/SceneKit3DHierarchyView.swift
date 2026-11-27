import SwiftUI
import SceneKit
import AppKit
import DevCompanionCore

/// Metal GPU-accelerated 120fps 3D Debug View Hierarchy powered by SceneKit (`SCNView`).
/// Orbit rotation & zoom run directly on the SceneKit GPU graph with zero SwiftUI main-thread re-renders.
struct SceneKit3DHierarchyView: NSViewRepresentable {
    let nodes: [UIComponentNode]
    let fullScreenImage: CGImage?
    let croppedTextures: [String: CGImage]
    let selectedNodeID: String?
    let layerSpacing: Double
    let showWireframesOnly: Bool
    let showLabels: Bool
    let zoomScale: Double
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

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 38
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100
        cameraNode.position = SCNVector3(0, 0, 11.5)
        scene.rootNode.addChildNode(cameraNode)
        context.coordinator.cameraNode = cameraNode

        // Pivot node holding all 3D layers
        let pivot = SCNNode()
        pivot.eulerAngles = SCNVector3(Float(0.10), Float(-0.46), 0)
        scene.rootNode.addChildNode(pivot)
        context.coordinator.pivotNode = pivot
        context.coordinator.scnView = scnView

        // Native AppKit gestures (120fps GPU orbit without triggering SwiftUI body rebuilds)
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
            coordinator.pivotNode?.eulerAngles = SCNVector3(CGFloat(0.10), CGFloat(-0.46), 0)
            let resetZ = CGFloat(11.5) / max(0.5, CGFloat(zoomScale))
            coordinator.cameraNode?.position = SCNVector3(0, 0, resetZ)
            SCNTransaction.commit()
        } else {
            let targetZ = CGFloat(11.5) / max(0.5, CGFloat(zoomScale))
            let currentZ = coordinator.cameraNode?.position.z ?? CGFloat(11.5)
            if abs(currentZ - targetZ) > 0.05 {
                coordinator.cameraNode?.position = SCNVector3(0, 0, targetZ)
            }
        }

        let needsRebuild = coordinator.lastNodes != nodes
            || coordinator.lastImagePtr != fullScreenImage.map { Unmanaged.passUnretained($0).toOpaque() }
            || coordinator.lastShowWireframe != showWireframesOnly
            || coordinator.lastShowLabels != showLabels
            || abs(coordinator.lastLayerSpacing - layerSpacing) > 0.5
            || coordinator.lastSelectedID != selectedNodeID

        if needsRebuild {
            coordinator.lastNodes = nodes
            coordinator.lastImagePtr = fullScreenImage.map { Unmanaged.passUnretained($0).toOpaque() }
            coordinator.lastShowWireframe = showWireframesOnly
            coordinator.lastShowLabels = showLabels
            coordinator.lastLayerSpacing = layerSpacing
            coordinator.lastSelectedID = selectedNodeID
            coordinator.rebuildHierarchyPlanes(
                nodes: nodes,
                fullImage: fullScreenImage,
                croppedTextures: croppedTextures,
                selectedID: selectedNodeID,
                layerSpacing: layerSpacing,
                wireframe: showWireframesOnly,
                showLabels: showLabels
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
        var lastShowWireframe = false
        var lastShowLabels = false
        var lastLayerSpacing: Double = 32
        var lastSelectedID: String?
        var lastResetTrigger = 0

        private var panStartEuler: SCNVector3 = SCNVector3Zero
        private var pinchStartZ: CGFloat = 11.5

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
            let yaw = max(CGFloat(-1.35), min(CGFloat(1.35), rawYaw))
            let pitch = max(CGFloat(-0.85), min(CGFloat(0.85), rawPitch))
            pivot.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        @objc func handlePinch(_ gesture: NSMagnificationGestureRecognizer) {
            guard let cam = cameraNode else { return }
            if gesture.state == .began {
                pinchStartZ = cam.position.z
            }
            let scale = max(CGFloat(0.4), 1.0 + gesture.magnification)
            let newZ = max(CGFloat(5.5), min(CGFloat(20.0), pinchStartZ / scale))
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
            wireframe: Bool,
            showLabels: Bool
        ) {
            guard let pivot = pivotNode else { return }
            pivot.childNodes.forEach { $0.removeFromParentNode() }

            let stageW: CGFloat = 2.95
            let stageH: CGFloat = 6.20
            let zStep = Float(layerSpacing) * 0.022

            // Subtle glass guide planes for Z1..Z3
            for z in 1...3 {
                let zPos = (Float(z) - 1.5) * zStep
                let guide = SCNPlane(width: stageW, height: stageH)
                guide.cornerRadius = 0.22
                let mat = SCNMaterial()
                mat.diffuse.contents = NSColor.white.withAlphaComponent(0.025)
                mat.isDoubleSided = true
                guide.materials = [mat]
                let guideNode = SCNNode(geometry: guide)
                guideNode.position = SCNVector3(0, 0, zPos - 0.01)
                pivot.addChildNode(guideNode)
            }

            for node in nodes where !node.isHidden {
                let zPos = (Float(node.zLayer) - 1.5) * zStep
                let isSelected = node.id == selectedID

                let w = max(0.18, CGFloat(node.normalizedWidth) * stageW)
                let h = max(0.14, CGFloat(node.normalizedHeight) * stageH)
                let cx = (CGFloat(node.normalizedX) + CGFloat(node.normalizedWidth) * 0.5 - 0.5) * stageW
                let cy = (0.5 - (CGFloat(node.normalizedY) + CGFloat(node.normalizedHeight) * 0.5)) * stageH

                let plane = SCNPlane(width: w, height: h)
                plane.cornerRadius = node.kind == .window ? 0.22 : min(0.12, CGFloat(node.cornerRadius) * 0.008)

                let mat = SCNMaterial()
                mat.isDoubleSided = true
                mat.lightingModel = .constant

                if node.kind == .window {
                    if !wireframe, let fullImage {
                        mat.diffuse.contents = fullImage
                        mat.transparency = 0.96
                    } else {
                        mat.diffuse.contents = NSColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 0.85)
                    }
                } else if node.isEdited {
                    mat.diffuse.contents = Self.renderEditedTexture(node: node, size: CGSize(width: max(140, w * 90), height: max(48, h * 90)))
                    mat.transparency = CGFloat(node.opacity)
                } else if !wireframe, let tex = croppedTextures[node.id] {
                    mat.diffuse.contents = tex
                    mat.transparency = CGFloat(node.opacity)
                } else {
                    let accent = Self.nsColor(hex: node.accentHex)
                    mat.diffuse.contents = accent.withAlphaComponent(wireframe ? 0.10 : (isSelected ? 0.38 : 0.20))
                }

                plane.materials = [mat]
                let scnNode = SCNNode(geometry: plane)
                scnNode.name = node.id
                scnNode.position = SCNVector3(Float(cx), Float(cy), zPos + (isSelected ? 0.03 : 0.0))

                // Crisp border frame on selected or wireframe/labeled components
                if isSelected || wireframe || showLabels || node.kind == .window {
                    let borderColor: NSColor = isSelected
                        ? .white
                        : Self.nsColor(hex: node.accentHex).withAlphaComponent(node.kind == .window ? 0.35 : 0.65)
                    let borderNode = Self.makeBorderNode(width: w, height: h, color: borderColor, thickness: isSelected ? 0.028 : 0.012)
                    borderNode.position = SCNVector3(0, 0, 0.006)
                    scnNode.addChildNode(borderNode)
                }

                pivot.addChildNode(scnNode)
            }
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
            topN.position = SCNVector3(0, Float(height * 0.5), 0)

            let bot = SCNPlane(width: width, height: thickness)
            bot.materials = [mat]
            let botN = SCNNode(geometry: bot)
            botN.position = SCNVector3(0, Float(-height * 0.5), 0)

            let left = SCNPlane(width: thickness, height: height)
            left.materials = [mat]
            let leftN = SCNNode(geometry: left)
            leftN.position = SCNVector3(Float(-width * 0.5), 0, 0)

            let right = SCNPlane(width: thickness, height: height)
            right.materials = [mat]
            let rightN = SCNNode(geometry: right)
            rightN.position = SCNVector3(Float(width * 0.5), 0, 0)

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

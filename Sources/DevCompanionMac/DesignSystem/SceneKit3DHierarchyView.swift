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

public enum SceneKitCameraPreset: String, CaseIterable, Sendable, Identifiable {
    case front2D = "Front"
    case iso3D = "3D"

    public var id: String { rawValue }
}

/// Metal GPU-accelerated 120fps 3D Debug View Hierarchy modeled after Xcode's View Debugger:
/// - Stepped structural container backing planes (matte light/slate cards + dark Top Header Tab with C/V icon) — never duplicating full-screen screenshot pixels.
/// - Intermediate wireframe subview layout grid planes.
/// - Isolated foreground leaf visual elements rendering their cropped pixel content + Xcode sky-blue selection outline + 3D AutoLayout Constraint I-Beams.
struct SceneKit3DHierarchyView: NSViewRepresentable {
    let nodes: [UIComponentNode]
    let fullScreenImage: CGImage?
    let croppedTextures: [String: CGImage]
    let selectedNodeID: String?
    let layerSpacing: Double
    let displayMode: HierarchyDisplayMode
    let showLabels: Bool
    let showConstraints: Bool
    let showClippedContent: Bool
    let zoomScale: Double
    let minDepthRatio: Double
    let maxDepthRatio: Double
    let resetTrigger: Int
    let cameraPreset: SceneKitCameraPreset
    let cameraPresetTrigger: Int
    let onSelectNode: (UIComponentNode) -> Void
    let onFocusNode: (UIComponentNode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectNode: onSelectNode, onFocusNode: onFocusNode)
    }

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        // Signature Xcode View Debugger solid dark canvas background (#1E1E22 / #1C1D21)
        scnView.backgroundColor = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
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

        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        scnView.addGestureRecognizer(doubleClick)

        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        click.numberOfClicksRequired = 1
        scnView.addGestureRecognizer(click)

        let mag = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        scnView.addGestureRecognizer(mag)

        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelectNode = onSelectNode
        coordinator.onFocusNode = onFocusNode
        coordinator.nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        if coordinator.lastResetTrigger != resetTrigger {
            coordinator.lastResetTrigger = resetTrigger
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            coordinator.pivotNode?.eulerAngles = SCNVector3(CGFloat(0.08), CGFloat(-0.52), 0)
            let resetZ = CGFloat(12.5) / max(0.5, CGFloat(zoomScale))
            coordinator.cameraNode?.position = SCNVector3(0, 0, resetZ)
            SCNTransaction.commit()
        } else if coordinator.lastPresetTrigger != cameraPresetTrigger {
            coordinator.lastPresetTrigger = cameraPresetTrigger
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            switch cameraPreset {
            case .front2D:
                coordinator.pivotNode?.eulerAngles = SCNVector3(0, 0, 0)
            case .iso3D:
                coordinator.pivotNode?.eulerAngles = SCNVector3(CGFloat(0.08), CGFloat(-0.52), 0)
            }
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
            || coordinator.lastShowConstraints != showConstraints
            || coordinator.lastShowClipped != showClippedContent
            || abs(coordinator.lastLayerSpacing - layerSpacing) > 0.4
            || abs(coordinator.lastMinDepth - minDepthRatio) > 0.01
            || abs(coordinator.lastMaxDepth - maxDepthRatio) > 0.01
            || coordinator.lastSelectedID != selectedNodeID

        if needsRebuild {
            coordinator.lastNodes = nodes
            coordinator.lastImagePtr = fullScreenImage.map { Unmanaged.passUnretained($0).toOpaque() }
            coordinator.lastDisplayMode = displayMode
            coordinator.lastShowLabels = showLabels
            coordinator.lastShowConstraints = showConstraints
            coordinator.lastShowClipped = showClippedContent
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
                showConstraints: showConstraints,
                showClippedContent: showClippedContent,
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
        var onFocusNode: (UIComponentNode) -> Void

        var nodesByID: [String: UIComponentNode] = [:]
        var lastNodes: [UIComponentNode] = []
        var lastImagePtr: UnsafeMutableRawPointer?
        var lastDisplayMode: HierarchyDisplayMode = .wireframesAndContents
        var lastShowLabels = true
        var lastShowConstraints = true
        var lastShowClipped = false
        var lastLayerSpacing: Double = 32
        var lastMinDepth: Double = 0.0
        var lastMaxDepth: Double = 1.0
        var lastSelectedID: String?
        var lastResetTrigger = 0
        var lastPresetTrigger = 0

        private var panStartEuler: SCNVector3 = SCNVector3Zero
        private var pinchStartZ: CGFloat = 12.5

        init(onSelectNode: @escaping (UIComponentNode) -> Void, onFocusNode: @escaping (UIComponentNode) -> Void) {
            self.onSelectNode = onSelectNode
            self.onFocusNode = onFocusNode
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

        @objc func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = scnView else { return }
            let loc = gesture.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                var current: SCNNode? = hit.node
                while let n = current {
                    if let name = n.name, let matched = nodesByID[name] {
                        onFocusNode(matched)
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
            showConstraints: Bool,
            showClippedContent: Bool,
            minDepthRatio: Double,
            maxDepthRatio: Double
        ) {
            guard let pivot = pivotNode else { return }
            pivot.childNodes.forEach { $0.removeFromParentNode() }

            let visible = showClippedContent ? nodes : nodes.filter { !$0.isHidden }
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

                if node.kind == .window {
                    // Root UIWindow / plain UIView backing plane at the very back:
                    // Authentic Xcode Debug View renders plain backing layers in clean white (never duplicating full-screen screenshot pixels).
                    if showContents {
                        mat.diffuse.contents = isSelected
                            ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.45)
                            : NSColor(white: 0.98, alpha: 0.96)
                    } else {
                        mat.diffuse.contents = isSelected
                            ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.45)
                            : NSColor(white: 0.96, alpha: 0.04)
                    }
                    containerOrder += 1
                } else if isContainer {
                    // Intermediate structural containers (Card, TableView, CollectionView, StackView, ViewControllers):
                    // Direct visual bars/cells may show their cropped texture; layout containers render as bounded translucent frames above UIView.
                    let isDirectVisualContainer = (node.kind == .navigationBar || node.kind == .tabBar || node.kind == .cell)
                    if showContents, isDirectVisualContainer, let tex = croppedTextures[node.id] {
                        mat.diffuse.contents = tex
                        mat.transparency = CGFloat(node.opacity)
                    } else if isSelected {
                        mat.diffuse.contents = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.42)
                    } else {
                        mat.diffuse.contents = NSColor(white: 0.96, alpha: showContents ? 0.14 : 0.04)
                    }
                    containerOrder += 1
                } else if node.isEdited {
                    mat.diffuse.contents = Self.renderEditedTexture(node: node, size: CGSize(width: max(140, w * 90), height: max(48, h * 90)))
                    mat.transparency = CGFloat(node.opacity)
                } else if showContents, let tex = croppedTextures[node.id] {
                    mat.diffuse.contents = tex
                    mat.transparency = CGFloat(node.opacity)
                } else if showContents {
                    mat.diffuse.contents = Self.renderSyntheticComponentTexture(
                        node: node,
                        size: CGSize(width: max(160, w * 120), height: max(48, h * 120)),
                        isSelected: isSelected
                    )
                    mat.transparency = CGFloat(node.opacity)
                } else {
                    mat.diffuse.contents = isSelected ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.35) : NSColor.white.withAlphaComponent(0.02)
                }

                plane.materials = [mat]
                let scnNode = SCNNode(geometry: plane)
                scnNode.name = node.id
                scnNode.position = SCNVector3(cx, cy, zPos + (isSelected ? 0.02 : 0.0))

                // If a leaf component is selected in Contents mode, overlay Xcode transparent blue selection tint
                if isSelected && !isContainer && node.kind != .window {
                    let selOverlay = SCNPlane(width: w, height: h)
                    selOverlay.cornerRadius = plane.cornerRadius
                    let selMat = SCNMaterial()
                    selMat.lightingModel = .constant
                    selMat.isDoubleSided = true
                    selMat.diffuse.contents = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.38)
                    selOverlay.materials = [selMat]
                    let selNode = SCNNode(geometry: selOverlay)
                    selNode.position = SCNVector3(0, 0, 0.003)
                    scnNode.addChildNode(selNode)
                }

                // Wireframe outline / Xcode sky-blue selection highlight
                if isSelected || showWireframes || isContainer {
                    let xcodeBlue = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
                    let borderColor: NSColor = isSelected
                        ? xcodeBlue
                        : (isContainer
                            ? NSColor(white: 0.92, alpha: 0.55)
                            : NSColor(srgbRed: 0.64, green: 0.72, blue: 0.82, alpha: 0.45))
                    let thickness: CGFloat = isSelected ? 0.026 : (isContainer ? 0.010 : 0.007)
                    let borderNode = Self.makeBorderNode(width: w, height: h, color: borderColor, thickness: thickness)
                    borderNode.position = SCNVector3(0, 0, 0.004)
                    scnNode.addChildNode(borderNode)
                }

                // Xcode Top Header Tab Banner: controlled by `showLabels` (or shown on the single currently selected component)
                if (showLabels && isContainer) || isSelected {
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

                // Xcode 3D AutoLayout Constraint I-Beams for the currently selected view
                if isSelected && showConstraints && node.kind != .window {
                    let constraintGuides = Self.make3DConstraintGuidesNode(
                        node: node,
                        nodeCenterX: cx,
                        nodeCenterY: cy,
                        nodeWidth: w,
                        nodeHeight: h,
                        stageWidth: stageW,
                        stageHeight: stageH
                    )
                    constraintGuides.position = SCNVector3(0, 0, 0.008)
                    scnNode.addChildNode(constraintGuides)
                }

                pivot.addChildNode(scnNode)
            }
        }

        private static func make3DConstraintGuidesNode(
            node: UIComponentNode,
            nodeCenterX: CGFloat,
            nodeCenterY: CGFloat,
            nodeWidth: CGFloat,
            nodeHeight: CGFloat,
            stageWidth: CGFloat,
            stageHeight: CGFloat
        ) -> SCNNode {
            let group = SCNNode()
            let guideColor = NSColor(srgbRed: 0.16, green: 0.62, blue: 1.0, alpha: 0.95)
            let mat = SCNMaterial()
            mat.diffuse.contents = guideColor
            mat.lightingModel = .constant
            mat.isDoubleSided = true

            let lineThickness: CGFloat = 0.012
            let capSize: CGFloat = 0.09

            func addIBeam(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, horizontal: Bool) {
                let len = horizontal ? abs(toX - fromX) : abs(toY - fromY)
                guard len > 0.04 else { return }
                let beamGeom = SCNPlane(
                    width: horizontal ? len : lineThickness,
                    height: horizontal ? lineThickness : len
                )
                beamGeom.materials = [mat]
                let beamNode = SCNNode(geometry: beamGeom)
                beamNode.position = SCNVector3((fromX + toX) * 0.5, (fromY + toY) * 0.5, 0)
                group.addChildNode(beamNode)

                let capGeom = SCNPlane(
                    width: horizontal ? lineThickness : capSize,
                    height: horizontal ? capSize : lineThickness
                )
                capGeom.materials = [mat]
                let startCap = SCNNode(geometry: capGeom)
                startCap.position = SCNVector3(fromX, fromY, 0)
                let endCap = SCNNode(geometry: capGeom)
                endCap.position = SCNVector3(toX, toY, 0)
                group.addChildNode(startCap)
                group.addChildNode(endCap)
            }

            let leftEdgeInStage = -stageWidth * 0.5
            let rightEdgeInStage = stageWidth * 0.5
            let topEdgeInStage = stageHeight * 0.5
            let botEdgeInStage = -stageHeight * 0.5

            // Leading & Trailing relative to node local center (0, 0)
            let leadingDist = (nodeCenterX - nodeWidth * 0.5) - leftEdgeInStage
            if leadingDist > 0.05 {
                addIBeam(fromX: -nodeWidth * 0.5 - leadingDist, fromY: 0, toX: -nodeWidth * 0.5, toY: 0, horizontal: true)
            }
            let trailingDist = rightEdgeInStage - (nodeCenterX + nodeWidth * 0.5)
            if trailingDist > 0.05 {
                addIBeam(fromX: nodeWidth * 0.5, fromY: 0, toX: nodeWidth * 0.5 + trailingDist, toY: 0, horizontal: true)
            }
            // Top & Bottom relative to node local center (0, 0)
            let topDist = topEdgeInStage - (nodeCenterY + nodeHeight * 0.5)
            if topDist > 0.05 {
                addIBeam(fromX: 0, fromY: nodeHeight * 0.5, toX: 0, toY: nodeHeight * 0.5 + topDist, horizontal: false)
            }
            let botDist = (nodeCenterY - nodeHeight * 0.5) - botEdgeInStage
            if botDist > 0.05 {
                addIBeam(fromX: 0, fromY: -nodeHeight * 0.5 - botDist, toX: 0, toY: -nodeHeight * 0.5, horizontal: false)
            }
            return group
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

        private static func renderSyntheticWindowTexture(width: CGFloat, height: CGFloat) -> NSImage {
            let scale: CGFloat = 120.0
            let targetSize = CGSize(width: max(280, width * scale), height: max(580, height * scale))
            let img = NSImage(size: targetSize)
            img.lockFocus()
            let rect = NSRect(origin: .zero, size: targetSize)

            // 1. Device background with subtle corner radius
            let cornerRadius: CGFloat = 28
            let clipPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            clipPath.addClip()

            // Dark canvas gradient (#12141A to #1A1D24)
            let gradient = NSGradient(
                starting: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1.0),
                ending: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.15, alpha: 1.0)
            )
            gradient?.draw(in: rect, angle: -90)

            // Outer device bezel hairline
            NSColor(srgbRed: 0.22, green: 0.25, blue: 0.30, alpha: 0.85).setStroke()
            let strokePath = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius)
            strokePath.lineWidth = 1.8
            strokePath.stroke()

            // 2. Status Bar: "9:41" at top left
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            ("9:41" as NSString).draw(at: NSPoint(x: 24, y: targetSize.height - 30), withAttributes: timeAttrs)

            // Dynamic Island / Notch at top center
            let islandW: CGFloat = min(110, targetSize.width * 0.34)
            let islandH: CGFloat = 24
            let islandRect = NSRect(
                x: (targetSize.width - islandW) * 0.5,
                y: targetSize.height - islandH - 10,
                width: islandW,
                height: islandH
            )
            NSColor(srgbRed: 0.03, green: 0.03, blue: 0.04, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: islandRect, xRadius: islandH * 0.5, yRadius: islandH * 0.5).fill()

            // Cellular signal bars at top right
            let rightX = targetSize.width - 76
            let barBaseY = targetSize.height - 28
            for i in 0..<4 {
                let barH = CGFloat(4.0 + Double(i) * 2.5)
                let barRect = NSRect(x: rightX + CGFloat(i * 5), y: barBaseY, width: 3, height: barH)
                NSColor.white.setFill()
                NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
            }

            // Battery icon at top right
            let battRect = NSRect(x: targetSize.width - 44, y: targetSize.height - 28, width: 20, height: 10)
            NSColor(white: 0.85, alpha: 0.8).setStroke()
            let battPath = NSBezierPath(roundedRect: battRect, xRadius: 2.5, yRadius: 2.5)
            battPath.lineWidth = 1.2
            battPath.stroke()
            // Battery terminal cap
            let capRect = NSRect(x: battRect.maxX + 1, y: battRect.midY - 2, width: 1.5, height: 4)
            NSColor(white: 0.85, alpha: 0.8).setFill()
            NSBezierPath(rect: capRect).fill()
            // Battery green fill
            let fillRect = battRect.insetBy(dx: 2, dy: 2)
            NSColor(srgbRed: 0.20, green: 0.82, blue: 0.40, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()

            // 3. Home Indicator bar at bottom center
            let indW: CGFloat = min(130, targetSize.width * 0.38)
            let indRect = NSRect(
                x: (targetSize.width - indW) * 0.5,
                y: 12,
                width: indW,
                height: 4.5
            )
            NSColor(white: 0.92, alpha: 0.45).setFill()
            NSBezierPath(roundedRect: indRect, xRadius: 2.25, yRadius: 2.25).fill()

            img.unlockFocus()
            return img
        }

        private static func renderSyntheticComponentTexture(node: UIComponentNode, size: CGSize, isSelected: Bool) -> NSImage {
            let img = NSImage(size: size)
            img.lockFocus()
            let rect = NSRect(origin: .zero, size: size)
            let cr = min(size.height * 0.42, max(4, CGFloat(node.cornerRadius) * 2.5))
            let path = NSBezierPath(roundedRect: rect, xRadius: cr, yRadius: cr)

            let accent = nsColor(hex: node.accentHex)

            switch node.kind {
            case .button:
                let bg = isSelected ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.95) : accent.withAlphaComponent(0.92)
                bg.setFill()
                path.fill()
                NSColor(white: 1.0, alpha: 0.3).setStroke()
                path.lineWidth = 1.0
                path.stroke()

                let title = node.displayText.isEmpty ? node.name : node.displayText
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.lineBreakMode = .byTruncatingTail
                let fontSz = max(10, min(14, size.height * 0.32))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: fontSz),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: para
                ]
                let tSize = (title as NSString).size(withAttributes: attrs)
                let textRect = NSRect(
                    x: 6,
                    y: (size.height - tSize.height) * 0.5,
                    width: max(10, size.width - 12),
                    height: tSize.height
                )
                (title as NSString).draw(in: textRect, withAttributes: attrs)

            case .label:
                let bg = isSelected
                    ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.32)
                    : NSColor(white: 0.16, alpha: 0.45)
                bg.setFill()
                path.fill()
                if isSelected {
                    NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.8).setStroke()
                    path.lineWidth = 1.0
                    path.stroke()
                }

                let title = node.displayText.isEmpty ? node.name : node.displayText
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.lineBreakMode = .byTruncatingTail
                let fontSz = max(9.5, min(15, CGFloat(node.fontSize) * 0.82))
                let textColor = node.accentHex.isEmpty || node.accentHex.lowercased() == "#ffffff" ? NSColor.white : accent
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSz, weight: node.fontWeight.lowercased() == "bold" ? .bold : .medium),
                    .foregroundColor: textColor,
                    .paragraphStyle: para
                ]
                let tSize = (title as NSString).size(withAttributes: attrs)
                let textRect = NSRect(
                    x: 4,
                    y: (size.height - tSize.height) * 0.5,
                    width: max(10, size.width - 8),
                    height: tSize.height
                )
                (title as NSString).draw(in: textRect, withAttributes: attrs)

            case .inputField:
                let bg = NSColor(white: 0.15, alpha: 0.88)
                bg.setFill()
                path.fill()
                NSColor(white: 0.45, alpha: 0.5).setStroke()
                path.lineWidth = 1.0
                path.stroke()

                let title = node.displayText.isEmpty ? node.name : node.displayText
                let para = NSMutableParagraphStyle()
                para.alignment = .left
                para.lineBreakMode = .byTruncatingTail
                let fontSz = max(9.5, min(13, size.height * 0.28))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSz),
                    .foregroundColor: NSColor(white: 0.78, alpha: 1.0),
                    .paragraphStyle: para
                ]
                let tSize = (title as NSString).size(withAttributes: attrs)
                let textRect = NSRect(
                    x: 8,
                    y: (size.height - tSize.height) * 0.5,
                    width: max(10, size.width - 16),
                    height: tSize.height
                )
                (title as NSString).draw(in: textRect, withAttributes: attrs)

                let cursorRect = NSRect(x: textRect.minX + tSize.width + 2, y: textRect.minY + 1, width: 1.5, height: textRect.height - 2)
                accent.setFill()
                NSBezierPath(rect: cursorRect).fill()

            case .imageView, .banner:
                let bg = NSColor(white: 0.14, alpha: 0.82)
                bg.setFill()
                path.fill()
                accent.withAlphaComponent(0.4).setStroke()
                path.lineWidth = 1.0
                path.stroke()

                let title = node.displayText.isEmpty ? node.name : node.displayText
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.lineBreakMode = .byTruncatingTail
                let fontSz = max(9, min(12, size.height * 0.22))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSz, weight: .medium),
                    .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
                    .paragraphStyle: para
                ]
                let tSize = (title as NSString).size(withAttributes: attrs)
                let textRect = NSRect(
                    x: 4,
                    y: (size.height - tSize.height) * 0.5,
                    width: max(10, size.width - 8),
                    height: tSize.height
                )
                (title as NSString).draw(in: textRect, withAttributes: attrs)

            default:
                let bg = isSelected
                    ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.38)
                    : NSColor(white: 0.20, alpha: 0.35)
                bg.setFill()
                path.fill()
                NSColor(white: 0.65, alpha: isSelected ? 0.85 : 0.28).setStroke()
                path.lineWidth = isSelected ? 1.5 : 0.8
                path.stroke()

                if size.height >= 28 {
                    let title = node.name
                    let para = NSMutableParagraphStyle()
                    para.alignment = .left
                    para.lineBreakMode = .byTruncatingTail
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: max(9, min(12, size.height * 0.22))),
                        .foregroundColor: NSColor(white: 0.92, alpha: 0.90),
                        .paragraphStyle: para
                    ]
                    let tSize = (title as NSString).size(withAttributes: attrs)
                    let textRect = NSRect(
                        x: 8,
                        y: size.height - tSize.height - 6,
                        width: max(10, size.width - 16),
                        height: tSize.height
                    )
                    (title as NSString).draw(in: textRect, withAttributes: attrs)
                }
            }

            img.unlockFocus()
            return img
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

import SwiftUI
import AppKit
import DevCompanionCore

struct SimulatorControlsView: View {
    @Bindable var presenter: SimulatorPresenter
    var onChooseProject: (() -> Void)?
    @State private var dragStartYaw: Double?
    @State private var dragStartPitch: Double?
    @State private var showComponentLabels = false
    @Namespace private var simTabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header + Sub-Tab Switcher (Responsive FlowLayout prevents squished pickers/buttons)
                FlowLayout(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppStrings.Simulator.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        Text("Xcode-style 2D & 3D Exploded View Hierarchy Inspector, Live Component Editor & Code Jump")
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                    }

                    HStack(spacing: 4) {
                        ForEach(SimulatorWorkspaceTab.allCases) { tab in
                            let isSelected = presenter.workspaceTab == tab
                            Button {
                                withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
                                    presenter.workspaceTab = tab
                                }
                            } label: {
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(CompanionTheme.accentTint)
                                                .matchedGeometryEffect(id: "simTabPill", in: simTabNamespace)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CompanionTheme.glassLow)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                    )

                    Button(AppStrings.Simulator.refreshDevices) {
                        Task { await presenter.refreshRunningAppsAndHierarchy() }
                    }
                    .buttonStyle(.borderedProminent)
                    .preventSquish()
                }

                if !presenter.hasBootedSimulator && presenter.physicalDevices.isEmpty {
                    GuidedRequirementBanner(
                        icon: AppConstants.Icons.iphone,
                        message: AppStrings.Overview.needSimulatorBanner,
                        actionTitle: AppStrings.Simulator.refreshDevices,
                        action: { Task { await presenter.refreshRunningAppsAndHierarchy() } }
                    )
                } else if !presenter.hasProject, let onChooseProject {
                    GuidedRequirementBanner(
                        icon: AppConstants.Icons.folder,
                        message: AppStrings.Overview.needProjectBanner,
                        actionTitle: AppStrings.Common.selectXcodeProjectButton,
                        action: onChooseProject
                    )
                }

                switch presenter.workspaceTab {
                case .uiInspector:
                    liveUIHierarchyInspectorWorkspace
                case .quickTools:
                    quickSimulatorToolsWorkspace
                case .consoleAndLinks:
                    consoleAndDeepLinksWorkspace
                }
            }
            .padding(20)
        }
        .task {
            await presenter.refreshRunningAppsAndHierarchy()
        }
        .onDisappear {
            presenter.stopLogStream()
        }
    }

    // MARK: - 1. Xcode-Style 2D & 3D Live UI Hierarchy Inspector
    private var liveUIHierarchyInspectorWorkspace: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Running App & 2D/3D Camera Control Bar (Responsive FlowLayout)
            GlassCard {
                FlowLayout(spacing: 12, verticalSpacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(presenter.selectedTargetID != nil ? CompanionTheme.mint : CompanionTheme.amber)
                            .frame(width: 7, height: 7)
                        Text("1. Target:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .preventSquish()
                    }
                    .fixedSize()

                    Picker("", selection: $presenter.selectedTargetID) {
                        Text("Select Device / Simulator…").tag(String?.none)
                        ForEach(presenter.availableTargets) { target in
                            Text(target.title).tag(String?.some(target.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 205)
                    .fixedSize(horizontal: true, vertical: false)

                    Toggle("USB Only", isOn: $presenter.wiredUSBOnly)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .help("Hide Wi-Fi / Local Network devices and show only Wired USB devices & Simulators")
                        .preventSquish()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(presenter.selectedRunningApp != nil ? CompanionTheme.mint : CompanionTheme.amber)
                            .frame(width: 7, height: 7)
                        Text("2. Opened App:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .preventSquish()
                    }
                    .fixedSize()

                    Picker("", selection: $presenter.selectedRunningApp) {
                        Text(
                            presenter.selectedTargetID == nil
                                ? "Select Target First…"
                                : (presenter.isTargetAtHomeScreen
                                    ? "No Xcode App in Foreground"
                                    : (presenter.filteredRunningApps.isEmpty ? "No Xcode App Open" : "Select Xcode App…"))
                        )
                        .tag(SimulatorProcessInfo?.none)
                        ForEach(presenter.filteredRunningApps) { app in
                            Text("\(app.xcodePrivacyBadge) \(app.name) (PID \(app.id))").tag(SimulatorProcessInfo?.some(app))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 215)
                    .disabled(presenter.selectedTargetID == nil)
                    .fixedSize(horizontal: true, vertical: false)

                    Button {
                        Task { await presenter.refreshOpenedAppsNow(quiet: false) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: AppConstants.Icons.arrowClockwise)
                            Text("Refresh App")
                        }
                        .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(presenter.selectedTargetID == nil || presenter.isCapturingHierarchy)
                    .help("Refresh opened foreground application on the selected Target")
                    .preventSquish()

                    Toggle("Auto", isOn: $presenter.autoRefreshRunningApps)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .help("Automatically detect when an app is opened or closed on the selected Target")
                        .preventSquish()

                    HStack(spacing: 2) {
                        ForEach(UIRenderDimensionMode.allCases) { mode in
                            let isSelected = presenter.renderMode == mode
                            Button {
                                withAnimation(MotionTokens.snappy(reduceMotion: reduceMotion)) {
                                    presenter.renderMode = mode
                                }
                            } label: {
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? Color.white : CompanionTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? CompanionTheme.accent : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .preventSquish()
                        }
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CompanionTheme.glassLow)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                    )
                    .fixedSize(horizontal: true, vertical: false)

                    if presenter.renderMode == .render3D {
                        HStack(spacing: 6) {
                            Text("Depth")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(CompanionTheme.textSecondary)
                                .preventSquish()
                            Slider(value: $presenter.layerSpacing, in: 10...64)
                                .frame(width: 75)
                            Text("Zoom")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(CompanionTheme.textSecondary)
                                .preventSquish()
                            Slider(value: $presenter.canvasZoom, in: 0.65...1.45)
                                .frame(width: 75)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    Toggle("Wireframe", isOn: $presenter.showWireframesOnly)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .preventSquish()

                    Toggle("Labels", isOn: $showComponentLabels)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .preventSquish()

                    Button(presenter.isLiveScreenSyncActive ? "Live Sync: ON" : "Live Sync") {
                        presenter.toggleLiveScreenSync()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(presenter.isLiveScreenSyncActive ? CompanionTheme.mint : CompanionTheme.accent)
                    .controlSize(.small)
                    .disabled(presenter.selectedRunningApp == nil)
                    .preventSquish()

                    Button("Reset 3D") {
                        withAnimation(.snappy) {
                            presenter.reset3DCamera()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .preventSquish()

                    Button("Capture Now") {
                        Task { await presenter.captureHierarchyForSelectedApp() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(presenter.selectedRunningApp == nil || presenter.isCapturingHierarchy)
                    .preventSquish()
                }
            }

            if presenter.selectedRunningApp == nil {
                GlassCard {
                    VStack(spacing: 10) {
                        Image(systemName: AppConstants.Icons.iphone)
                            .font(.system(size: 28))
                            .foregroundStyle(CompanionTheme.textMuted)
                        Text("No Active Running Application Selected")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        Text("Open an application in your booted iOS Simulator or connected iPhone, then click Refresh Devices to inspect its 2D/3D view hierarchy and jump to Xcode.")
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                }
            } else {
                // 3-Column Xcode View Debugger Stage
                HStack(alignment: .top, spacing: 12) {
                    // Left Column: Xcode-Style Root-to-Leaf View Hierarchy Tree
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("View Hierarchy Tree")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                Spacer()
                                Button {
                                    presenter.expandAllNodes()
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .help("Expand All")
                                Button {
                                    presenter.collapseToContainers()
                                } label: {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .help("Collapse Containers")
                                Text("\(presenter.visibleHierarchyNodes.count)/\(presenter.componentNodes.count)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textMuted)
                            }

                            HStack(spacing: 6) {
                                Image(systemName: AppConstants.Icons.magnifyingGlass)
                                    .font(.system(size: 10))
                                    .foregroundStyle(CompanionTheme.textMuted)
                                TextField("Filter UITableView, Cell, UILabel…", text: $presenter.hierarchySearchQuery)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 10.5))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))

                            RecycledVirtualList(items: presenter.visibleHierarchyNodes, rowSpacing: 4) { node in
                                let isSelected = presenter.selectedNode?.id == node.id
                                let isCollapsed = presenter.collapsedNodeIDs.contains(node.id)
                                HStack(spacing: 5) {
                                    Spacer()
                                        .frame(width: CGFloat(min(6, node.depth)) * 10)

                                    if node.childCount > 0 {
                                        Button {
                                            presenter.toggleNodeCollapse(node.id)
                                        } label: {
                                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                                .font(.system(size: 8.5, weight: .bold))
                                                .foregroundStyle(CompanionTheme.textMuted)
                                                .frame(width: 12, height: 12)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Spacer().frame(width: 12)
                                    }

                                    Button {
                                        withAnimation(.snappy) {
                                            presenter.selectComponent(node)
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: node.kind.iconName)
                                                .font(.system(size: 10))
                                                .foregroundStyle(isSelected ? CompanionTheme.accent : Color(hex: node.accentHex))

                                            VStack(alignment: .leading, spacing: 1) {
                                                HStack(spacing: 4) {
                                                    Text(node.name)
                                                        .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                                                        .foregroundStyle(CompanionTheme.textPrimary)
                                                        .lineLimit(1)
                                                    if node.childCount > 0 {
                                                        Text("(\(node.childCount))")
                                                            .font(.system(size: 8.5, design: .monospaced))
                                                            .foregroundStyle(CompanionTheme.textMuted)
                                                    }
                                                }
                                                Text("\(node.className) • \(node.locationLabel)")
                                                    .font(.system(size: 8.5, design: .monospaced))
                                                    .foregroundStyle(CompanionTheme.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isSelected ? CompanionTheme.accent.opacity(0.75) : .clear, lineWidth: 1)
                                        )
                                )
                            }
                            .frame(minHeight: 420, maxHeight: 490)
                        }
                    }
                    .frame(minWidth: 230, idealWidth: 265, maxWidth: 295)

                    // Center Column: Interactive 2D / 3D Exploded Layer Stage
                    GlassCard {
                        VStack(spacing: 8) {
                            HStack {
                                Text(presenter.renderMode == .render3D
                                     ? "3D Debug View Hierarchy (Drag to rotate 3D • Tap layer/component)"
                                     : "2D Live Device Screen (Tap any detected component)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CompanionTheme.textSecondary)
                                Spacer()
                                if presenter.isCapturingHierarchy {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                if let app = presenter.selectedRunningApp {
                                    Text(app.displayLabel)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.mint)
                                }
                            }

                            // Xcode Top Breadcrumb Jump Bar (Root ▸ Container ▸ Subview)
                            if !presenter.breadcrumbNodes.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        ForEach(Array(presenter.breadcrumbNodes.enumerated()), id: \.element.id) { idx, crumb in
                                            if idx > 0 {
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(CompanionTheme.textMuted)
                                            }
                                            Button {
                                                presenter.selectComponent(crumb)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: crumb.kind.iconName)
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(crumb.id == presenter.selectedNodeID ? CompanionTheme.accent : CompanionTheme.textSecondary)
                                                    Text(crumb.name)
                                                        .font(.system(size: 10, weight: crumb.id == presenter.selectedNodeID ? .bold : .medium))
                                                        .foregroundStyle(crumb.id == presenter.selectedNodeID ? CompanionTheme.textPrimary : CompanionTheme.textSecondary)
                                                        .lineLimit(1)
                                                }
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .fill(crumb.id == presenter.selectedNodeID ? CompanionTheme.accent.opacity(0.22) : Color.white.opacity(0.04))
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }

                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.14, green: 0.15, blue: 0.18).opacity(0.92))

                                if presenter.renderMode == .render2D {
                                    deviceStagePlane(zLayerFilter: nil)
                                        .frame(width: 245, height: 505)
                                        .scaleEffect(presenter.canvasZoom)
                                } else {
                                    // Authentic Xcode 3D Debug View Hierarchy
                                    SceneKit3DHierarchyView(
                                        nodes: presenter.componentNodes,
                                        fullScreenImage: presenter.liveScreenCGImage,
                                        croppedTextures: presenter.preCroppedTextures,
                                        selectedNodeID: presenter.selectedNode?.id,
                                        layerSpacing: presenter.layerSpacing,
                                        displayMode: presenter.displayMode,
                                        showLabels: showComponentLabels,
                                        zoomScale: presenter.canvasZoom,
                                        minDepthRatio: presenter.minDepthRatio,
                                        maxDepthRatio: presenter.maxDepthRatio,
                                        resetTrigger: presenter.cameraResetCounter,
                                        onSelectNode: { node in
                                            presenter.selectComponent(node)
                                        }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 460)

                            // Xcode Bottom View Debugger Canvas Bar (Spacing | Display Mode | Depth Range Clip)
                            HStack(spacing: 10) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.3.layers.3d.down.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(CompanionTheme.textSecondary)
                                    Slider(value: $presenter.layerSpacing, in: 8...68)
                                        .frame(width: 85)
                                        .help("Layer Spacing")
                                }

                                Spacer()

                                HStack(spacing: 2) {
                                    ForEach(HierarchyDisplayMode.allCases) { mode in
                                        let active = presenter.displayMode == mode
                                        Button {
                                            presenter.displayMode = mode
                                            presenter.showWireframesOnly = (mode == .wireframes)
                                        } label: {
                                            Text(mode.rawValue)
                                                .font(.system(size: 9.5, weight: active ? .bold : .medium))
                                                .foregroundStyle(active ? Color.white : CompanionTheme.textSecondary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .fill(active ? CompanionTheme.accent : Color.clear)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(2)
                                .background(RoundedRectangle(cornerRadius: 6).fill(CompanionTheme.glassLow))

                                Spacer()

                                HStack(spacing: 5) {
                                    Text("Clip")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(CompanionTheme.textMuted)
                                    Slider(value: $presenter.minDepthRatio, in: 0.0...0.85)
                                        .frame(width: 60)
                                        .help("Clip Back Layers")
                                    Slider(value: $presenter.maxDepthRatio, in: 0.15...1.0)
                                        .frame(width: 60)
                                        .help("Clip Front Layers")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(CompanionTheme.glassLow))
                        }
                    }

                    // Right Column: Safe Draft-First 5-Tab XIB Inspector
                    SimulatorXIBInspectorPane(presenter: presenter)
                }
            }
        }
    }

    // MARK: - 2D / 3D Plane Renderer
    private func deviceStagePlane(zLayerFilter: Int?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let visibleNodes = presenter.componentNodes.filter {
                !$0.isHidden && (zLayerFilter == nil || $0.zLayer == zLayerFilter)
            }

            ZStack(alignment: .topLeading) {
                // Base Layer (Z0 or 2D Full Screen): Show live captured iPhone/Simulator screenshot
                if zLayerFilter == nil || zLayerFilter == 0 {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 0.06, green: 0.09, blue: 0.14))
                        .overlay(
                            Group {
                                if !presenter.showWireframesOnly, let cgImg = presenter.liveScreenCGImage {
                                    Image(decorative: cgImg, scale: 1.0)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: w, height: h)
                                        .clipShape(RoundedRectangle(cornerRadius: 22))
                                        .opacity(zLayerFilter == 0 ? 0.94 : 1.0)
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(CompanionTheme.hairlineBorder, lineWidth: 1.2)
                        )
                } else {
                    // Transparent glass plane for higher exploded 3D Z-layers (Z1..Z3)
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(CompanionTheme.hairlineBorder.opacity(0.50), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                        )
                }

                // Layer Depth Badge in 3D mode
                if let z = zLayerFilter {
                    Text("Z\(z)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.65))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .clipShape(Capsule())
                        .padding(8)
                }

                // Interactive Component Nodes on this plane (renders real cropped iPhone/Simulator pixels in 3D!)
                ForEach(visibleNodes) { rawNode in
                    let isSelected = presenter.selectedNode?.id == rawNode.id
                    let node = (isSelected ? presenter.draftNode : nil) ?? rawNode
                    let nodeX = CGFloat(node.normalizedX) * w
                    let nodeY = CGFloat(node.normalizedY) * h
                    let nodeW = max(24, CGFloat(node.normalizedWidth) * w)
                    let nodeH = max(18, CGFloat(node.normalizedHeight) * h)
                    let tint = Color(hex: node.accentHex)

                    if isSelected {
                        // AutoLayout Constraint Guides in 2D Canvas
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: nodeY + nodeH / 2))
                            p.addLine(to: CGPoint(x: nodeX, y: nodeY + nodeH / 2))
                            p.move(to: CGPoint(x: nodeX + nodeW, y: nodeY + nodeH / 2))
                            p.addLine(to: CGPoint(x: w, y: nodeY + nodeH / 2))
                            p.move(to: CGPoint(x: nodeX + nodeW / 2, y: 0))
                            p.addLine(to: CGPoint(x: nodeX + nodeW / 2, y: nodeY))
                            p.move(to: CGPoint(x: nodeX + nodeW / 2, y: nodeY + nodeH))
                            p.addLine(to: CGPoint(x: nodeX + nodeW / 2, y: h))
                        }
                        .stroke(CompanionTheme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }

                    Button {
                        withAnimation(.snappy) {
                            presenter.selectComponent(node)
                        }
                    } label: {
                        ZStack {
                            if (node.isEdited || (isSelected && presenter.hasUnappliedChanges)) && node.kind != .window {
                                RoundedRectangle(cornerRadius: node.cornerRadius)
                                    .fill(tint.opacity(0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: node.cornerRadius)
                                            .stroke(isSelected ? Color.white : tint, lineWidth: isSelected ? 2.2 : 1.0)
                                    )
                                Text(node.displayText)
                                    .font(.system(size: max(9, CGFloat(node.fontSize) * 0.8), weight: .bold))
                                    .foregroundStyle(Color.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                            } else if !presenter.showWireframesOnly,
                                      node.kind != .window,
                                      zLayerFilter != nil,
                                      let cropped = croppedComponentImage(for: node) {
                                Image(decorative: cropped, scale: 1.0)
                                    .resizable()
                                    .frame(width: nodeW, height: nodeH)
                                    .clipShape(RoundedRectangle(cornerRadius: node.cornerRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: node.cornerRadius)
                                            .stroke(
                                                isSelected ? Color.white : tint.opacity(0.75),
                                                lineWidth: isSelected ? 2.2 : 1.0
                                            )
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: node.cornerRadius)
                                    .fill(
                                        presenter.showWireframesOnly
                                            ? Color.clear
                                            : (isSelected ? tint.opacity(0.24) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: node.cornerRadius)
                                            .stroke(
                                                isSelected ? Color.white : tint.opacity(presenter.liveScreenCGImage == nil ? 0.85 : 0.45),
                                                lineWidth: isSelected ? 2.2 : 1.0
                                            )
                                    )

                                if node.kind != .window && (showComponentLabels || presenter.liveScreenCGImage == nil || presenter.showWireframesOnly || isSelected) {
                                    Text(node.name)
                                        .font(.system(size: max(8.5, CGFloat(node.fontSize) * 0.72), weight: .bold))
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.black.opacity(0.65))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(width: nodeW, height: nodeH)
                        .opacity(node.opacity)
                    }
                    .buttonStyle(.plain)
                    .position(x: nodeX + nodeW * 0.5, y: nodeY + nodeH * 0.5)
                }
            }
        }
    }

    private func croppedComponentImage(for node: UIComponentNode) -> CGImage? {
        guard let fullImg = presenter.liveScreenCGImage else { return nil }
        let imgW = CGFloat(fullImg.width)
        let imgH = CGFloat(fullImg.height)
        let cropRect = CGRect(
            x: max(0, CGFloat(node.normalizedX) * imgW),
            y: max(0, CGFloat(node.normalizedY) * imgH),
            width: max(8, CGFloat(node.normalizedWidth) * imgW),
            height: max(8, CGFloat(node.normalizedHeight) * imgH)
        ).intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard !cropRect.isNull, cropRect.width >= 4, cropRect.height >= 4 else { return nil }
        return fullImg.cropping(to: cropRect)
    }

    // MARK: - 2. Secondary Tab: Simulator Tools & Live Reload
    private var quickSimulatorToolsWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !presenter.physicalDevices.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: AppConstants.Icons.iphone)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CompanionTheme.mint)
                            Text(AppStrings.TopBar.physicalDevicesSection)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CompanionTheme.textPrimary)
                            Spacer()
                            Text("\(presenter.physicalDevices.count)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(CompanionTheme.mint.opacity(0.2))
                                .foregroundStyle(CompanionTheme.mint)
                                .clipShape(Capsule())
                        }

                        VStack(spacing: 6) {
                            ForEach(presenter.physicalDevices) { device in
                                let isSelected = presenter.selectedPhysicalDeviceID == device.id
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(CompanionTheme.mint)
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(device.name)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(CompanionTheme.textPrimary)
                                            Text(device.modelName)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(CompanionTheme.textSecondary)
                                        }
                                        Text("iOS \(device.osVersion) • \(device.connectionType) • \(AppStrings.TopBar.deviceConnected)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(CompanionTheme.textMuted)
                                    }
                                    Spacer()
                                    Button(isSelected ? AppStrings.TopBar.activeDeviceTarget : AppStrings.TopBar.useDeviceTarget) {
                                        presenter.selectPhysicalDevice(device)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(isSelected ? CompanionTheme.mint : CompanionTheme.accent)
                                    .controlSize(.small)
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(isSelected ? CompanionTheme.glassHigh : CompanionTheme.glassLow)
                                )
                            }
                        }
                    }
                }
            }

            // Live Refresh (Flutter-style Hot Reload)
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle()
                            .fill(presenter.isLiveReloadActive ? CompanionTheme.mint : CompanionTheme.textMuted)
                            .frame(width: 7, height: 7)
                        Text(AppStrings.Simulator.liveReloadTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        Spacer()
                        Button(presenter.isLiveReloadActive ? AppStrings.Simulator.stopLiveReload : AppStrings.Simulator.startLiveReload) {
                            presenter.toggleLiveReload()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!presenter.hasProject)
                    }
                    Text(AppStrings.Simulator.liveReloadSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.textSecondary)
                    TextField(AppStrings.Simulator.liveReloadSchemePlaceholder, text: $presenter.liveReloadScheme)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!presenter.hasProject)
                    if !presenter.lastReloadSummary.isEmpty {
                        Text(presenter.lastReloadSummary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CompanionTheme.mint)
                    }
                }
            }

            // Environment & Appearance Controls (Uses resolvedBootedUDID)
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppStrings.Simulator.appearanceSection)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textPrimary)

                    FlowLayout(spacing: 10) {
                        Button(AppStrings.Simulator.darkMode) { Task { await presenter.setAppearance(.dark) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(!presenter.hasBootedSimulator)
                            .preventSquish()
                        Button(AppStrings.Simulator.lightMode) { Task { await presenter.setAppearance(.light) } }
                            .buttonStyle(.bordered)
                            .disabled(!presenter.hasBootedSimulator)
                            .preventSquish()
                        Button(AppStrings.Simulator.cleanStatusBar) { Task { await presenter.overrideStatusBar() } }
                            .buttonStyle(.bordered)
                            .disabled(!presenter.hasBootedSimulator)
                            .preventSquish()
                        Button(AppStrings.Simulator.screenshotToClipboard) { Task { await presenter.captureScreenshot() } }
                            .buttonStyle(.bordered)
                            .disabled(!presenter.hasBootedSimulator)
                            .preventSquish()
                    }

                    Divider()

                    Text(AppStrings.Simulator.dynamicTypeSize)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CompanionTheme.textSecondary)

                    FlowLayout(spacing: 8) {
                        ForEach(DynamicTypeSizeOption.allCases) { size in
                            Button(size.rawValue) {
                                Task { await presenter.setDynamicType(size) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!presenter.hasBootedSimulator)
                            .preventSquish()
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppStrings.Simulator.deepLinkSection)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        HStack {
                            TextField(AppStrings.Simulator.deepLinkPlaceholder, text: $presenter.deepLinkURL)
                                .textFieldStyle(.roundedBorder)
                            Button(AppStrings.Simulator.openURL) {
                                Task { await presenter.openDeepLink() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!presenter.canOpenDeepLink)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppStrings.Simulator.pushSection)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        TextField(AppStrings.Simulator.bundleIDPlaceholder, text: $presenter.pushBundleID)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            TextField(AppStrings.Simulator.pushTitlePlaceholder, text: $presenter.pushTitle)
                                .textFieldStyle(.roundedBorder)
                            TextField(AppStrings.Simulator.pushBodyPlaceholder, text: $presenter.pushBody)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(AppStrings.Simulator.sendPush) {
                            Task { await presenter.sendPush() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!presenter.canSendPush)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppStrings.Enhancements.simLifecycle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)

                        FlowLayout(spacing: 8) {
                            Button(presenter.isRecordingVideo ? AppStrings.Enhancements.stopSaveVideo : AppStrings.Enhancements.recordVideo) {
                                presenter.toggleVideoRecording()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(presenter.isRecordingVideo ? CompanionTheme.coral : CompanionTheme.accent)
                            .disabled(!presenter.hasBootedSimulator && !presenter.isRecordingVideo)

                            Button(AppStrings.Enhancements.shutdownSim) {
                                Task { await presenter.shutdownBootedSimulator() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!presenter.hasBootedSimulator)

                            if !presenter.availableShutdownSimulators.isEmpty {
                                Menu(AppStrings.Enhancements.bootSim) {
                                    ForEach(presenter.availableShutdownSimulators.prefix(12)) { sim in
                                        Button("\(sim.name) (\(sim.runtime))") {
                                            Task { await presenter.bootSimulator(udid: sim.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Enhancements.sandboxTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textPrimary)

                    HStack(spacing: 8) {
                        TextField("Bundle ID (e.g. com.example.MyApp)", text: $presenter.sandboxBundleID)
                            .textFieldStyle(.roundedBorder)
                        Button(presenter.isInspectingSandbox ? "Inspecting…" : "Inspect Container") {
                            Task { await presenter.inspectAppSandbox() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!presenter.hasBootedSimulator || presenter.sandboxBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || presenter.isInspectingSandbox)
                    }

                    if let snap = presenter.sandboxSnapshot {
                        Text("Documents (\(snap.documentsFiles.count)) • Caches (\(snap.cachesCount)) • UserDefaults (\(snap.userDefaults.count) keys)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanionTheme.mint)

                        if !snap.userDefaults.isEmpty {
                            RecycledVirtualList(items: snap.userDefaults, rowSpacing: 3) { item in
                                HStack {
                                    Text(item.key)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.accent)
                                        .frame(width: 180, alignment: .leading)
                                        .lineLimit(1)
                                    Text(item.value)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .frame(minHeight: 110, maxHeight: 180)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.Enhancements.locationSpoofer)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        FlowLayout(spacing: 6) {
                            Button("Jakarta") { Task { await presenter.setSimulatorLocation(latitude: -6.2088, longitude: 106.8456, label: "Jakarta") } }
                            Button("Tokyo") { Task { await presenter.setSimulatorLocation(latitude: 35.6762, longitude: 139.6503, label: "Tokyo") } }
                            Button("San Francisco") { Task { await presenter.setSimulatorLocation(latitude: 37.7749, longitude: -122.4194, label: "San Francisco") } }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!presenter.hasBootedSimulator)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.Enhancements.privacyReset)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        FlowLayout(spacing: 6) {
                            ForEach(SimulatorPrivacyService.allCases) { service in
                                Button(service.displayName) {
                                    Task { await presenter.resetPrivacy(service) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .disabled(!presenter.hasBootedSimulator)
                    }
                }
            }
        }
    }

    // MARK: - 3. Live Console (os_log) & Deep Link Presets
    private var consoleAndDeepLinksWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 8) {
                        Text(AppStrings.Enhancements.liveConsole)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                            .preventSquish()

                        Picker("", selection: $presenter.logLevelFilter) {
                            ForEach(SimulatorLogLevel.allCases) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .frame(width: 110)

                        TextField("Filter subsystem, process, or text…", text: $presenter.logSearchQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180, maxWidth: 280)

                        Button(presenter.isStreamingLogs ? "Pause Stream" : "Start Stream") {
                            presenter.toggleLogStream()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(presenter.isStreamingLogs ? CompanionTheme.coral : CompanionTheme.mint)
                        .disabled(!presenter.hasBootedSimulator && !presenter.isStreamingLogs)
                        .preventSquish()

                        Button("Clear") {
                            presenter.clearLogs()
                        }
                        .buttonStyle(.bordered)
                        .disabled(presenter.logEntries.isEmpty)
                        .preventSquish()

                        Text("\(presenter.filteredLogEntries.count)/500")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CompanionTheme.textMuted)
                            .preventSquish()
                    }

                    if presenter.filteredLogEntries.isEmpty {
                        Text(presenter.isStreamingLogs ? "Waiting for log events from booted simulator…" : "Click Start Stream to inspect live os_log output (capped at 500 lines).")
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                            .padding(.vertical, 12)
                    } else {
                        RecycledVirtualList(items: presenter.filteredLogEntries, rowSpacing: 3) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timestamp)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textMuted)
                                    .frame(width: 82, alignment: .leading)
                                Text(entry.level.rawValue.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(logLevelColor(entry.level))
                                    .frame(width: 52, alignment: .leading)
                                Text(entry.subsystem.isEmpty ? entry.process : "\(entry.process)[\(entry.subsystem)]")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.accent)
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(CompanionTheme.textPrimary)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(minHeight: 220, maxHeight: 360)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Enhancements.deepLinkPresets)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textPrimary)

                    HStack(spacing: 8) {
                        TextField("Preset label (optional)", text: $presenter.deepLinkPresetTitle)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        TextField(AppStrings.Simulator.deepLinkPlaceholder, text: $presenter.deepLinkURL)
                            .textFieldStyle(.roundedBorder)
                        Button("Save Preset") {
                            presenter.saveDeepLinkPreset()
                        }
                        .buttonStyle(.bordered)
                        .disabled(presenter.deepLinkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Open Link") {
                            Task { await presenter.openDeepLink() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!presenter.hasBootedSimulator || presenter.deepLinkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if presenter.deepLinkPresets.isEmpty {
                        Text("Open or save a deep link above to build 1-click presets.")
                            .font(.system(size: 11))
                            .foregroundStyle(CompanionTheme.textSecondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(presenter.deepLinkPresets) { preset in
                                HStack(spacing: 6) {
                                    Button {
                                        Task { await presenter.fireDeepLinkPreset(preset) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(preset.title)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(CompanionTheme.textPrimary)
                                            Text(preset.urlString)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(CompanionTheme.textMuted)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!presenter.hasBootedSimulator)

                                    Button {
                                        presenter.removeDeepLinkPreset(id: preset.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(CompanionTheme.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(CompanionTheme.glassLow)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CompanionTheme.hairlineBorder, lineWidth: 1))
                                )
                            }
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Enhancements.sandboxTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CompanionTheme.textPrimary)

                    HStack(spacing: 8) {
                        TextField("Bundle ID (e.g. com.example.MyApp)", text: $presenter.sandboxBundleID)
                            .textFieldStyle(.roundedBorder)
                        Button(presenter.isInspectingSandbox ? "Inspecting…" : "Inspect Container") {
                            Task { await presenter.inspectAppSandbox() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!presenter.hasBootedSimulator || presenter.sandboxBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || presenter.isInspectingSandbox)
                    }

                    if let snap = presenter.sandboxSnapshot {
                        Text("Documents (\(snap.documentsFiles.count)) • Caches (\(snap.cachesCount)) • UserDefaults (\(snap.userDefaults.count) keys)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanionTheme.mint)

                        if !snap.userDefaults.isEmpty {
                            RecycledVirtualList(items: snap.userDefaults, rowSpacing: 3) { item in
                                HStack {
                                    Text(item.key)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.accent)
                                        .frame(width: 180, alignment: .leading)
                                        .lineLimit(1)
                                    Text(item.value)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(CompanionTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .frame(minHeight: 110, maxHeight: 180)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.Enhancements.locationSpoofer)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        FlowLayout(spacing: 6) {
                            Button("Jakarta") { Task { await presenter.setSimulatorLocation(latitude: -6.2088, longitude: 106.8456, label: "Jakarta") } }
                            Button("Tokyo") { Task { await presenter.setSimulatorLocation(latitude: 35.6762, longitude: 139.6503, label: "Tokyo") } }
                            Button("San Francisco") { Task { await presenter.setSimulatorLocation(latitude: 37.7749, longitude: -122.4194, label: "San Francisco") } }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!presenter.hasBootedSimulator)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.Enhancements.privacyReset)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionTheme.textPrimary)
                        FlowLayout(spacing: 6) {
                            ForEach(SimulatorPrivacyService.allCases) { service in
                                Button(service.displayName) {
                                    Task { await presenter.resetPrivacy(service) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .disabled(!presenter.hasBootedSimulator)
                    }
                }
            }
        }
    }

    private func logLevelColor(_ level: SimulatorLogLevel) -> Color {
        switch level {
        case .error, .fault: CompanionTheme.coral
        case .info: CompanionTheme.accent
        case .debug: CompanionTheme.amber
        case .all, .defaultLevel: CompanionTheme.textSecondary
        }
    }
}

extension Color {
    init(hex: String) {
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
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

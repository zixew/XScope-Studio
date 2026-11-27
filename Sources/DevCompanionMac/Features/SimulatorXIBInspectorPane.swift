import SwiftUI
import DevCompanionCore

enum XIBInspectorTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case style = "Style"
    case constraints = "Constraints"
    case code = "Code"
    case actions = "Actions"

    var id: String { rawValue }
}

struct SimulatorXIBInspectorPane: View {
    @Bindable var presenter: SimulatorPresenter
    @State private var selectedTab: XIBInspectorTab = .info

    var body: some View {
        GlassCard {
            if let draft = presenter.draftNode {
                VStack(alignment: .leading, spacing: 10) {
                    headerBar(node: draft)
                    draftStatusBar
                    tabBar
                    Divider()

                    ScrollView {
                        switch selectedTab {
                        case .info:
                            infoTab(node: draft)
                        case .style:
                            styleTab
                        case .constraints:
                            constraintsTab
                        case .code:
                            codeTab(node: draft)
                        case .actions:
                            actionsTab(node: draft)
                        }
                    }
                    .frame(maxHeight: 410)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 26))
                        .foregroundStyle(CompanionTheme.textMuted)
                    Text("Click 1× or 2× on any component in 2D/3D to inspect its info, XIB properties, constraints, code, and actions safely.")
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 430, alignment: .center)
                .padding()
            }
        }
        .frame(minWidth: 280, idealWidth: 330, maxWidth: 370)
    }

    private func headerBar(node: UIComponentNode) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Z\(node.zLayer)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: node.accentHex).opacity(0.25))
                        .foregroundStyle(Color(hex: node.accentHex))
                        .clipShape(Capsule())
                    Text(node.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CompanionTheme.textPrimary)
                        .lineLimit(1)
                }
                Text("\(node.kind.rawValue) • \(node.locationLabel)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CompanionTheme.mint)
                    .lineLimit(1)
            }
            Spacer()
            Button(AppStrings.Performance.openInXcode) {
                Task { await presenter.openSelectedComponentInXcode() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!presenter.hasProject)
        }
    }

    private var draftStatusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(presenter.hasUnappliedChanges ? CompanionTheme.amber : CompanionTheme.mint)
                    .frame(width: 7, height: 7)
                Text(presenter.hasUnappliedChanges ? "Unapplied Draft (Inspecting safely)" : "Inspected • No Pending Edits")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(presenter.hasUnappliedChanges ? CompanionTheme.amber : CompanionTheme.textSecondary)
                Spacer()
            }

            FlowLayout(spacing: 6) {
                Button("Apply Preview") {
                    presenter.applyDraftToPreview()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(!presenter.hasUnappliedChanges)

                Button("Apply to Xcode") {
                    presenter.applyComponentChangesToSwiftCode()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!presenter.hasProject)

                if presenter.hasUnappliedChanges {
                    Button("Discard") {
                        presenter.discardDraft()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if presenter.lastComponentRevertRecord != nil {
                    Button(AppStrings.Performance.undoPatch) {
                        presenter.undoLastComponentPatch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(CompanionTheme.glassLow))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(XIBInspectorTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.white : CompanionTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? CompanionTheme.accent.opacity(0.85) : Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func infoTab(node: UIComponentNode) -> some View {
        let ptMetrics = UIHierarchyInspectorService.pointFrameAndBounds(for: node)
        let inheritance = UIHierarchyInspectorService.classInheritanceChain(for: node.kind, className: node.className)
        return VStack(alignment: .leading, spacing: 8) {
            infoRow("Class", node.className)
            infoRow("Inheritance", inheritance.joined(separator: " → "))
            infoRow("Component", node.name)
            infoRow("Kind", node.kind.rawValue)
            infoRow("Source", node.locationLabel)
            infoRow("Frame (pt)", String(format: "x:%.0f y:%.0f w:%.0f h:%.0f", ptMetrics.frame.origin.x, ptMetrics.frame.origin.y, ptMetrics.frame.size.width, ptMetrics.frame.size.height))
            infoRow("Bounds (pt)", String(format: "x:0 y:0 w:%.0f h:%.0f", ptMetrics.bounds.size.width, ptMetrics.bounds.size.height))
            infoRow("Normalized", String(format: "x:%.2f y:%.2f w:%.2f h:%.2f", node.normalizedX, node.normalizedY, node.normalizedWidth, node.normalizedHeight))
            infoRow("Hugging H / V", node.kind == .label || node.kind == .button ? "251 / 251" : "250 / 250")
            infoRow("Compression H / V", "750 / 750")
            infoRow("Interaction / Clip", "\(node.isUserInteractionEnabled ? "Enabled" : "Off") • \(node.clipsToBounds ? "Clips" : "NoClip")")
            infoRow("Actions Found", "\(node.actions.count)")
            infoRow("Debug Bridge", presenter.isDebugBridgeConnected ? "Connected (:49876)" : "Zero-SDK Mode")

            VStack(alignment: .leading, spacing: 4) {
                Text("Source Declaration")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textSecondary)
                CodeSurfaceContainer(padding: 8) {
                    XcodeCodeText(code: node.codeSnippet, fontSize: 11)
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(CompanionTheme.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(CompanionTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var styleTab: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let _ = presenter.draftNode {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Text / Title")
                        .font(.system(size: 10))
                        .foregroundStyle(CompanionTheme.textSecondary)
                    TextField("Title", text: draftBinding(\.displayText))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }

                HStack {
                    Text("Accent Hex")
                        .font(.system(size: 10))
                        .foregroundStyle(CompanionTheme.textSecondary)
                    Spacer()
                    TextField("#HEX", text: draftBinding(\.accentHex))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 85)
                }

                HStack(spacing: 6) {
                    ForEach(["#007AFF", "#1C7ED6", "#20C997", "#F59F00", "#FF6B6B", "#7950F2"], id: \.self) { preset in
                        Button {
                            presenter.draftNode?.accentHex = preset
                        } label: {
                            Circle()
                                .fill(Color(hex: preset))
                                .frame(width: 17, height: 17)
                                .overlay(
                                    Circle()
                                        .stroke(presenter.draftNode?.accentHex == preset ? Color.white : .clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("Background Hex")
                        .font(.system(size: 10))
                        .foregroundStyle(CompanionTheme.textSecondary)
                    Spacer()
                    TextField("#HEX", text: draftBinding(\.backgroundHex))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 85)
                }

                sliderRow("Corner Radius", value: draftBinding(\.cornerRadius), range: 0...32, suffix: "pt")
                sliderRow("Border Width", value: draftBinding(\.borderWidth), range: 0...6, suffix: "pt")
                sliderRow("Font Size", value: draftBinding(\.fontSize), range: 9...28, suffix: "pt")
                sliderRow("Opacity", value: draftBinding(\.opacity), range: 0.1...1.0, isPercent: true)

                Toggle("Hidden", isOn: draftBinding(\.isHidden))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                Toggle("Clips To Bounds", isOn: draftBinding(\.clipsToBounds))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                Toggle("User Interaction Enabled", isOn: draftBinding(\.isUserInteractionEnabled))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
            }
        }
    }

    private var constraintsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frame & AutoLayout Constants")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CompanionTheme.textSecondary)

            sliderRow("Norm X", value: draftBinding(\.normalizedX), range: 0.0...0.95, decimals: 2)
            sliderRow("Norm Y", value: draftBinding(\.normalizedY), range: 0.0...0.95, decimals: 2)
            sliderRow("Norm Width", value: draftBinding(\.normalizedWidth), range: 0.05...1.0, decimals: 2)
            sliderRow("Norm Height", value: draftBinding(\.normalizedHeight), range: 0.03...1.0, decimals: 2)

            Divider()

            constraintField("Top", binding: optionalConstraintBinding(\.top))
            constraintField("Leading", binding: optionalConstraintBinding(\.leading))
            constraintField("Trailing", binding: optionalConstraintBinding(\.trailing))
            constraintField("Bottom", binding: optionalConstraintBinding(\.bottom))
            constraintField("Width", binding: optionalConstraintBinding(\.width))
            constraintField("Height", binding: optionalConstraintBinding(\.height))
        }
    }

    private func codeTab(node: UIComponentNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live Component Swift Code")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CompanionTheme.textSecondary)
                Spacer()
                Button("Preview in 2D/3D") {
                    presenter.applyDraftToPreview()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Button("Apply to Xcode") {
                    presenter.applyDirectCodeToXcode()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!presenter.hasProject)
            }

            Text("Edit properties or constraints in Swift syntax below and click 'Preview in 2D/3D' to update the canvas live.")
                .font(.system(size: 9.5))
                .foregroundStyle(CompanionTheme.textMuted)

            CodeSurfaceContainer(padding: 8) {
                TextEditor(text: $presenter.draftSourceSlice)
                    .font(.system(size: 11, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(CompanionTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(height: 265)
            }
        }
    }

    private func actionsTab(node: UIComponentNode) -> some View {
        let isInteractiveKind = [.button, .control, .actionGrid, .cell].contains(node.kind)
        return VStack(alignment: .leading, spacing: 10) {
            if isInteractiveKind || !node.actions.isEmpty {
                FlowLayout(spacing: 6) {
                    Button("Tap in Simulator") {
                        Task { await presenter.triggerComponentTapInSimulator() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Install Debug Bridge") {
                        presenter.installDebugBridgeInProject()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!presenter.hasProject)
                }
            }

            if !presenter.lastActionStatus.isEmpty {
                Text(presenter.lastActionStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(CompanionTheme.mint)
            }

            if node.actions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isInteractiveKind
                         ? "No explicit @IBAction or #selector matched '\(node.name)' in \(node.fileName). You can trigger it directly via 'Tap in Simulator'."
                         : "This component (\(node.kind.rawValue)) is a non-interactive view and has no bound action in code.")
                        .font(.system(size: 11))
                        .foregroundStyle(CompanionTheme.textSecondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(node.actions) { act in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(act.kind.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CompanionTheme.accent.opacity(0.2))
                                .foregroundStyle(CompanionTheme.accent)
                                .clipShape(Capsule())
                            Text(act.name)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CompanionTheme.textPrimary)
                            Spacer()
                            Button("Run") {
                                Task { await presenter.invokeActionViaBridge(act) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                        CodeSurfaceContainer(padding: 6) {
                            XcodeCodeText(code: act.bodySnippet, fontSize: 10.5)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(CompanionTheme.glassLow))
                }
            }
        }
    }

    private func draftBinding<T>(_ keyPath: WritableKeyPath<UIComponentNode, T>) -> Binding<T> {
        Binding(
            get: { presenter.draftNode![keyPath: keyPath] },
            set: { presenter.draftNode?[keyPath: keyPath] = $0 }
        )
    }

    private func optionalConstraintBinding(_ keyPath: WritableKeyPath<ComponentConstraints, Double?>) -> Binding<String> {
        Binding(
            get: {
                if let val = presenter.draftNode?.constraints[keyPath: keyPath] {
                    return "\(Int(val.rounded()))"
                }
                return ""
            },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                presenter.draftNode?.constraints[keyPath: keyPath] = trimmed.isEmpty ? nil : Double(trimmed)
            }
        )
    }

    private func constraintField(_ label: String, binding: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(CompanionTheme.textSecondary)
            Spacer()
            TextField("auto", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 80)
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String = "",
        decimals: Int = 0,
        isPercent: Bool = false
    ) -> some View {
        let display: String = isPercent
            ? "\(Int((value.wrappedValue * 100).rounded()))%"
            : (decimals == 0 ? "\(Int(value.wrappedValue.rounded()))\(suffix)" : String(format: "%.\(decimals)f\(suffix)", value.wrappedValue))
        return HStack {
            Text("\(title): \(display)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(CompanionTheme.textSecondary)
            Spacer()
            Slider(value: value, in: range)
                .frame(width: 110)
        }
    }
}

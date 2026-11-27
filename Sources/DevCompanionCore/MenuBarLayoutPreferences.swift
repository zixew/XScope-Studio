import Foundation

public enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case terminal = "terminal"
    case scope = "scope"
    case bolt = "bolt.fill"
    case waveform = "waveform.path.ecg"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .scope: "Scope Reticle"
        case .bolt: "Bolt"
        case .waveform: "Telemetry Pulse"
        }
    }
}

public enum MenuBarPopoverDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case detailed = "detailed"
    case compact = "compact"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .detailed: "Detailed"
        case .compact: "Compact"
        }
    }
}

public enum MenuBarSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case target = "target"
    case running = "running"
    case controls = "controls"
    case status = "status"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .target: "Active Target & Project"
        case .running: "Running Now"
        case .controls: "Quick Controls"
        case .status: "Last Status"
        }
    }
}

public struct MenuBarSectionItem: Codable, Equatable, Identifiable, Sendable {
    public var kind: MenuBarSectionKind
    public var isEnabled: Bool

    public var id: String { kind.rawValue }

    public init(kind: MenuBarSectionKind, isEnabled: Bool = true) {
        self.kind = kind
        self.isEnabled = isEnabled
    }
}

public struct MenuBarLayoutConfig: Codable, Equatable, Sendable {
    public var iconStyle: MenuBarIconStyle
    public var showTargetBadge: Bool
    public var showLiveMetrics: Bool
    public var density: MenuBarPopoverDensity
    public var sections: [MenuBarSectionItem]

    public init(
        iconStyle: MenuBarIconStyle = .terminal,
        showTargetBadge: Bool = true,
        showLiveMetrics: Bool = true,
        density: MenuBarPopoverDensity = .detailed,
        sections: [MenuBarSectionItem] = MenuBarSectionKind.allCases.map { MenuBarSectionItem(kind: $0, isEnabled: true) }
    ) {
        self.iconStyle = iconStyle
        self.showTargetBadge = showTargetBadge
        self.showLiveMetrics = showLiveMetrics
        self.density = density
        self.sections = sections
    }

    public mutating func moveSection(at index: Int, offset: Int) {
        let dest = index + offset
        guard sections.indices.contains(index), sections.indices.contains(dest) else { return }
        sections.swapAt(index, dest)
    }
}

public final class MenuBarLayoutStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "xscope.menubar.layout.config") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> MenuBarLayoutConfig {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(MenuBarLayoutConfig.self, from: data) else {
            return MenuBarLayoutConfig()
        }
        return decoded
    }

    public func save(_ config: MenuBarLayoutConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
        }
    }
}

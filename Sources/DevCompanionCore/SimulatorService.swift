import Foundation

public struct SimulatorDevice: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let runtime: String
    public let state: String

    public var isBooted: Bool { state.lowercased() == "booted" }

    public init(id: String, name: String, runtime: String, state: String) {
        self.id = id
        self.name = name
        self.runtime = runtime
        self.state = state
    }
}

public enum SimulatorAppearance: String, CaseIterable, Sendable {
    case dark
    case light
}

public enum DynamicTypeSizeOption: String, CaseIterable, Sendable, Identifiable {
    case small = "S"
    case medium = "M"
    case large = "L"
    case extraLarge = "XL"
    case accessibilityExtraLarge = "AX-XL"

    public var id: String { rawValue }

    var simctlCategory: String {
        switch self {
        case .small: "UICTContentSizeCategoryS"
        case .medium: "UICTContentSizeCategoryM"
        case .large: "UICTContentSizeCategoryL"
        case .extraLarge: "UICTContentSizeCategoryXL"
        case .accessibilityExtraLarge: "UICTContentSizeCategoryAccessibilityXL"
        }
    }
}

public struct PhysicalDevice: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let modelName: String
    public let osVersion: String
    public let connectionType: String
    public let isConnected: Bool

    public var isWiredUSB: Bool {
        let lower = connectionType.lowercased()
        return lower == "wired" || lower == "usb"
    }

    public var connectionBadge: String {
        isWiredUSB ? "USB" : "Wi-Fi"
    }

    public init(
        id: String,
        name: String,
        modelName: String = "iPhone",
        osVersion: String,
        connectionType: String,
        isConnected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.osVersion = osVersion
        self.connectionType = connectionType
        self.isConnected = isConnected
    }
}

/// Controls iOS Simulators (`xcrun simctl`) and discovers physical iOS devices (`xcrun devicectl`).
public struct SimulatorService: Sendable {
    private let runner: any CommandExecuting

    public init(runner: any CommandExecuting = ProcessRunner()) {
        self.runner = runner
    }

    public func listSimulators() async throws -> [SimulatorDevice] {
        let output = try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "--json"], workingDirectory: nil)
        guard output.isSuccess, let data = output.stdout.data(using: .utf8) else {
            return []
        }
        return Self.parseSimctlDevices(from: data)
    }

    public func setAppearance(_ appearance: SimulatorAppearance, udid: String = "booted") async throws -> CommandOutput {
        try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "ui", udid, "appearance", appearance.rawValue], workingDirectory: nil)
    }

    public func setDynamicType(_ size: DynamicTypeSizeOption, udid: String = "booted") async throws -> CommandOutput {
        try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "ui", udid, "content_size", size.simctlCategory], workingDirectory: nil)
    }

    public func overrideStatusBarClean(udid: String = "booted") async throws -> CommandOutput {
        try await runner.run(
            "/usr/bin/xcrun",
            arguments: [
                "simctl", "status_bar", udid, "override",
                "--time", "9:41",
                "--batteryState", "charged",
                "--batteryLevel", "100",
                "--wifiBars", "3",
                "--cellularBars", "4"
            ],
            workingDirectory: nil
        )
    }

    public func clearStatusBarOverride(udid: String = "booted") async throws -> CommandOutput {
        try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "status_bar", udid, "clear"], workingDirectory: nil)
    }

    public func openDeepLink(_ urlString: String, udid: String = "booted") async throws -> CommandOutput {
        try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "openurl", udid, urlString], workingDirectory: nil)
    }

    public func captureScreenshot(to fileURL: URL, udid: String = "booted") async throws -> CommandOutput {
        try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "io", udid, "screenshot", fileURL.path], workingDirectory: nil)
    }

    public func bootSimulator(udid: String) async throws -> CommandOutput {
        try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "boot", udid], workingDirectory: nil)
    }

    public func shutdownSimulator(udid: String) async throws -> CommandOutput {
        try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "shutdown", udid], workingDirectory: nil)
    }

    public func deleteUnavailableSimulators() async throws -> CommandOutput {
        try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"], workingDirectory: nil)
    }

    public func capturePhysicalDeviceScreenshot(deviceID: String, to fileURL: URL) async throws -> CommandOutput {
        try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "device", "capture", "screenshot", "--device", deviceID, "--destination", fileURL.path],
            workingDirectory: nil
        )
    }

    public func sendPushNotification(bundleID: String, title: String, body: String, udid: String = "booted") async throws -> CommandOutput {
        let payload: [String: Any] = [
            "aps": [
                "alert": [
                    "title": title,
                    "body": body
                ],
                "sound": "default"
            ]
        ]
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("devcompanion_push_\(UUID().uuidString).apns")
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try await runner.run("/usr/bin/xcrun", arguments: ["simctl", "push", udid, bundleID, tempURL.path], workingDirectory: nil)
    }

    public func listPhysicalDevices() async throws -> [PhysicalDevice] {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("devcompanion_devices_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let output = try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--json-output", tempURL.path],
            workingDirectory: nil
        )
        guard output.isSuccess, let data = try? Data(contentsOf: tempURL) else {
            return []
        }
        // Only surface actively connected / connectable physical devices at runtime
        return Self.parseDevicectlDevices(from: data).filter(\.isConnected)
    }

    // MARK: - Parsers

    static func parseSimctlDevices(from data: Data) -> [SimulatorDevice] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devicesByRuntime = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var result: [SimulatorDevice] = []
        for (runtimeKey, entries) in devicesByRuntime {
            let readableRuntime = runtimeKey
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
            for entry in entries {
                guard
                    let isAvailable = entry["isAvailable"] as? Bool, isAvailable,
                    let udid = entry["udid"] as? String,
                    let name = entry["name"] as? String,
                    let state = entry["state"] as? String
                else { continue }
                result.append(SimulatorDevice(id: udid, name: name, runtime: readableRuntime, state: state))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.isBooted != rhs.isBooted { return lhs.isBooted }
            return lhs.name < rhs.name
        }
    }

    static func parseDevicectlDevices(from data: Data) -> [PhysicalDevice] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resultObj = json["result"] as? [String: Any],
            let devices = resultObj["devices"] as? [[String: Any]]
        else { return [] }

        let parsed = devices.compactMap { entry -> PhysicalDevice? in
            guard
                let identifier = entry["identifier"] as? String,
                let deviceProps = entry["deviceProperties"] as? [String: Any],
                let name = deviceProps["name"] as? String
            else { return nil }

            let osVersion = (deviceProps["osVersionNumber"] as? String) ?? "iOS"
            let hwProps = entry["hardwareProperties"] as? [String: Any]
            let modelName = (hwProps?["marketingName"] as? String)
                ?? (hwProps?["productType"] as? String)
                ?? (hwProps?["deviceType"] as? String)
                ?? "iPhone"
            let props = entry["properties"] as? [String: Any]
            let connPropsNew = props?["connection"] as? [String: Any]
            let modernState = (connPropsNew?["state"] as? String)?.lowercased()

            let connProps = entry["connectionProperties"] as? [String: Any]
            let transport = (connProps?["transportType"] as? String)
                ?? (connPropsNew?["authenticationType"] as? String)
                ?? "USB/Wi-Fi"
            let tunnelState = (connProps?["tunnelState"] as? String)?.lowercased() ?? ""
            let pairingState = (connProps?["pairingState"] as? String)?.lowercased()
                ?? (connPropsNew?["pairingState"] as? String)?.lowercased()
                ?? ""
            let hasExplicitTransport = connProps?["transportType"] != nil

            let isConnected: Bool
            if let modernState {
                isConnected = (modernState == "connected" || modernState == "connecting")
            } else if let connProps {
                if tunnelState == "disconnected" || tunnelState == "unavailable" || pairingState == "unpaired" {
                    isConnected = false
                } else if tunnelState == "connected" || tunnelState == "connecting" || hasExplicitTransport {
                    isConnected = true
                } else {
                    isConnected = connProps.isEmpty
                }
            } else {
                isConnected = true
            }

            return PhysicalDevice(
                id: identifier,
                name: name,
                modelName: modelName,
                osVersion: osVersion,
                connectionType: transport,
                isConnected: isConnected
            )
        }

        let connected = parsed.filter(\.isConnected).sorted { lhs, rhs in
            if lhs.isWiredUSB != rhs.isWiredUSB { return lhs.isWiredUSB }
            return lhs.name < rhs.name
        }
        let disconnected = parsed.filter { !$0.isConnected }
        return connected + disconnected
    }
}

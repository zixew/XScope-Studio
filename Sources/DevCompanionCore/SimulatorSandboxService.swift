import Foundation

public struct SandboxUserDefaultEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.id = key
        self.key = key
        self.value = value
    }
}

public struct SimulatorSandboxSnapshot: Sendable, Equatable {
    public let containerPath: String
    public let documentsFiles: [String]
    public let cachesCount: Int
    public let userDefaults: [SandboxUserDefaultEntry]

    public init(
        containerPath: String,
        documentsFiles: [String],
        cachesCount: Int,
        userDefaults: [SandboxUserDefaultEntry]
    ) {
        self.containerPath = containerPath
        self.documentsFiles = documentsFiles
        self.cachesCount = cachesCount
        self.userDefaults = userDefaults
    }
}

public enum SimulatorPrivacyService: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case location = "location"
    case camera = "camera"
    case photos = "photos"
    case notifications = "notifications"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .all: "All Permissions"
        case .location: "Location"
        case .camera: "Camera"
        case .photos: "Photos"
        case .notifications: "Notifications"
        }
    }
}

public struct SimulatorSandboxService: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func inspectDataContainer(udid: String, bundleID: String) async throws -> SimulatorSandboxSnapshot {
        let out = try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "get_app_container", udid, bundleID, "data"],
            workingDirectory: nil
        )
        guard out.isSuccess else {
            throw CompanionError.commandFailed(
                executable: "xcrun",
                exitCode: out.exitCode,
                stderr: out.stderr.isEmpty ? "Container not found for \(bundleID)" : out.stderr
            )
        }
        let containerPath = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let containerURL = URL(fileURLWithPath: containerPath, isDirectory: true)
        let fm = FileManager.default

        let docsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        let docsFiles = (try? fm.contentsOfDirectory(atPath: docsURL.path))?.sorted().prefix(40).map { $0 } ?? []

        let cachesURL = containerURL.appendingPathComponent("Library/Caches", isDirectory: true)
        let cachesCount = (try? fm.contentsOfDirectory(atPath: cachesURL.path))?.count ?? 0

        let plistURL = containerURL.appendingPathComponent("Library/Preferences/\(bundleID).plist")
        let plistData = (try? Data(contentsOf: plistURL)) ?? Data()
        let userDefaults = Self.parseUserDefaultsPlist(data: plistData)

        return SimulatorSandboxSnapshot(
            containerPath: containerPath,
            documentsFiles: docsFiles,
            cachesCount: cachesCount,
            userDefaults: userDefaults
        )
    }

    public static func parseUserDefaultsPlist(data: Data) -> [SandboxUserDefaultEntry] {
        guard !data.isEmpty,
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return []
        }
        return dict.keys.sorted().prefix(80).map { key in
            SandboxUserDefaultEntry(key: key, value: String(describing: dict[key] ?? ""))
        }
    }

    public func setLocation(latitude: Double, longitude: Double, udid: String) async throws -> CommandOutput {
        try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "location", udid, "set", "\(latitude),\(longitude)"],
            workingDirectory: nil
        )
    }

    public func resetPrivacy(service: SimulatorPrivacyService, udid: String) async throws -> CommandOutput {
        try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "privacy", udid, "reset", service.rawValue],
            workingDirectory: nil
        )
    }
}

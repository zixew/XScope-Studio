import Foundation

public struct BuildTimingTarget: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let targetName: String
    public let projectName: String
    public let durationSeconds: Double
    public let logDate: Date

    public init(
        id: UUID = UUID(),
        targetName: String,
        projectName: String,
        durationSeconds: Double,
        logDate: Date
    ) {
        self.id = id
        self.targetName = targetName
        self.projectName = projectName
        self.durationSeconds = durationSeconds
        self.logDate = logDate
    }

    public var formattedDuration: String {
        String(format: "%.2fs", durationSeconds)
    }
}

public struct ProvisioningProfileSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let appIDName: String
    public let teamName: String
    public let expirationDate: Date
    public let entitlementsCount: Int
    public let filePath: String

    public init(
        id: UUID = UUID(),
        name: String,
        appIDName: String,
        teamName: String,
        expirationDate: Date,
        entitlementsCount: Int,
        filePath: String
    ) {
        self.id = id
        self.name = name
        self.appIDName = appIDName
        self.teamName = teamName
        self.expirationDate = expirationDate
        self.entitlementsCount = entitlementsCount
        self.filePath = filePath
    }

    public var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
    }

    public var isExpired: Bool {
        expirationDate < Date()
    }
}

public struct BuildAndSigningInspector: Sendable {
    public init() {}

    /// Scans newest `.xcactivitylog` files under DerivedData and extracts build target durations.
    public func scanRecentBuildTimings(derivedDataURL: URL? = nil, maxLogs: Int = 4) -> [BuildTimingTarget] {
        let fileManager = FileManager.default
        let root = derivedDataURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var logFiles: [(url: URL, project: String, mdate: Date)] = []
        for dir in projectDirs {
            let buildLogsDir = dir.appendingPathComponent("Logs/Build", isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: buildLogsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let projectName = dir.lastPathComponent.split(separator: "-").dropLast().joined(separator: "-")
            let displayProject = projectName.isEmpty ? dir.lastPathComponent : projectName

            for file in files where file.pathExtension == "xcactivitylog" {
                let mdate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                logFiles.append((file, displayProject, mdate))
            }
        }

        let newestLogs = logFiles.sorted { $0.mdate > $1.mdate }.prefix(maxLogs)
        var results: [BuildTimingTarget] = []

        for entry in newestLogs {
            guard let text = decompressGzipText(at: entry.url) else { continue }
            let parsed = Self.parseBuildTimings(fromActivityLogText: text, projectName: entry.project, logDate: entry.mdate)
            results.append(contentsOf: parsed)
        }

        return results.sorted { $0.durationSeconds > $1.durationSeconds }
    }

    /// Parses target build timings from decompressed `.xcactivitylog` SLF text.
    public static func parseBuildTimings(
        fromActivityLogText text: String,
        projectName: String,
        logDate: Date
    ) -> [BuildTimingTarget] {
        // SLF tokens often contain readable strings like "Build target Foo (1.23 seconds)" or "CompileSwift ... (0.45 seconds)"
        let pattern = #"(?:Build target|Build)\s+([A-Za-z0-9_.\- ]+?)\s*\((\d+(?:\.\d+)?)\s+seconds?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: min(nsText.length, 400_000)))

        var byTarget: [String: BuildTimingTarget] = [:]
        for match in matches where match.numberOfRanges >= 3 {
            let target = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let seconds = Double(nsText.substring(with: match.range(at: 2))) ?? 0
            guard !target.isEmpty, seconds > 0 else { continue }
            if let existing = byTarget[target], existing.durationSeconds >= seconds {
                continue
            }
            byTarget[target] = BuildTimingTarget(
                targetName: target,
                projectName: projectName,
                durationSeconds: seconds,
                logDate: logDate
            )
        }
        return Array(byTarget.values).sorted { $0.durationSeconds > $1.durationSeconds }
    }

    /// Scans local `.mobileprovision` files and extracts expiry + entitlements metadata.
    public func scanProvisioningProfiles(searchDirectories: [URL]? = nil) -> [ProvisioningProfileSummary] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let dirs = searchDirectories ?? [
            home.appendingPathComponent("Library/MobileDevice/Provisioning Profiles", isDirectory: true),
            home.appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles", isDirectory: true)
        ]

        var summaries: [ProvisioningProfileSummary] = []
        for dir in dirs {
            guard let files = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "mobileprovision" {
                guard let data = try? Data(contentsOf: file),
                      let parsed = Self.parseProvisioningProfile(data: data, filePath: file.path) else {
                    continue
                }
                summaries.append(parsed)
            }
        }
        return summaries.sorted { $0.expirationDate < $1.expirationDate }
    }

    public static func parseProvisioningProfile(data: Data, filePath: String) -> ProvisioningProfileSummary? {
        guard let rawString = String(data: data, encoding: .isoLatin1),
              let startRange = rawString.range(of: "<plist"),
              let endRange = rawString.range(of: "</plist>") else {
            return nil
        }

        let plistString = String(rawString[startRange.lowerBound..<endRange.upperBound])
        guard let plistData = plistString.data(using: .utf8),
              let dict = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }

        let name = (dict["Name"] as? String) ?? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        let appIDName = (dict["AppIDName"] as? String) ?? "Unknown App ID"
        let teamName = (dict["TeamName"] as? String) ?? ((dict["TeamIdentifier"] as? [String])?.first ?? "Unknown Team")
        let expirationDate = (dict["ExpirationDate"] as? Date) ?? Date.distantPast
        let entitlements = (dict["Entitlements"] as? [String: Any]) ?? [:]

        return ProvisioningProfileSummary(
            name: name,
            appIDName: appIDName,
            teamName: teamName,
            expirationDate: expirationDate,
            entitlementsCount: entitlements.count,
            filePath: filePath
        )
    }

    private func decompressGzipText(at url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }
}

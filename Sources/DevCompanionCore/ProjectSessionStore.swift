import Foundation
import CryptoKit

/// Persistent snapshot of all recorded diagnostics, telemetry, review findings, unit tests, and L10n state for a single Xcode project.
public struct ProjectSessionSnapshot: Codable, Sendable, Equatable {
    public var projectPath: String
    public var projectName: String
    public var updatedAt: Date

    // Performance & Telemetry
    public var liveCPU: Double
    public var liveMemoryMB: Double
    public var cpuHistory: [Double]
    public var memoryHistory: [Double]
    public var lastHangSeconds: Double?
    public var selectedProcessName: String?
    public var capturedFreezeEvents: [FreezeLagEvent]

    // Crashlytics
    public var selectedReportPath: String?
    public var selectedReportName: String
    public var selectedReportContent: String
    public var activeCrashAnalysis: CrashAnalysisReport?

    // Code Review & Leaks
    public var findings: [CodeReviewFinding]
    public var hasAnalyzed: Bool

    // Unit Tests
    public var sourceFileName: String
    public var testModuleName: String
    public var xcodeProjectPath: String
    public var schemeName: String
    public var discoveredSchemes: [String]
    public var generatedTestCode: String

    // Utilities & Live Refresh
    public var missingLocalizations: [LocalizationMissingEntry]
    public var liveReloadScheme: String
    public var lastReloadSummary: String

    public init(
        projectPath: String,
        projectName: String,
        updatedAt: Date = Date(),
        liveCPU: Double = 0,
        liveMemoryMB: Double = 0,
        cpuHistory: [Double] = Array(repeating: 0, count: 40),
        memoryHistory: [Double] = Array(repeating: 0, count: 40),
        lastHangSeconds: Double? = nil,
        selectedProcessName: String? = nil,
        capturedFreezeEvents: [FreezeLagEvent] = [],
        selectedReportPath: String? = nil,
        selectedReportName: String = "",
        selectedReportContent: String = "",
        activeCrashAnalysis: CrashAnalysisReport? = nil,
        findings: [CodeReviewFinding] = [],
        hasAnalyzed: Bool = false,
        sourceFileName: String = "",
        testModuleName: String = "",
        xcodeProjectPath: String = "",
        schemeName: String = "",
        discoveredSchemes: [String] = [],
        generatedTestCode: String = "",
        missingLocalizations: [LocalizationMissingEntry] = [],
        liveReloadScheme: String = "",
        lastReloadSummary: String = ""
    ) {
        self.projectPath = projectPath
        self.projectName = projectName
        self.updatedAt = updatedAt
        self.liveCPU = liveCPU
        self.liveMemoryMB = liveMemoryMB
        self.cpuHistory = cpuHistory
        self.memoryHistory = memoryHistory
        self.lastHangSeconds = lastHangSeconds
        self.selectedProcessName = selectedProcessName
        self.capturedFreezeEvents = capturedFreezeEvents
        self.selectedReportPath = selectedReportPath
        self.selectedReportName = selectedReportName
        self.selectedReportContent = selectedReportContent
        self.activeCrashAnalysis = activeCrashAnalysis
        self.findings = findings
        self.hasAnalyzed = hasAnalyzed
        self.sourceFileName = sourceFileName
        self.testModuleName = testModuleName
        self.xcodeProjectPath = xcodeProjectPath
        self.schemeName = schemeName
        self.discoveredSchemes = discoveredSchemes
        self.generatedTestCode = generatedTestCode
        self.missingLocalizations = missingLocalizations
        self.liveReloadScheme = liveReloadScheme
        self.lastReloadSummary = lastReloadSummary
    }

    enum CodingKeys: String, CodingKey {
        case projectPath, projectName, updatedAt
        case liveCPU, liveMemoryMB, cpuHistory, memoryHistory, lastHangSeconds, selectedProcessName, capturedFreezeEvents
        case selectedReportPath, selectedReportName, selectedReportContent, activeCrashAnalysis
        case findings, hasAnalyzed
        case sourceFileName, testModuleName, xcodeProjectPath, schemeName, discoveredSchemes, generatedTestCode
        case missingLocalizations, liveReloadScheme, lastReloadSummary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        projectName = try c.decode(String.self, forKey: .projectName)
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
        liveCPU = (try? c.decode(Double.self, forKey: .liveCPU)) ?? 0
        liveMemoryMB = (try? c.decode(Double.self, forKey: .liveMemoryMB)) ?? 0
        cpuHistory = (try? c.decode([Double].self, forKey: .cpuHistory)) ?? Array(repeating: 0, count: 40)
        memoryHistory = (try? c.decode([Double].self, forKey: .memoryHistory)) ?? Array(repeating: 0, count: 40)
        lastHangSeconds = try? c.decodeIfPresent(Double.self, forKey: .lastHangSeconds)
        selectedProcessName = try? c.decodeIfPresent(String.self, forKey: .selectedProcessName)
        capturedFreezeEvents = (try? c.decode([FreezeLagEvent].self, forKey: .capturedFreezeEvents)) ?? []
        selectedReportPath = try? c.decodeIfPresent(String.self, forKey: .selectedReportPath)
        selectedReportName = (try? c.decode(String.self, forKey: .selectedReportName)) ?? ""
        selectedReportContent = (try? c.decode(String.self, forKey: .selectedReportContent)) ?? ""
        activeCrashAnalysis = try? c.decodeIfPresent(CrashAnalysisReport.self, forKey: .activeCrashAnalysis)
        findings = (try? c.decode([CodeReviewFinding].self, forKey: .findings)) ?? []
        hasAnalyzed = (try? c.decode(Bool.self, forKey: .hasAnalyzed)) ?? false
        sourceFileName = (try? c.decode(String.self, forKey: .sourceFileName)) ?? ""
        testModuleName = (try? c.decode(String.self, forKey: .testModuleName)) ?? ""
        xcodeProjectPath = (try? c.decode(String.self, forKey: .xcodeProjectPath)) ?? ""
        schemeName = (try? c.decode(String.self, forKey: .schemeName)) ?? ""
        discoveredSchemes = (try? c.decode([String].self, forKey: .discoveredSchemes)) ?? []
        generatedTestCode = (try? c.decode(String.self, forKey: .generatedTestCode)) ?? ""
        missingLocalizations = (try? c.decode([LocalizationMissingEntry].self, forKey: .missingLocalizations)) ?? []
        liveReloadScheme = (try? c.decode(String.self, forKey: .liveReloadScheme)) ?? ""
        lastReloadSummary = (try? c.decode(String.self, forKey: .lastReloadSummary)) ?? ""
    }
}

public struct ProjectSessionBackup: Codable, Sendable, Equatable {
    public var exportedAt: Date
    public var appVersion: String
    public var sessions: [ProjectSessionSnapshot]

    public init(exportedAt: Date = Date(), appVersion: String = "1.0", sessions: [ProjectSessionSnapshot]) {
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.sessions = sessions
    }
}

public protocol ProjectSessionStoring: Sendable {
    func save(_ snapshot: ProjectSessionSnapshot) throws
    func load(for projectURL: URL) -> ProjectSessionSnapshot?
    func delete(for projectURL: URL) throws
    func loadAll() -> [ProjectSessionSnapshot]
    func exportBackup(to destinationURL: URL, projectURL: URL?) throws
    func importBackup(from sourceURL: URL) throws -> Int
}

public struct FileProjectSessionStore: ProjectSessionStoring {
    public let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.baseDirectory = appSupport
                .appendingPathComponent("DevCompanion", isDirectory: true)
                .appendingPathComponent("Sessions", isDirectory: true)
        }
    }

    public func save(_ snapshot: ProjectSessionSnapshot) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let url = fileURL(forPath: snapshot.projectPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public func load(for projectURL: URL) -> ProjectSessionSnapshot? {
        let url = fileURL(forPath: projectURL.path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProjectSessionSnapshot.self, from: data)
    }

    public func delete(for projectURL: URL) throws {
        let url = fileURL(forPath: projectURL.path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func loadAll() -> [ProjectSessionSnapshot] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ProjectSessionSnapshot.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func exportBackup(to destinationURL: URL, projectURL: URL?) throws {
        let sessions: [ProjectSessionSnapshot]
        if let projectURL, let single = load(for: projectURL) {
            sessions = [single]
        } else {
            sessions = loadAll()
        }
        let backup = ProjectSessionBackup(sessions: sessions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        try data.write(to: destinationURL, options: .atomic)
    }

    public func importBackup(from sourceURL: URL) throws -> Int {
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(ProjectSessionBackup.self, from: data)
        for session in backup.sessions {
            try save(session)
        }
        return backup.sessions.count
    }

    private func fileURL(forPath path: String) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex8 = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        let rawName = URL(fileURLWithPath: path).lastPathComponent
        let safeName = rawName.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return baseDirectory.appendingPathComponent("\(safeName)_\(hex8).json")
    }
}

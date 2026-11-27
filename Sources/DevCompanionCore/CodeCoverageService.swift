import Foundation

public enum CoverageScopeKind: String, CaseIterable, Identifiable, Sendable {
    case none = "Not Selected"
    case file = "Per File"
    case directory = "Per Directory"
    case project = "Whole Project"

    public var id: String { rawValue }
}

public struct FileCoverageItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let filePath: String
    public let relativePath: String
    public let coveredLines: Int
    public let executableLines: Int
    public let lineCoveragePercent: Double
    public let uncoveredFunctions: [String]

    public init(
        fileName: String,
        filePath: String,
        relativePath: String,
        coveredLines: Int,
        executableLines: Int,
        lineCoveragePercent: Double,
        uncoveredFunctions: [String] = []
    ) {
        self.id = filePath
        self.fileName = fileName
        self.filePath = filePath
        self.relativePath = relativePath
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.lineCoveragePercent = lineCoveragePercent
        self.uncoveredFunctions = uncoveredFunctions
    }
}

public struct CoverageReportSummary: Sendable, Equatable {
    public let scopeKind: CoverageScopeKind
    public let scopeLabel: String
    public let overallPercent: Double
    public let coveredLines: Int
    public let executableLines: Int
    public let files: [FileCoverageItem]
    public let generatedAt: Date

    public init(
        scopeKind: CoverageScopeKind,
        scopeLabel: String,
        overallPercent: Double,
        coveredLines: Int,
        executableLines: Int,
        files: [FileCoverageItem],
        generatedAt: Date = Date()
    ) {
        self.scopeKind = scopeKind
        self.scopeLabel = scopeLabel
        self.overallPercent = overallPercent
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.files = files
        self.generatedAt = generatedAt
    }
}

public struct CodeCoverageService: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Runs hybrid code coverage (Xcode `xccov` or SwiftPM `llvm-cov`) and filters by selected scope.
    public func runCoverage(
        projectURL: URL,
        xcodeProjectPath: String,
        scheme: String,
        destination: String,
        scope: CoverageScopeKind,
        selectedFilePath: String?,
        selectedDirectoryPath: String?
    ) async throws -> CoverageReportSummary {
        guard scope != .none else {
            throw CompanionError.commandFailed(executable: "coverage", exitCode: 1, stderr: "Select a coverage scope first.")
        }

        let allFiles: [FileCoverageItem]
        let packageSwift = projectURL.appendingPathComponent("Package.swift")
        if !xcodeProjectPath.isEmpty && !scheme.isEmpty {
            allFiles = try await runXcodeCoverage(
                projectURL: projectURL,
                xcodeProjectPath: xcodeProjectPath,
                scheme: scheme,
                destination: destination
            )
        } else if FileManager.default.fileExists(atPath: packageSwift.path) {
            allFiles = try await runSwiftPMCoverage(projectURL: projectURL)
        } else {
            throw CompanionError.commandFailed(
                executable: "coverage",
                exitCode: 1,
                stderr: "No Xcode scheme or Package.swift detected."
            )
        }

        let filtered = Self.filterFiles(
            allFiles,
            scope: scope,
            selectedFilePath: selectedFilePath,
            selectedDirectoryPath: selectedDirectoryPath
        )

        let covered = filtered.reduce(0) { $0 + $1.coveredLines }
        let executable = filtered.reduce(0) { $0 + $1.executableLines }
        let overall = executable > 0 ? (Double(covered) / Double(executable)) * 100.0 : 0.0

        let label: String = switch scope {
        case .none: ""
        case .file: URL(fileURLWithPath: selectedFilePath ?? "").lastPathComponent
        case .directory: URL(fileURLWithPath: selectedDirectoryPath ?? "").lastPathComponent
        case .project: projectURL.lastPathComponent
        }

        return CoverageReportSummary(
            scopeKind: scope,
            scopeLabel: label,
            overallPercent: overall,
            coveredLines: covered,
            executableLines: executable,
            files: filtered
        )
    }

    private func runXcodeCoverage(
        projectURL: URL,
        xcodeProjectPath: String,
        scheme: String,
        destination: String
    ) async throws -> [FileCoverageItem] {
        let resultBundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("xscope_cov_\(UUID().uuidString).xcresult")
        defer { try? FileManager.default.removeItem(at: resultBundle) }

        let flag = xcodeProjectPath.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
        let testOut = try await runner.run(
            "/usr/bin/xcodebuild",
            arguments: [
                "test",
                flag, xcodeProjectPath,
                "-scheme", scheme,
                "-destination", destination,
                "-enableCodeCoverage", "YES",
                "-resultBundlePath", resultBundle.path
            ],
            workingDirectory: projectURL
        )
        guard FileManager.default.fileExists(atPath: resultBundle.path) else {
            throw CompanionError.commandFailed(executable: "xcodebuild", exitCode: testOut.exitCode, stderr: testOut.stderr)
        }

        let covOut = try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["xccov", "view", "--report", "--json", resultBundle.path],
            workingDirectory: projectURL
        )
        guard covOut.isSuccess, let data = covOut.stdout.data(using: .utf8) else {
            throw CompanionError.commandFailed(executable: "xccov", exitCode: covOut.exitCode, stderr: covOut.stderr)
        }
        return Self.parseXccovReportJSON(data: data, projectRootPath: projectURL.path)
    }

    private func runSwiftPMCoverage(projectURL: URL) async throws -> [FileCoverageItem] {
        let testOut = try await runner.run(
            "/usr/bin/swift",
            arguments: ["test", "--enable-code-coverage"],
            workingDirectory: projectURL
        )
        guard testOut.isSuccess else {
            throw CompanionError.commandFailed(executable: "swift", exitCode: testOut.exitCode, stderr: testOut.stderr)
        }

        let binPathOut = try await runner.run(
            "/usr/bin/swift",
            arguments: ["build", "--show-bin-path"],
            workingDirectory: projectURL
        )
        let binDir = URL(fileURLWithPath: binPathOut.stdout.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
        let profdata = binDir.appendingPathComponent("codecov/default.profdata")
        guard let testBinary = findTestBinary(in: binDir) else {
            throw CompanionError.fileNotFound(path: binDir.path)
        }

        let reportOut = try await runner.run(
            "/usr/bin/xcrun",
            arguments: [
                "llvm-cov", "report",
                testBinary.path,
                "-instr-profile=\(profdata.path)",
                "-ignore-filename-regex=.build|Tests"
            ],
            workingDirectory: projectURL
        )
        guard reportOut.isSuccess else {
            throw CompanionError.commandFailed(executable: "llvm-cov", exitCode: reportOut.exitCode, stderr: reportOut.stderr)
        }
        return Self.parseLlvmCovReport(text: reportOut.stdout, projectRootPath: projectURL.path)
    }

    private func findTestBinary(in binDir: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: binDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        if let xctest = entries.first(where: { $0.pathExtension == "xctest" }) {
            let macosBin = xctest.appendingPathComponent("Contents/MacOS/\(xctest.deletingPathExtension().lastPathComponent)")
            if FileManager.default.fileExists(atPath: macosBin.path) { return macosBin }
            return xctest
        }
        return nil
    }

    public static func filterFiles(
        _ files: [FileCoverageItem],
        scope: CoverageScopeKind,
        selectedFilePath: String?,
        selectedDirectoryPath: String?
    ) -> [FileCoverageItem] {
        switch scope {
        case .none:
            return []
        case .file:
            guard let target = selectedFilePath, !target.isEmpty else { return [] }
            return files.filter { $0.filePath == target || $0.relativePath == target }
        case .directory:
            guard let dir = selectedDirectoryPath, !dir.isEmpty else { return [] }
            let normalized = dir.hasSuffix("/") ? dir : dir + "/"
            return files.filter { $0.filePath.hasPrefix(normalized) || $0.filePath == dir }
        case .project:
            return files
        }
    }

    public static func parseXccovReportJSON(data: Data, projectRootPath: String) -> [FileCoverageItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = json["targets"] as? [[String: Any]] else {
            return []
        }

        var itemsByPath: [String: FileCoverageItem] = [:]
        for target in targets {
            let targetName = (target["name"] as? String) ?? ""
            if targetName.hasSuffix(".xctest") { continue }
            guard let files = target["files"] as? [[String: Any]] else { continue }
            for file in files {
                guard let path = file["path"] as? String else { continue }
                let covered = (file["coveredLines"] as? Int) ?? 0
                let executable = (file["executableLines"] as? Int) ?? 0
                let pct = ((file["lineCoverage"] as? Double) ?? 0) * 100.0
                let funcs = (file["functions"] as? [[String: Any]]) ?? []
                let uncoveredFuncs = funcs.compactMap { fn -> String? in
                    let fnCov = (fn["lineCoverage"] as? Double) ?? 1.0
                    let name = fn["name"] as? String
                    return fnCov == 0 ? name : nil
                }
                let rel = path.replacingOccurrences(of: projectRootPath + "/", with: "")
                itemsByPath[path] = FileCoverageItem(
                    fileName: URL(fileURLWithPath: path).lastPathComponent,
                    filePath: path,
                    relativePath: rel,
                    coveredLines: covered,
                    executableLines: executable,
                    lineCoveragePercent: pct,
                    uncoveredFunctions: Array(uncoveredFuncs.prefix(8))
                )
            }
        }
        return Array(itemsByPath.values).sorted { $0.lineCoveragePercent < $1.lineCoveragePercent }
    }

    public static func parseLlvmCovReport(text: String, projectRootPath: String) -> [FileCoverageItem] {
        var items: [FileCoverageItem] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("Filename"),
                  !trimmed.hasPrefix("---"),
                  !trimmed.hasPrefix("TOTAL") else { continue }

            // Format: path/File.swift  <regions> <missedRegions> <cover%> <funcs> <missedFuncs> <cover%> <lines> <missedLines> <lineCover%>
            let cols = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard cols.count >= 10 else { continue }
            let rawPath = cols[0]
            let linesTotal = Int(cols[7]) ?? 0
            let missedLines = Int(cols[8]) ?? 0
            let coveredLines = max(0, linesTotal - missedLines)
            let pctString = cols[9].replacingOccurrences(of: "%", with: "")
            let pct = Double(pctString) ?? 0

            let fullPath = rawPath.hasPrefix("/") ? rawPath : projectRootPath + "/" + rawPath
            let rel = fullPath.replacingOccurrences(of: projectRootPath + "/", with: "")
            items.append(
                FileCoverageItem(
                    fileName: URL(fileURLWithPath: fullPath).lastPathComponent,
                    filePath: fullPath,
                    relativePath: rel,
                    coveredLines: coveredLines,
                    executableLines: linesTotal,
                    lineCoveragePercent: pct
                )
            )
        }
        return items.sorted { $0.lineCoveragePercent < $1.lineCoveragePercent }
    }
}

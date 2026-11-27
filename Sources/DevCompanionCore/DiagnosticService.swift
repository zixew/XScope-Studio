import Foundation

public enum TimeRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case allTime = "All Time"
    case today = "Today"
    case thisWeek = "7 Days"
    case thisMonth = "30 Days"

    public var id: String { rawValue }

    public func matches(date: Date, referenceDate: Date = Date()) -> Bool {
        let interval = referenceDate.timeIntervalSince(date)
        switch self {
        case .allTime: return true
        case .today: return interval >= 0 && interval <= 86_400
        case .thisWeek: return interval >= 0 && interval <= 7 * 86_400
        case .thisMonth: return interval >= 0 && interval <= 30 * 86_400
        }
    }
}

public struct DiagnosticReportItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case hang = "Hang / Freeze"
        case crash = "Crash"
        case memory = "Memory / Jetsam"
        case other = "Diagnostic"
    }

    public let id: String
    public let fileName: String
    public let processName: String
    public let kind: Kind
    public let timestamp: Date
    public let summary: String
    public let filePath: String
    public let isSystemDaemon: Bool
    public var isNew: Bool
    public var humanTitle: String
    public var whenContext: String
    public var sourceLocation: String?

    public var formattedDateString: String {
        Self.dateFormatter.string(from: timestamp)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    public var priority: CodeReviewFinding.Severity {
        switch kind {
        case .crash: return .critical
        case .hang: return .warning
        case .memory, .other: return .suggestion
        }
    }

    public init(
        id: String,
        fileName: String,
        processName: String,
        kind: Kind,
        timestamp: Date,
        summary: String,
        filePath: String,
        isSystemDaemon: Bool = false,
        isNew: Bool = false,
        humanTitle: String = "",
        whenContext: String = "",
        sourceLocation: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.processName = processName
        self.kind = kind
        self.timestamp = timestamp
        self.summary = summary
        self.filePath = filePath
        self.isSystemDaemon = isSystemDaemon
        self.isNew = isNew
        self.humanTitle = humanTitle.isEmpty ? summary : humanTitle
        self.whenContext = whenContext
        self.sourceLocation = sourceLocation
    }
}

public struct CrashAnalysisReport: Sendable, Equatable, Codable {
    public let processName: String
    public let exceptionType: String
    public let terminationReason: String
    public let crashedThread: String
    public let culpritSymbol: String
    public var sourceFileName: String?
    public var sourceLineNumber: Int?
    public let stackFrames: [String]
    public var humanExplanation: String
    public var whenAction: String
    public var offendingLineCode: String?

    public init(
        processName: String,
        exceptionType: String,
        terminationReason: String,
        crashedThread: String,
        culpritSymbol: String,
        sourceFileName: String? = nil,
        sourceLineNumber: Int? = nil,
        stackFrames: [String] = [],
        humanExplanation: String = "",
        whenAction: String = "",
        offendingLineCode: String? = nil
    ) {
        self.processName = processName
        self.exceptionType = exceptionType
        self.terminationReason = terminationReason
        self.crashedThread = crashedThread
        self.culpritSymbol = culpritSymbol
        self.sourceFileName = sourceFileName
        self.sourceLineNumber = sourceLineNumber
        self.stackFrames = stackFrames
        self.humanExplanation = humanExplanation.isEmpty
            ? DiagnosticService.explainException(exceptionType: exceptionType, terminationReason: terminationReason)
            : humanExplanation
        self.whenAction = whenAction.isEmpty
            ? DiagnosticService.formatWhenAction(culpritSymbol: culpritSymbol, crashedThread: crashedThread)
            : whenAction
        self.offendingLineCode = offendingLineCode
    }

    enum CodingKeys: String, CodingKey {
        case processName, exceptionType, terminationReason, crashedThread, culpritSymbol
        case sourceFileName, sourceLineNumber, stackFrames
        case humanExplanation, whenAction, offendingLineCode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        processName = try c.decode(String.self, forKey: .processName)
        exceptionType = try c.decode(String.self, forKey: .exceptionType)
        terminationReason = try c.decode(String.self, forKey: .terminationReason)
        crashedThread = try c.decode(String.self, forKey: .crashedThread)
        culpritSymbol = try c.decode(String.self, forKey: .culpritSymbol)
        sourceFileName = try? c.decodeIfPresent(String.self, forKey: .sourceFileName)
        sourceLineNumber = try? c.decodeIfPresent(Int.self, forKey: .sourceLineNumber)
        stackFrames = (try? c.decode([String].self, forKey: .stackFrames)) ?? []
        let decodedExp = (try? c.decodeIfPresent(String.self, forKey: .humanExplanation)) ?? ""
        humanExplanation = decodedExp.isEmpty
            ? DiagnosticService.explainException(exceptionType: exceptionType, terminationReason: terminationReason)
            : decodedExp
        let decodedWhen = (try? c.decodeIfPresent(String.self, forKey: .whenAction)) ?? ""
        whenAction = decodedWhen.isEmpty
            ? DiagnosticService.formatWhenAction(culpritSymbol: culpritSymbol, crashedThread: crashedThread)
            : decodedWhen
        offendingLineCode = try? c.decodeIfPresent(String.self, forKey: .offendingLineCode)
    }
}

public struct CrashSourceSnippet: Sendable, Equatable {
    public let filePath: String
    public let fileName: String
    public let lineNumber: Int
    public let snippet: String

    public init(filePath: String, fileName: String, lineNumber: Int, snippet: String) {
        self.filePath = filePath
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.snippet = snippet
    }
}

/// Reads macOS/iOS DiagnosticReports (`.ips`, `.hang`) and runs `xcrun xctrace` profiling.
public struct DiagnosticService: Sendable {
    private let runner: any CommandExecuting

    public init(runner: any CommandExecuting = ProcessRunner()) {
        self.runner = runner
    }

    public func loadRecentReports(
        limit: Int = 25,
        projectName: String? = nil,
        simulatorAppNames: [String] = [],
        allowedDeveloperAppNames: Set<String>? = nil,
        includeSystemReports: Bool = false,
        directory: URL? = nil
    ) -> [DiagnosticReportItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let primaryDir = directory ?? home.appendingPathComponent("Library/Logs/DiagnosticReports")

        var urls: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: primaryDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        // Also scan synced physical iOS device crash reports under ~/Library/Logs/CrashReporter/MobileDevice
        if directory == nil {
            let mobileDeviceDir = home.appendingPathComponent("Library/Logs/CrashReporter/MobileDevice")
            if let enumerator = FileManager.default.enumerator(
                at: mobileDeviceDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    urls.append(fileURL)
                }
            }
        }

        guard !urls.isEmpty else {
            return []
        }

        let supportedExtensions: Set<String> = ["ips", "hang", "crash"]
        let sorted = urls
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let d1 = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }

        let normalizedProject = projectName?.lowercased()
        let normalizedSimApps = Set(simulatorAppNames.map { $0.lowercased() })
        let normalizedAllowedDev = allowedDeveloperAppNames.map { Set($0.map { $0.lowercased() }) }

        var items: [DiagnosticReportItem] = []
        for url in sorted {
            let fileName = url.lastPathComponent
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let lower = fileName.lowercased()
            let ext = url.pathExtension.lowercased()
            let kind: DiagnosticReportItem.Kind = if ext == "hang" || lower.contains("hang") || lower.contains("spin") {
                .hang
            } else if lower.contains("jetsam") || lower.contains("memory") {
                .memory
            } else if lower.contains("crash") || ext == "ips" {
                .crash
            } else {
                .other
            }

            let processName = Self.extractProcessName(from: fileName)
            let isSys = Self.isSystemDiagnostic(fileName: fileName, processName: processName)
            let procLower = processName.lowercased()
            let matchesProject = normalizedProject.map { procLower.contains($0) || $0.contains(procLower) } ?? false
            let matchesSimApp = normalizedSimApps.contains(procLower)
            let matchesAllowedDev = normalizedAllowedDev?.contains(where: { procLower.contains($0) || $0.contains(procLower) }) ?? false
            let isKnownNonDev = ProcessTelemetryService.nonDeveloperAppBlocklist.contains(procLower)
            let hasDevContext = (normalizedProject != nil) || !normalizedSimApps.isEmpty || (normalizedAllowedDev != nil)

            if !includeSystemReports {
                // Fail-closed Developer Apps Only privacy gate:
                // Never expose system daemons or consumer/third-party apps (e.g. WhatsApp, Discord, Chrome, Spotify)
                if isSys || isKnownNonDev {
                    continue
                }
                if hasDevContext && !matchesProject && !matchesSimApp && !matchesAllowedDev {
                    continue
                }
            }

            let meta = Self.extractQuickMetadata(from: url, kind: kind, processName: processName)
            items.append(
                DiagnosticReportItem(
                    id: url.path,
                    fileName: fileName,
                    processName: processName,
                    kind: kind,
                    timestamp: date,
                    summary: meta.summary,
                    filePath: url.path,
                    isSystemDaemon: isSys,
                    isNew: Date().timeIntervalSince(date) <= 86_400,
                    humanTitle: meta.humanTitle,
                    whenContext: meta.whenContext,
                    sourceLocation: meta.sourceLocation
                )
            )
            if items.count >= max(0, limit) { break }
        }
        if !items.isEmpty, !items.contains(where: \.isNew) {
            // Mark the most recent report(s) as NEW so the user immediately sees the latest event at the top
            for idx in items.indices.prefix(2) {
                items[idx].isNew = true
            }
        }
        return items.sorted { lhs, rhs in
            if lhs.priority.priorityRank != rhs.priority.priorityRank {
                return lhs.priority.priorityRank < rhs.priority.priorityRank
            }
            if lhs.isNew != rhs.isNew {
                return lhs.isNew && !rhs.isNew
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    static func extractProcessName(from fileName: String) -> String {
        var base = fileName
        for prefix in ["ExcUserFault_", "ExcResource_"] where base.hasPrefix(prefix) {
            base = String(base.dropFirst(prefix.count))
        }
        if let range = base.range(of: #"-\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(base[..<range.lowerBound])
        }
        return base.components(separatedBy: CharacterSet(charactersIn: "_.")).first ?? fileName
    }

    private static func isSystemDiagnostic(fileName: String, processName: String) -> Bool {
        if fileName.hasPrefix("ExcUserFault_") || fileName.hasPrefix("ExcResource_") {
            return true
        }
        let systemPrefixes = [
            "ibagent", "nsattributedstringagent", "springboard", "backboardd",
            "launchd", "windowserver", "coreduetd", "mds", "siri", "spotlight",
            "xcode", "sourcekit", "simulatortracker", "com.apple."
        ]
        let lower = processName.lowercased()
        return systemPrefixes.contains { lower.hasPrefix($0) }
    }

    public func recordTrace(
        template: String,
        deviceNameOrUDID: String,
        processName: String,
        durationSeconds: Int = 10
    ) async throws -> (outputURL: URL, commandOutput: CommandOutput) {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevCompanion_\(template.replacingOccurrences(of: " ", with: "_"))_\(UUID().uuidString).trace")

        let output = try await runner.run(
            "/usr/bin/xcrun",
            arguments: [
                "xctrace", "record",
                "--template", template,
                "--device", deviceNameOrUDID,
                "--attach", processName,
                "--time-limit", "\(durationSeconds)s",
                "--output", outURL.path
            ],
            workingDirectory: nil
        )
        return (outURL, output)
    }

    public func exportTraceTOC(traceURL: URL) async throws -> CommandOutput {
        try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["xctrace", "export", "--input", traceURL.path, "--toc"],
            workingDirectory: nil
        )
    }

    public func symbolicateAddress(_ address: String, binaryOrDsymPath: String, loadAddress: String = "0x0", arch: String = "arm64") async throws -> String {
        let output = try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["atos", "-arch", arch, "-o", binaryOrDsymPath, "-l", loadAddress, address],
            workingDirectory: nil
        )
        return output.isSuccess ? output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : output.stderr
    }

    /// Parses modern `.ips` JSON or classic `.crash`/`.hang` logs to identify force-close cause, symbol, and Swift source location.
    public func analyzeCrashReport(content: String, processName: String = "") -> CrashAnalysisReport {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ipsReport = Self.parseIPSJSON(from: trimmed, fallbackProcess: processName) {
            return ipsReport
        }
        return Self.parseClassicCrashText(from: trimmed, fallbackProcess: processName)
    }

    /// Locates the offending `.swift` file in `projectURL` and extracts ±3 lines of code around `lineNumber`.
    public func locateSourceSnippet(fileName: String, lineNumber: Int?, in projectURL: URL) -> CrashSourceSnippet? {
        guard !fileName.isEmpty,
              let enumerator = FileManager.default.enumerator(
                  at: projectURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              )
        else { return nil }

        let skipDirs: Set<String> = [".build", "Pods", "DerivedData", ".git"]
        var matchedURL: URL?
        for case let url as URL in enumerator {
            if skipDirs.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == fileName {
                matchedURL = url
                break
            }
        }

        guard let fileURL = matchedURL,
              let source = try? String(contentsOf: fileURL, encoding: .utf8)
        else { return nil }

        let lines = source.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }
        let targetLine = min(max(1, lineNumber ?? 1), lines.count)
        let start = max(0, targetLine - 4)
        let end = min(lines.count - 1, targetLine + 2)

        let formatted = (start...end).map { idx in
            let marker = (idx + 1 == targetLine) ? "→" : " "
            return String(format: "%@ %4d | %@", marker, idx + 1, lines[idx])
        }.joined(separator: "\n")

        return CrashSourceSnippet(
            filePath: fileURL.path,
            fileName: fileURL.lastPathComponent,
            lineNumber: targetLine,
            snippet: formatted
        )
    }

    /// Resolves a crash report to the exact Swift file, line number, and source snippet inside `projectURL`, even when raw `.ips` frames lack `.swift:line` debug info.
    public func resolveProjectSource(
        for report: CrashAnalysisReport,
        in projectURL: URL?
    ) -> (analysis: CrashAnalysisReport, snippet: CrashSourceSnippet?) {
        var enriched = report
        guard let projectURL else {
            return (enriched, nil)
        }

        // 1. Direct fileName:lineNumber match if already present in stack trace
        if let fileName = enriched.sourceFileName,
           let snippet = locateSourceSnippet(fileName: fileName, lineNumber: enriched.sourceLineNumber, in: projectURL) {
            enriched.sourceFileName = snippet.fileName
            enriched.sourceLineNumber = snippet.lineNumber
            enriched.offendingLineCode = Self.extractTargetLineCode(from: snippet.snippet)
            enriched.whenAction = Self.formatWhenAction(
                culpritSymbol: enriched.culpritSymbol,
                crashedThread: enriched.crashedThread,
                sourceLocation: "\(snippet.fileName):\(snippet.lineNumber)"
            )
            return (enriched, snippet)
        }

        // 2. Symbol-to-Swift file correlation across project directory
        let candidateTokens = Self.extractSymbolTokens(from: [enriched.culpritSymbol] + enriched.stackFrames)
        let skipDirs: Set<String> = [".build", "Pods", "DerivedData", ".git"]
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (enriched, nil)
        }

        var bestMatch: (url: URL, line: Int, code: String, score: Int, funcName: String?)?
        var scanned = 0

        for case let fileURL as URL in enumerator {
            guard scanned < 250 else { break }
            if skipDirs.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard fileURL.pathExtension == "swift",
                  let source = try? String(contentsOf: fileURL, encoding: .utf8)
            else { continue }
            scanned += 1

            let fileStem = (fileURL.lastPathComponent as NSString).deletingPathExtension
            var fileScore = 0
            for token in candidateTokens {
                if fileStem.localizedCaseInsensitiveContains(token) || token.localizedCaseInsensitiveContains(fileStem) {
                    fileScore += 10
                }
            }

            let lines = source.components(separatedBy: .newlines)
            var currentFunc: String?
            var inMatchingFunc = false
            for (idx, rawLine) in lines.enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.isEmpty else { continue }

                if let fnMatch = Self.extractFuncName(from: trimmed) {
                    currentFunc = fnMatch
                    inMatchingFunc = candidateTokens.contains {
                        $0.localizedCaseInsensitiveContains(fnMatch) || fnMatch.localizedCaseInsensitiveContains($0)
                    }
                }

                let isDeclaration = trimmed.hasPrefix("class ") || trimmed.hasPrefix("final class ") || trimmed.hasPrefix("struct ") || trimmed.hasPrefix("func ") || trimmed.hasPrefix("private func ") || trimmed.hasPrefix("public func ")
                var lineScore = fileScore + (inMatchingFunc ? 10 : 0) - (isDeclaration ? 5 : 0)
                for token in candidateTokens where token.count >= 4 {
                    if trimmed.localizedCaseInsensitiveContains(token) {
                        lineScore += 4
                    }
                }
                if trimmed.contains("try!") || trimmed.contains("as!") || trimmed.contains("fatalError(") || trimmed.contains("preconditionFailure(") {
                    lineScore += 12
                } else if trimmed.contains("Data(contentsOf:") || trimmed.contains("DispatchSemaphore") || trimmed.contains("Thread.sleep") {
                    lineScore += 10
                } else if trimmed.contains("!") && !trimmed.contains("!=") && !trimmed.hasPrefix("if !") && !trimmed.hasPrefix("guard !") {
                    lineScore += 6
                }

                if lineScore > (bestMatch?.score ?? 2) {
                    bestMatch = (fileURL, idx + 1, trimmed, lineScore, currentFunc)
                }
            }
        }

        if let match = bestMatch,
           let snippet = locateSourceSnippet(fileName: match.url.lastPathComponent, lineNumber: match.line, in: projectURL) {
            enriched.sourceFileName = match.url.lastPathComponent
            enriched.sourceLineNumber = match.line
            enriched.offendingLineCode = match.code
            let actionSym = match.funcName.map { "\(match.url.deletingPathExtension().lastPathComponent).\($0)()" } ?? enriched.culpritSymbol
            enriched.whenAction = Self.formatWhenAction(
                culpritSymbol: actionSym,
                crashedThread: enriched.crashedThread,
                sourceLocation: "\(match.url.lastPathComponent):\(match.line)"
            )
            return (enriched, snippet)
        }

        return (enriched, nil)
    }

    public static func explainException(exceptionType: String, terminationReason: String) -> String {
        let combined = "\(exceptionType) \(terminationReason)".lowercased()
        if combined.contains("8badf00d") || combined.contains("watchdog") || combined.contains("hang") || combined.contains("spin") {
            return "Main Thread Freeze / Watchdog Timeout (UI terkunci terlalu lama di main thread)"
        }
        if combined.contains("exc_breakpoint") || combined.contains("sigtrap") || combined.contains("unexpectedly found nil") || combined.contains("force unwrap") {
            return "Swift Runtime Trap / Force Unwrap nil (nilai optional bernilai nil atau index out of range)"
        }
        if combined.contains("exc_bad_access") || combined.contains("sigsegv") || combined.contains("sigbus") || combined.contains("kern_invalid_address") {
            return "Invalid Memory Access / Dangling Pointer (mengakses objek yang sudah dilepas di memori)"
        }
        if combined.contains("sigabrt") || combined.contains("exc_crash") || combined.contains("uncaught exception") {
            return "Fatal Abort / Uncaught Exception (NSException, IBOutlet putus, atau assertion gagal)"
        }
        if combined.contains("jetsam") || combined.contains("highwater") || combined.contains("per-process-limit") {
            return "Out of Memory / Jetsam Kill (alokasi memori melewati batas maksimum iOS)"
        }
        return "Unexpected Process Termination (\(exceptionType))"
    }

    public static func formatWhenAction(culpritSymbol: String, crashedThread: String, sourceLocation: String? = nil) -> String {
        let cleanSym = culpritSymbol
            .replacingOccurrences(of: #"^\d+\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let locPrefix = sourceLocation.map { "[\($0)] " } ?? ""
        if cleanSym.isEmpty || cleanSym == "Unknown Symbol" {
            return "\(locPrefix)Saat eksekusi pada \(crashedThread)"
        }
        return "\(locPrefix)Saat mengeksekusi \(cleanSym) (\(crashedThread))"
    }

    private static func extractTargetLineCode(from formattedSnippet: String) -> String? {
        for line in formattedSnippet.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("→"), let pipeRange = trimmed.range(of: "|") {
                return trimmed[pipeRange.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func extractSymbolTokens(from frames: [String]) -> [String] {
        let stopWords: Set<String> = [
            "app", "main", "start", "dyld", "uikit", "uikitcore", "swiftui", "foundation",
            "libsystem", "libswiftcore", "libdispatch", "closure", "implicit", "thunk",
            "objc", "thread", "crashed", "unknown", "symbol"
        ]
        var tokens: [String] = []
        var seen = Set<String>()
        for frame in frames {
            let parts = frame.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for part in parts where part.count >= 4 {
                let lower = part.lowercased()
                guard !stopWords.contains(lower),
                      !lower.hasPrefix("0x"),
                      part.rangeOfCharacter(from: .letters) != nil,
                      seen.insert(lower).inserted
                else { continue }
                tokens.append(part)
            }
        }
        return tokens
    }

    private static func extractFuncName(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"func\s+([A-Za-z0-9_]+)\s*\("#) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func parseIPSJSON(from text: String, fallbackProcess: String) -> CrashAnalysisReport? {
        let rawLines = text.components(separatedBy: .newlines)
        let bodyCandidate: String = if rawLines.count > 1,
                                       let firstLineData = rawLines[0].trimmingCharacters(in: .whitespaces).data(using: .utf8),
                                       (try? JSONSerialization.jsonObject(with: firstLineData)) != nil {
            rawLines.dropFirst().joined(separator: "\n")
        } else {
            text
        }

        guard let data = bodyCandidate.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["exception"] != nil || json["faultingThread"] != nil || json["threads"] != nil
        else { return nil }

        let proc = (json["procName"] as? String) ?? (fallbackProcess.isEmpty ? "UnknownProcess" : fallbackProcess)
        let exc = json["exception"] as? [String: Any]
        let excType = (exc?["type"] as? String) ?? "Unknown Exception"
        let excSignal = exc?["signal"] as? String
        let fullException = excSignal.map { "\(excType) (\($0))" } ?? excType

        let term = json["termination"] as? [String: Any]
        let termIndicator = (term?["indicator"] as? String) ?? (term?["namespace"] as? String) ?? ""
        let asiDict = json["asi"] as? [String: [String]]
        let asiMessage = asiDict?.values.flatMap { $0 }.joined(separator: " | ") ?? ""
        let terminationReason = [termIndicator, asiMessage].filter { !$0.isEmpty }.joined(separator: " — ")

        let faultingIdx = (json["faultingThread"] as? Int) ?? 0
        let threads = json["threads"] as? [[String: Any]] ?? []
        let usedImages = json["usedImages"] as? [[String: Any]] ?? []

        var frames: [String] = []
        if faultingIdx < threads.count {
            let rawFrames = threads[faultingIdx]["frames"] as? [[String: Any]] ?? []
            for (i, frame) in rawFrames.prefix(10).enumerated() {
                let sym = (frame["symbol"] as? String) ?? String(format: "0x%llx", (frame["imageOffset"] as? UInt64) ?? 0)
                let imgIdx = frame["imageIndex"] as? Int
                let imgName = (imgIdx != nil && imgIdx! < usedImages.count)
                    ? ((usedImages[imgIdx!]["name"] as? String) ?? "App")
                    : "App"
                let srcFile = frame["sourceFile"] as? String
                let srcLine = frame["sourceLine"] as? Int
                if let srcFile, let srcLine {
                    frames.append("\(i)  \(imgName)  \(sym) (\(srcFile):\(srcLine))")
                } else {
                    frames.append("\(i)  \(imgName)  \(sym)")
                }
            }
        }

        let sourceLoc = extractSwiftLocation(from: ([asiMessage] + frames).joined(separator: "\n"))
        let culprit = frames.first(where: { !$0.contains("libsystem") && !$0.contains("libswiftCore") }) ?? frames.first ?? "Unknown Symbol"

        return CrashAnalysisReport(
            processName: proc,
            exceptionType: fullException,
            terminationReason: terminationReason.isEmpty ? "Process terminated unexpectedly" : terminationReason,
            crashedThread: "Thread \(faultingIdx) Crashed",
            culpritSymbol: culprit,
            sourceFileName: sourceLoc?.fileName,
            sourceLineNumber: sourceLoc?.lineNumber,
            stackFrames: frames
        )
    }

    private static func parseClassicCrashText(from text: String, fallbackProcess: String) -> CrashAnalysisReport {
        let lines = text.components(separatedBy: .newlines)
        func field(_ prefix: String) -> String? {
            lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) })?
                .components(separatedBy: prefix).last?
                .trimmingCharacters(in: .whitespaces)
        }

        let proc = field("Process:")?.components(separatedBy: " ").first ?? (fallbackProcess.isEmpty ? "UnknownProcess" : fallbackProcess)
        let excType = field("Exception Type:") ?? "Unknown Exception"
        let termReason = field("Termination Reason:") ?? field("Exception Codes:") ?? "Process terminated unexpectedly"
        let asi = field("Application Specific Information:") ?? ""
        let fullReason = [termReason, asi].filter { !$0.isEmpty }.joined(separator: " — ")

        var crashedHeader = "Thread 0 Crashed"
        var frames: [String] = []
        var inCrashedThread = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("Crashed:") {
                crashedHeader = t.replacingOccurrences(of: ":", with: "")
                inCrashedThread = true
                continue
            }
            if inCrashedThread {
                if t.isEmpty || t.hasPrefix("Thread ") { break }
                frames.append(t)
                if frames.count >= 10 { break }
            }
        }

        let sourceLoc = extractSwiftLocation(from: ([asi] + frames).joined(separator: "\n"))
        let culprit = frames.first(where: { !$0.contains("libsystem") && !$0.contains("libswiftCore") }) ?? frames.first ?? "Unknown Symbol"

        return CrashAnalysisReport(
            processName: proc,
            exceptionType: excType,
            terminationReason: fullReason,
            crashedThread: crashedHeader,
            culpritSymbol: culprit,
            sourceFileName: sourceLoc?.fileName,
            sourceLineNumber: sourceLoc?.lineNumber,
            stackFrames: frames
        )
    }

    private static func extractSwiftLocation(from text: String) -> (fileName: String, lineNumber: Int)? {
        let pattern = #"([A-Za-z0-9_+\-]+\.swift):(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 3,
              let lineNum = Int(ns.substring(with: match.range(at: 2)))
        else { return nil }
        let file = URL(fileURLWithPath: ns.substring(with: match.range(at: 1))).lastPathComponent
        return (file, lineNum)
    }

    private static func extractQuickMetadata(
        from url: URL,
        kind: DiagnosticReportItem.Kind,
        processName: String
    ) -> (summary: String, humanTitle: String, whenContext: String, sourceLocation: String?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ("Diagnostic report", kind.rawValue, processName, nil)
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 16_384)
        guard let text = String(data: data, encoding: .utf8) else {
            return ("Diagnostic report", kind.rawValue, processName, nil)
        }

        let parsed = DiagnosticService().analyzeCrashReport(content: text, processName: processName)
        let loc = parsed.sourceFileName.map { "\($0):\(parsed.sourceLineNumber ?? 1)" }
        let humanTitle = parsed.humanExplanation
        let whenContext = parsed.whenAction
        let summary = loc.map { "\($0) • \(humanTitle)" } ?? "\(humanTitle) • \(parsed.culpritSymbol)"
        return (summary, humanTitle, whenContext, loc)
    }

    /// Distinguishes user app/project stack frames from Apple system frames for Firebase Crashlytics-style stack trace highlighting.
    public static func isAppStackFrame(_ frame: String, processName: String, projectName: String? = nil) -> Bool {
        let lower = frame.lowercased()
        if lower.contains(".swift:") || lower.contains(".swift ") {
            return true
        }
        let systemTokens = [
            "libsystem", "libswift", "libobjc", "libdispatch", "dyld", "corefoundation",
            "uikitcore", "uikit", "swiftui", "foundation", "graphicsservices", "cfnetwork",
            "quartzcore", "metal", "audio", "webkit", "javascriptcore", "??? ("
        ]
        if systemTokens.contains(where: { lower.contains($0) }) {
            return false
        }
        let cleanProc = processName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !cleanProc.isEmpty && lower.contains(cleanProc) {
            return true
        }
        if let proj = projectName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !proj.isEmpty, lower.contains(proj) {
            return true
        }
        return false
    }
}

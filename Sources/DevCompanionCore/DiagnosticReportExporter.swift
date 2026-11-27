import Foundation

public struct ScanHealthSnapshot: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public let score: Int
    public let crashCount: Int
    public let hangCount: Int
    public let warningCount: Int

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        score: Int,
        crashCount: Int,
        hangCount: Int,
        warningCount: Int
    ) {
        self.id = id
        self.date = date
        self.score = score
        self.crashCount = crashCount
        self.hangCount = hangCount
        self.warningCount = warningCount
    }
}

public final class ScanHealthHistoryStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let maxSnapshots = 20

    public init(defaults: UserDefaults = .standard, key: String = "xscope.scan.health.history") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [ScanHealthSnapshot] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ScanHealthSnapshot].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.date < $1.date }
    }

    @discardableResult
    public func record(_ snapshot: ScanHealthSnapshot) -> [ScanHealthSnapshot] {
        var list = load()
        list.append(snapshot)
        if list.count > maxSnapshots {
            list.removeFirst(list.count - maxSnapshots)
        }
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
        return list
    }
}

public enum DiagnosticReportExporter {
    public static func buildCrashlyticsMarkdown(
        reports: [DiagnosticReportItem],
        projectName: String?
    ) -> String {
        let title = projectName ?? "Workspace"
        var lines: [String] = [
            "# XScope Studio — Crashlytics Report (\(title))",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Total Diagnostic Reports: \(reports.count)",
            ""
        ]

        if reports.isEmpty {
            lines.append("No crash or hang reports detected.")
            return lines.joined(separator: "\n")
        }

        for (idx, report) in reports.prefix(30).enumerated() {
            lines.append("## \(idx + 1). \(report.processName) — \(report.humanTitle)")
            lines.append("- **Kind:** \(report.kind.rawValue)")
            lines.append("- **Priority:** \(report.priority.rawValue)")
            lines.append("- **File:** `\(report.fileName)`")
            if !report.summary.isEmpty {
                lines.append("- **Summary:** \(report.summary)")
            }
            if !report.whenContext.isEmpty {
                lines.append("- **Context:** \(report.whenContext)")
            }
            if let loc = report.sourceLocation, !loc.isEmpty {
                lines.append("- **Source:** `\(loc)`")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func buildPerformanceMarkdown(
        appName: String?,
        cpuHistory: [Double],
        memoryHistory: [Double],
        freezes: [FreezeLagEvent]
    ) -> String {
        let target = appName ?? "Active Target"
        let peakCPU = cpuHistory.max() ?? 0
        let peakMem = memoryHistory.max() ?? 0
        let avgCPU = cpuHistory.isEmpty ? 0 : cpuHistory.reduce(0, +) / Double(cpuHistory.count)

        var lines: [String] = [
            "# XScope Studio — Performance & Hang Report (\(target))",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Summary",
            "- **Samples Captured:** \(cpuHistory.count)",
            "- **Average CPU:** \(String(format: "%.1f%%", avgCPU))",
            "- **Peak CPU:** \(String(format: "%.1f%%", peakCPU))",
            "- **Peak Memory:** \(String(format: "%.1f MB", peakMem))",
            "- **Detected Freezes / Hangs:** \(freezes.count)",
            ""
        ]

        if !freezes.isEmpty {
            lines.append("## Freeze & Hang Events")
            for freeze in freezes.prefix(30) {
                lines.append("- **\(freeze.culpritSymbol)** (\(String(format: "%.2fs", freeze.durationSeconds)), Peak CPU \(String(format: "%.1f%%", freeze.peakCPUPercent))) — \(freeze.reason)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

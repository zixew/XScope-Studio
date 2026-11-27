import Foundation

public enum SimulatorLogLevel: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case defaultLevel = "Default"
    case info = "Info"
    case debug = "Debug"
    case error = "Error"
    case fault = "Fault"

    public var id: String { rawValue }
}

public struct SimulatorLogEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: String
    public let process: String
    public let subsystem: String
    public let level: SimulatorLogLevel
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: String,
        process: String,
        subsystem: String,
        level: SimulatorLogLevel,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.process = process
        self.subsystem = subsystem
        self.level = level
        self.message = message
    }
}

/// Bounded ring buffer for simulator logs to keep memory flat during long sessions.
public struct SimulatorLogRingBuffer: Sendable {
    public let maxCapacity: Int
    public private(set) var entries: [SimulatorLogEntry] = []

    public init(maxCapacity: Int = 500) {
        self.maxCapacity = max(1, maxCapacity)
    }

    public mutating func append(_ newEntries: [SimulatorLogEntry]) {
        guard !newEntries.isEmpty else { return }
        entries.append(contentsOf: newEntries)
        if entries.count > maxCapacity {
            entries.removeFirst(entries.count - maxCapacity)
        }
    }

    public mutating func clear() {
        entries.removeAll(keepingCapacity: false)
    }

    public func filter(level: SimulatorLogLevel, query: String) -> [SimulatorLogEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            let matchesLevel = (level == .all) || (entry.level == level)
            guard matchesLevel else { return false }
            guard !q.isEmpty else { return true }
            return entry.process.lowercased().contains(q)
                || entry.subsystem.lowercased().contains(q)
                || entry.message.lowercased().contains(q)
        }
    }

    /// Parses a line from `xcrun simctl spawn <udid> log stream --style compact`.
    public static func parseCompactLine(_ line: String) -> SimulatorLogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("Filtering the log data"),
              !trimmed.hasPrefix("Timestamp") else {
            return nil
        }

        // Compact format example:
        // 2026-11-27 08:30:12.123 Df MyApp[1234:5678] [com.example:ui] Hello
        let parts = trimmed.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count >= 4 else {
            return SimulatorLogEntry(
                timestamp: "",
                process: "sim",
                subsystem: "",
                level: .defaultLevel,
                message: trimmed
            )
        }

        let timestamp = parts.count >= 2 ? String(parts[1]) : ""
        let typeToken = parts.count >= 3 ? String(parts[2]) : ""
        let level = mapCompactLevel(typeToken)

        let remainder = parts.count >= 5 ? "\(parts[3]) \(parts[4])" : String(parts[3])
        let process: String
        let afterProcess: String
        if let bracketIdx = remainder.firstIndex(of: "[") {
            process = String(remainder[..<bracketIdx]).trimmingCharacters(in: .whitespaces)
            if let closeIdx = remainder[bracketIdx...].firstIndex(of: "]") {
                afterProcess = String(remainder[remainder.index(after: closeIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                afterProcess = remainder
            }
        } else {
            process = "sim"
            afterProcess = remainder
        }

        var subsystem = ""
        var message = afterProcess
        if afterProcess.hasPrefix("["), let closeSub = afterProcess.firstIndex(of: "]") {
            let inside = String(afterProcess[afterProcess.index(after: afterProcess.startIndex)..<closeSub])
            subsystem = inside
            message = String(afterProcess[afterProcess.index(after: closeSub)...]).trimmingCharacters(in: .whitespaces)
        }

        return SimulatorLogEntry(
            timestamp: timestamp,
            process: process.isEmpty ? "sim" : process,
            subsystem: subsystem,
            level: level,
            message: message.isEmpty ? trimmed : message
        )
    }

    private static func mapCompactLevel(_ token: String) -> SimulatorLogLevel {
        switch token {
        case "E", "Er": return .error
        case "F", "Ft": return .fault
        case "I", "In": return .info
        case "D", "Db": return .debug
        default: return .defaultLevel
        }
    }
}

public struct DeepLinkPreset: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let urlString: String
    public var lastUsedAt: Date

    public init(id: UUID = UUID(), title: String, urlString: String, lastUsedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.lastUsedAt = lastUsedAt
    }
}

public final class DeepLinkPresetStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let maxCount = 20

    public init(defaults: UserDefaults = .standard, key: String = "xscope.deeplink.presets") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [DeepLinkPreset] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DeepLinkPreset].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    @discardableResult
    public func savePreset(title: String, urlString: String) -> [DeepLinkPreset] {
        let cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return load() }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = load().filter { $0.urlString != cleanURL }
        list.insert(
            DeepLinkPreset(
                title: cleanTitle.isEmpty ? cleanURL : cleanTitle,
                urlString: cleanURL,
                lastUsedAt: Date()
            ),
            at: 0
        )
        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }
        persist(list)
        return list
    }

    @discardableResult
    public func removePreset(id: UUID) -> [DeepLinkPreset] {
        let list = load().filter { $0.id != id }
        persist(list)
        return list
    }

    private func persist(_ list: [DeepLinkPreset]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
    }
}

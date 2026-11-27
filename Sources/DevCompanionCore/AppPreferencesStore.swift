import Foundation

public enum AppLanguageOverride: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case en = "en"
    case id = "id"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .system: "Auto"
        case .en: "English"
        case .id: "Bahasa"
        }
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var telemetryIntervalSeconds: Double
    public var logBufferCapacity: Int
    public var notifyOnCrash: Bool
    public var notifyOnHang: Bool
    public var notifyOnTaskComplete: Bool
    public var languageOverride: AppLanguageOverride

    public init(
        telemetryIntervalSeconds: Double = 1.5,
        logBufferCapacity: Int = 500,
        notifyOnCrash: Bool = true,
        notifyOnHang: Bool = true,
        notifyOnTaskComplete: Bool = true,
        languageOverride: AppLanguageOverride = .system
    ) {
        self.telemetryIntervalSeconds = telemetryIntervalSeconds
        self.logBufferCapacity = logBufferCapacity
        self.notifyOnCrash = notifyOnCrash
        self.notifyOnHang = notifyOnHang
        self.notifyOnTaskComplete = notifyOnTaskComplete
        self.languageOverride = languageOverride
    }
}

public final class AppPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "xscope.app.preferences") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }
        return decoded
    }

    public func save(_ prefs: AppPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: key)
        }
    }
}

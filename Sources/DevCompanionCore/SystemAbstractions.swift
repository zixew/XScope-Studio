import Foundation

/// Abstraction over key-value user preferences for Dependency Inversion and unit testing.
public protocol PreferencesStoring: Sendable {
    func string(forKey defaultName: String) -> String?
    func double(forKey defaultName: String) -> Double?
    func set(_ value: String?, forKey defaultName: String)
    func set(_ value: Double, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

public struct UserDefaultsStore: PreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey defaultName: String) -> String? {
        defaults.string(forKey: defaultName)
    }

    public func double(forKey defaultName: String) -> Double? {
        defaults.object(forKey: defaultName) as? Double
    }

    public func set(_ value: String?, forKey defaultName: String) {
        defaults.set(value, forKey: defaultName)
    }

    public func set(_ value: Double, forKey defaultName: String) {
        defaults.set(value, forKey: defaultName)
    }

    public func removeObject(forKey defaultName: String) {
        defaults.removeObject(forKey: defaultName)
    }
}

/// Abstraction over system clipboard operations so Views remain passive.
@MainActor
public protocol ClipboardManaging: Sendable {
    func copyString(_ text: String)
    func copyImage(at url: URL) -> Bool
}

public enum SingleInstancePolicy {
    public static func findExistingInstancePID(currentPID: Int32, candidatePIDs: [Int32]) -> Int32? {
        candidatePIDs.first(where: { $0 != currentPID && $0 > 0 })
    }
}

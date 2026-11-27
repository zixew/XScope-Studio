import Foundation
import OSLog

public enum CompanionLog {
    public static let subsystem = "com.devcompanion.mac"
    public static let process = Logger(subsystem: subsystem, category: "ProcessRunner")
    public static let agent = Logger(subsystem: subsystem, category: "AgentService")
    public static let telemetry = Logger(subsystem: subsystem, category: "Telemetry")
    public static let security = Logger(subsystem: subsystem, category: "Keychain")
}

public enum CompanionError: LocalizedError, Sendable, Equatable {
    case commandFailed(executable: String, exitCode: Int32, stderr: String)
    case commandTimedOut(executable: String, seconds: Double)
    case fileNotFound(path: String)
    case patchMismatch(fileName: String)
    case keychainFailure(status: Int32)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(exec, code, stderr):
            "Command \(exec) failed (exit \(code)): \(stderr)"
        case let .commandTimedOut(exec, seconds):
            "Command \(exec) timed out after \(Int(seconds))s"
        case let .fileNotFound(path):
            "File not found: \(path)"
        case let .patchMismatch(fileName):
            "Snippet mismatch in \(fileName); patch aborted safely"
        case let .keychainFailure(status):
            "Keychain operation failed (OSStatus \(status))"
        }
    }
}

#if canImport(UIKit) && DEBUG
import Foundation
import UIKit
import Network

public struct DevCompanionTelemetryEvent: Codable, Sendable {
    public let kind: String
    public let detail: String
    public let durationMs: Double?
    public let timestamp: Date

    public init(kind: String, detail: String, durationMs: Double? = nil, timestamp: Date = Date()) {
        self.kind = kind
        self.detail = detail
        self.durationMs = durationMs
        self.timestamp = timestamp
    }
}

/// Optional `#if DEBUG` iOS companion agent for real-device main-thread hang watchdog & UIViewController leak tracking.
@MainActor
public final class DevCompanionAgent {
    public static let shared = DevCompanionAgent()

    private var watchdogTask: Task<Void, Never>?
    private var trackedControllers: [(name: String, ref: WeakControllerBox, poppedAt: Date)] = []

    private init() {}

    public func startMainThreadWatchdog(thresholdMs: Double = 250, onHang: @escaping @Sendable (DevCompanionTelemetryEvent) -> Void) {
        watchdogTask?.cancel()
        watchdogTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let start = CFAbsoluteTimeGetCurrent()
                await MainActor.run { _ = 0 }
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                if elapsedMs >= thresholdMs {
                    onHang(
                        DevCompanionTelemetryEvent(
                            kind: "hang",
                            detail: "Main thread blocked",
                            durationMs: elapsedMs
                        )
                    )
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    public func trackDismissed(_ viewController: UIViewController) {
        let name = String(describing: type(of: viewController))
        trackedControllers.append((name, WeakControllerBox(viewController), Date()))
        pruneAndCheck()
    }

    public func currentSuspectedLeaks() -> [String] {
        pruneAndCheck()
        let cutoff = Date().addingTimeInterval(-3.0)
        return trackedControllers
            .filter { $0.ref.value != nil && $0.poppedAt < cutoff }
            .map { $0.name }
    }

    public func stop() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    private func pruneAndCheck() {
        trackedControllers.removeAll { $0.ref.value == nil }
    }
}

private final class WeakControllerBox {
    weak var value: UIViewController?
    init(_ value: UIViewController) { self.value = value }
}
#endif

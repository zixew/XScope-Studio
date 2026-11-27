import Foundation
import AppKit
import UserNotifications

enum BackgroundAlertCategory: String {
    case crash = "crash"
    case hang = "hang"
    case scanComplete = "scan_complete"
    case testsComplete = "tests_complete"
}

@MainActor
final class BackgroundNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var hasRequestedPermission = false
    private var lastSentAt: [BackgroundAlertCategory: Date] = [:]
    private let cooldownSeconds: TimeInterval = 10
    var onSelectModule: ((CompanionModule) -> Void)?

    private var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    override init() {
        super.init()
        if isAppBundle {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestAuthorizationIfNeeded() {
        guard isAppBundle, !hasRequestedPermission else { return }
        hasRequestedPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func notifyIfBackground(
        category: BackgroundAlertCategory,
        title: String,
        body: String,
        module: CompanionModule
    ) {
        guard isAppBundle else { return }
        let isHiddenOrInactive = !NSApp.isActive || NSApp.windows.allSatisfy { !$0.isVisible || $0.isMiniaturized }
        guard isHiddenOrInactive else { return }

        let now = Date()
        if let last = lastSentAt[category], now.timeIntervalSince(last) < cooldownSeconds {
            return
        }
        lastSentAt[category] = now

        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["module": module.rawValue]

        let request = UNNotificationRequest(
            identifier: "xscope.\(category.rawValue).\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let rawModule = response.notification.request.content.userInfo["module"] as? String
        await MainActor.run { [weak self] in
            if let rawModule, let module = CompanionModule(rawValue: rawModule) {
                self?.onSelectModule?(module)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

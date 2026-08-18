import AppKit
import Darwin
import UserNotifications

struct NotificationAuthorizationCoordinator: Sendable {
    static func requestOnLaunchIfNeeded() async {
        guard MacOSNotificationEnvironment.canUseUserNotifications else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}

enum SingleInstanceGuard {
    static func acquire(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        currentProcessID: pid_t = getpid()
    ) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return true
        }

        let existingProcessIDs = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
        return canAcquire(currentProcessID: currentProcessID, existingProcessIDs: existingProcessIDs)
    }

    static func canAcquire(currentProcessID: pid_t, existingProcessIDs: [pid_t]) -> Bool {
        !existingProcessIDs.contains { $0 != currentProcessID }
    }
}

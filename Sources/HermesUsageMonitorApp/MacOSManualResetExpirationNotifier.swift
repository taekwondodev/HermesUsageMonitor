import HermesUsageCore
import UserNotifications

/// Delivers an immediate manual-reset-credit expiration warning. It never
/// registers a future trigger that would survive process termination.
struct MacOSManualResetExpirationNotifier: ManualResetExpirationNotifier {
    func deliver(_ notification: ManualResetExpirationNotification) async -> Bool {
        guard MacOSNotificationEnvironment.canUseUserNotifications else {
            return false
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                return false
            }
        } else if settings.authorizationStatus != .authorized,
                  settings.authorizationStatus != .provisional {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Full reset in scadenza"
        let body: String
        if let earliest = notification.earliestExpiration {
            body = "\(notification.creditCount) Full reset disponibili il \(Self.dayLabel(earliest))."
        } else {
            body = "\(notification.creditCount) Full reset in scadenza."
        }
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "manual-reset-expiration-\(notification.localDate)",
            content: content,
            trigger: nil
        )
        return (try? await center.add(request)) != nil
    }

    private static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: date)
    }
}
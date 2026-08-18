import HermesUsageCore
import UserNotifications

struct MacOSQuotaResetNotifier: QuotaResetNotifier, Sendable {
    func notify(_ notification: QuotaResetNotification) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                return
            }
        } else if settings.authorizationStatus != .authorized,
                  settings.authorizationStatus != .provisional {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "AI Usage"
        content.body = notification.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

private extension QuotaResetNotification {
    var body: String {
        let grouped = Dictionary(grouping: events, by: \.subscription)
        let subscriptions = grouped.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map { subscription in
                let windows = grouped[subscription, default: []]
                    .map(\.windowLabel)
                    .joined(separator: ", ")
                return "\(subscription.displayName): \(windows)"
            }
        return "Quote resettate · " + subscriptions.joined(separator: " · ")
    }
}

private extension Subscription {
    var displayName: String {
        switch self {
        case .nousPortal:
            return "Nous Portal"
        case .opencodeGo:
            return "OpenCode Go"
        case .chatGPT:
            return "ChatGPT"
        }
    }
}

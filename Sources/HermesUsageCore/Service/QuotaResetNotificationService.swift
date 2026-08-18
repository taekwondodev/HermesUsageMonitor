import Foundation

public protocol QuotaResetNotifier: Sendable {
    func notify(_ notification: QuotaResetNotification) async
}

public actor QuotaResetNotificationService {
    private let notifier: any QuotaResetNotifier
    private var previousLiveSubscriptions: [SubscriptionQuota]?

    public init(notifier: any QuotaResetNotifier) {
        self.notifier = notifier
    }

    public func process(_ state: SubscriptionRefreshState) async {
        guard state.availability == .live else { return }

        guard let previousLiveSubscriptions else {
            self.previousLiveSubscriptions = state.subscriptions
            return
        }

        let events = QuotaResetDetector.detect(
            previous: previousLiveSubscriptions,
            current: state.subscriptions
        )
        self.previousLiveSubscriptions = state.subscriptions

        guard !events.isEmpty else { return }
        await notifier.notify(QuotaResetNotification(events: events))
    }
}

public enum QuotaResetDetector {
    public static func detect(
        previous: [SubscriptionQuota],
        current: [SubscriptionQuota]
    ) -> [QuotaResetEvent] {
        current.flatMap { currentSubscription -> [QuotaResetEvent] in
            guard let previousSubscription = previous.first(where: {
                $0.subscription == currentSubscription.subscription
            }),
            case let .snapshot(previousSnapshot) = previousSubscription.result,
            case let .snapshot(currentSnapshot) = currentSubscription.result,
            currentSnapshot.freshness != .stale
            else {
                return []
            }

            return currentSnapshot.windows.compactMap { currentWindow in
                guard let previousWindow = previousSnapshot.windows.first(where: {
                    $0.kind == currentWindow.kind
                }),
                didReset(previous: previousWindow, current: currentWindow)
                else {
                    return nil
                }

                return QuotaResetEvent(
                    subscription: currentSubscription.subscription,
                    windowKind: currentWindow.kind,
                    windowLabel: currentWindow.label
                )
            }
        }
    }

    private static func didReset(previous: QuotaWindow, current: QuotaWindow) -> Bool {
        guard let previousReset = previous.resetAt?.at.date,
              let currentReset = current.resetAt?.at.date else {
            return false
        }
        return currentReset > previousReset
    }
}

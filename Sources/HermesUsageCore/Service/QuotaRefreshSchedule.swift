import Foundation

public struct QuotaWindowReference: Hashable, Sendable {
    public let subscription: Subscription
    public let kind: QuotaWindowKind

    public init(subscription: Subscription, kind: QuotaWindowKind) {
        self.subscription = subscription
        self.kind = kind
    }
}

public enum QuotaRefreshSchedule {
    public static let postResetDelay: TimeInterval = 2
    public static let retryDelay: Duration = .seconds(30)
    public static let maximumRetryAttempts = 1

    public static func nextRetryDelay(after attempts: Int) -> Duration? {
        attempts < maximumRetryAttempts ? retryDelay : nil
    }

    public static func nextLiveReset(
        in state: SubscriptionRefreshState,
        now: Date
    ) -> Date? {
        guard state.availability == .live else { return nil }

        return state.subscriptions
            .compactMap { subscription in
                guard case let .snapshot(snapshot) = subscription.result,
                      snapshot.freshness == .live else {
                    return nil
                }
                return snapshot.windows.compactMap { window in
                    guard let resetAt = window.resetAt?.at.date,
                          resetAt > now else {
                        return nil
                    }
                    return resetAt
                }.min()
            }
            .compactMap { $0 }
            .min()
    }

    public static func expiredLiveWindows(
        in state: SubscriptionRefreshState,
        now: Date
    ) -> Set<QuotaWindowReference> {
        guard state.availability == .live else { return [] }

        return Set(state.subscriptions.flatMap { subscription -> [QuotaWindowReference] in
            guard case let .snapshot(snapshot) = subscription.result,
                  snapshot.freshness == .live else {
                return []
            }
            return snapshot.windows.compactMap { window in
                guard let resetAt = window.resetAt?.at.date,
                      resetAt <= now else {
                    return nil
                }
                return QuotaWindowReference(
                    subscription: subscription.subscription,
                    kind: window.kind
                )
            }
        })
    }

    public static func shouldRetry(
        state: SubscriptionRefreshState,
        attemptedWindows: Set<QuotaWindowReference>,
        now: Date
    ) -> Bool {
        guard state.availability == .live else { return true }

        for attemptedWindow in attemptedWindows {
            guard let subscription = state.subscriptions.first(where: {
                $0.subscription == attemptedWindow.subscription
            }) else {
                return true
            }

            switch subscription.result {
            case .unavailable:
                return true
            case let .snapshot(snapshot):
                guard snapshot.freshness == .live else { return true }
                guard let window = snapshot.windows.first(where: {
                    $0.kind == attemptedWindow.kind
                }) else {
                    continue
                }
                guard let resetAt = window.resetAt?.at.date else { continue }
                if resetAt <= now {
                    return true
                }
            }
        }

        return false
    }
}

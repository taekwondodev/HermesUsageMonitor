import Foundation

public struct QuotaResetEvent: Equatable, Sendable {
    public let subscription: Subscription
    public let windowKind: QuotaWindowKind
    public let windowLabel: String

    public init(
        subscription: Subscription,
        windowKind: QuotaWindowKind,
        windowLabel: String
    ) {
        self.subscription = subscription
        self.windowKind = windowKind
        self.windowLabel = windowLabel
    }
}

public struct QuotaResetNotification: Equatable, Sendable {
    public let events: [QuotaResetEvent]

    public init(events: [QuotaResetEvent]) {
        self.events = events
    }
}

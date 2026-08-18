import Foundation

public enum RefreshAvailability: Equatable, Sendable {
    case live
    case offline
    case waiting
}

public struct SubscriptionRefreshState: Equatable, Sendable {
    public let subscriptions: [SubscriptionQuota]
    public let availability: RefreshAvailability
    public let updatedAt: QuotaTimestamp?

    public init(
        subscriptions: [SubscriptionQuota],
        availability: RefreshAvailability,
        updatedAt: QuotaTimestamp?
    ) {
        self.subscriptions = subscriptions
        self.availability = availability
        self.updatedAt = updatedAt
    }
}

public protocol ProfileQuotaRefreshObserver: Sendable {
    func record(_ state: SubscriptionRefreshState)
}

struct NoopProfileQuotaRefreshObserver: ProfileQuotaRefreshObserver {
    func record(_ state: SubscriptionRefreshState) {}
}

public actor ProfileQuotaRefreshService {
    public static let defaultInterval: Duration = .seconds(900)

    private let source: any ProfileQuotaSource
    private let clock: @Sendable () -> Date
    private let aggregator: ProfileQuotaAggregationService
    private let observer: any ProfileQuotaRefreshObserver
    private var lastSuccessful: [SubscriptionQuota]?

    public init(
        hermesHome: URL,
        clock: @escaping @Sendable () -> Date = Date.init,
        observer: any ProfileQuotaRefreshObserver = OSLogProfileQuotaRefreshObserver()
    ) {
        self.init(
            source: HermesProfileQuotaSnapshotReader(hermesHome: hermesHome, now: clock),
            clock: clock,
            observer: observer
        )
    }

    init(
        source: any ProfileQuotaSource,
        clock: @escaping @Sendable () -> Date = Date.init,
        observer: any ProfileQuotaRefreshObserver = NoopProfileQuotaRefreshObserver()
    ) {
        self.source = source
        self.clock = clock
        aggregator = ProfileQuotaAggregationService(source: source)
        self.observer = observer
    }

    public func refresh() async -> SubscriptionRefreshState {
        let observations = await source.read()
        guard !observations.isEmpty else {
            if let lastSuccessful {
                return record(SubscriptionRefreshState(
                    subscriptions: lastSuccessful.map(markStale),
                    availability: .offline,
                    updatedAt: QuotaTimestamp(date: clock())
                ))
            }

            return record(SubscriptionRefreshState(
                subscriptions: aggregator.aggregate([]),
                availability: .waiting,
                updatedAt: nil
            ))
        }

        let subscriptions = aggregator.aggregate(observations)
        lastSuccessful = subscriptions
        return record(SubscriptionRefreshState(
            subscriptions: subscriptions,
            availability: .live,
            updatedAt: QuotaTimestamp(date: clock())
        ))
    }

    private func record(_ state: SubscriptionRefreshState) -> SubscriptionRefreshState {
        observer.record(state)
        return state
    }

    private func markStale(_ subscription: SubscriptionQuota) -> SubscriptionQuota {
        guard case let .snapshot(snapshot) = subscription.result else {
            return subscription
        }
        return SubscriptionQuota(
            subscription: subscription.subscription,
            result: .snapshot(snapshot.withFreshness(.stale))
        )
    }
}

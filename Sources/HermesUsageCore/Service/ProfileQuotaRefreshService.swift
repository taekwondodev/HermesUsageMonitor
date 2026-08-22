import Foundation

public enum RefreshAvailability: Equatable, Sendable {
    case live
    case offline
    case waiting
}

public struct SubscriptionRefreshState: Equatable, Sendable {
    public let subscriptions: [SubscriptionQuota]
    public let manualReset: ManualResetRefreshState
    public let availability: RefreshAvailability
    public let updatedAt: QuotaTimestamp?

    public init(
        subscriptions: [SubscriptionQuota],
        manualReset: ManualResetRefreshState = .unavailable,
        availability: RefreshAvailability,
        updatedAt: QuotaTimestamp?
    ) {
        self.subscriptions = subscriptions
        self.manualReset = manualReset
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

    private let source: any ProfileUsageSource
    private let clock: @Sendable () -> Date
    private let aggregator: ProfileQuotaAggregator
    private let observer: any ProfileQuotaRefreshObserver
    private let manualResetService: ManualResetRefreshService
    private let expirationNotifier: ManualResetExpirationNotifierService
    private var lastSuccessful: [SubscriptionQuota]?

    public init(
        hermesHome: URL,
        clock: @escaping @Sendable () -> Date = Date.init,
        observer: any ProfileQuotaRefreshObserver,
        manualResetObserver: any ManualResetRefreshObserver,
        expirationNotifier: (any ManualResetExpirationNotifier)? = nil,
        expirationHistory: (any ManualResetExpirationHistory)? = nil,
        expirationObserver: any ManualResetExpirationObserver = NoopManualResetExpirationObserver()
    ) {
        self.init(
            source: HermesUsageCommandReader(hermesHome: hermesHome),
            clock: clock,
            observer: observer,
            manualResetObserver: manualResetObserver,
            expirationNotifier: expirationNotifier,
            expirationHistory: expirationHistory,
            expirationObserver: expirationObserver
        )
    }

    init(
        source: any ProfileUsageSource,
        clock: @escaping @Sendable () -> Date = Date.init,
        observer: any ProfileQuotaRefreshObserver = NoopProfileQuotaRefreshObserver(),
        manualResetObserver: any ManualResetRefreshObserver = NoopManualResetRefreshObserver(),
        expirationNotifier: (any ManualResetExpirationNotifier)? = nil,
        expirationHistory: (any ManualResetExpirationHistory)? = nil,
        expirationObserver: any ManualResetExpirationObserver = NoopManualResetExpirationObserver()
    ) {
        self.source = source
        self.clock = clock
        aggregator = ProfileQuotaAggregator()
        self.observer = observer
        manualResetService = ManualResetRefreshService(
            clock: clock,
            observer: manualResetObserver
        )
        self.expirationNotifier = ManualResetExpirationNotifierService(
            notifier: expirationNotifier ?? NoopManualResetExpirationNotifier(),
            history: expirationHistory ?? NoopManualResetExpirationHistory(),
            observer: expirationObserver
        )
    }

    public func refresh() async -> SubscriptionRefreshState {
        let read = await source.readUsage()
        let observations = read.quotaObservations
        let manualReset = await manualResetService.refresh(read.manualReset)
        if case .live = manualReset {
            await expirationNotifier.process(read.manualReset)
        }
        guard !observations.isEmpty else {
            if let lastSuccessful {
                return record(SubscriptionRefreshState(
                    subscriptions: lastSuccessful.map(markStale),
                    manualReset: manualReset,
                    availability: .offline,
                    updatedAt: QuotaTimestamp(date: clock())
                ))
            }

            return record(SubscriptionRefreshState(
                subscriptions: aggregator.aggregate([]),
                manualReset: manualReset,
                availability: .waiting,
                updatedAt: nil
            ))
        }

        let subscriptions = mergeWithLastSuccessful(aggregator.aggregate(observations))
        lastSuccessful = subscriptions
        return record(SubscriptionRefreshState(
            subscriptions: subscriptions,
            manualReset: manualReset,
            availability: .live,
            updatedAt: QuotaTimestamp(date: clock())
        ))
    }

    private func mergeWithLastSuccessful(
        _ subscriptions: [SubscriptionQuota]
    ) -> [SubscriptionQuota] {
        guard let lastSuccessful else { return subscriptions }

        return subscriptions.map { current in
            guard case .unavailable = current.result,
                  let previous = lastSuccessful.first(where: {
                      $0.subscription == current.subscription
                  }) else {
                return current
            }
            return markStale(previous)
        }
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

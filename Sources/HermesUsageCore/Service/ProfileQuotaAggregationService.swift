import Foundation

protocol ProfileQuotaSource: Sendable {
    func read() async -> [ProfileQuotaObservation]
}

public protocol ProfileQuotaAggregationObserver: Sendable {
    func record(_ result: [SubscriptionQuota])
}

struct NoopProfileQuotaAggregationObserver: ProfileQuotaAggregationObserver {
    func record(_ result: [SubscriptionQuota]) {}
}

public struct ProfileQuotaAggregationService: Sendable {
    private let source: any ProfileQuotaSource
    private let observer: any ProfileQuotaAggregationObserver

    public init(
        hermesHome: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        observer: any ProfileQuotaAggregationObserver = OSLogProfileQuotaAggregationObserver()
    ) {
        source = HermesProfileQuotaSnapshotReader(hermesHome: hermesHome, now: now)
        self.observer = observer
    }

    init(
        source: any ProfileQuotaSource,
        observer: any ProfileQuotaAggregationObserver = NoopProfileQuotaAggregationObserver()
    ) {
        self.source = source
        self.observer = observer
    }

    public func read() async -> [SubscriptionQuota] {
        let result = aggregate(await source.read())
        observer.record(result)
        return result
    }

    func aggregate(_ observations: [ProfileQuotaObservation]) -> [SubscriptionQuota] {
        Subscription.allCases.map { subscription in
            let matching = observations.filter { $0.subscription == subscription }
            return SubscriptionQuota(
                subscription: subscription,
                result: bestResult(from: matching)
            )
        }
    }

    private func bestResult(
        from observations: [ProfileQuotaObservation]
    ) -> QuotaReadResult {
        guard !observations.isEmpty else {
            return .unavailable(.sourceMissing)
        }

        let snapshots = observations.compactMap { observation -> (QuotaSnapshot, QuotaTimestamp)? in
            guard case let .snapshot(snapshot) = observation.result else {
                return nil
            }
            return (snapshot, observation.observedAt)
        }

        if let bestSnapshot = snapshots.max(by: isLessReliable) {
            return .snapshot(bestSnapshot.0)
        }

        return observations.max { $0.observedAt.date < $1.observedAt.date }?.result
            ?? .unavailable(.sourceMissing)
    }

    private func isLessReliable(
        _ lhs: (QuotaSnapshot, QuotaTimestamp),
        _ rhs: (QuotaSnapshot, QuotaTimestamp)
    ) -> Bool {
        let lhsRank = freshnessRank(lhs.0.freshness)
        let rhsRank = freshnessRank(rhs.0.freshness)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.0.capturedAt.date != rhs.0.capturedAt.date {
            return lhs.0.capturedAt.date < rhs.0.capturedAt.date
        }
        return lhs.1.date < rhs.1.date
    }

    private func freshnessRank(_ freshness: QuotaFreshness) -> Int {
        switch freshness {
        case .stale:
            return 0
        case .persisted:
            return 1
        case .live:
            return 2
        }
    }
}

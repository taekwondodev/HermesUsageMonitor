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
    private let aggregator: ProfileQuotaAggregator

    public init(
        hermesHome: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        observer: any ProfileQuotaAggregationObserver = OSLogProfileQuotaAggregationObserver()
    ) {
        source = HermesProfileQuotaSnapshotReader(hermesHome: hermesHome, now: now)
        aggregator = ProfileQuotaAggregator(observer: observer)
    }

    init(
        source: any ProfileQuotaSource,
        observer: any ProfileQuotaAggregationObserver = NoopProfileQuotaAggregationObserver()
    ) {
        self.source = source
        aggregator = ProfileQuotaAggregator(observer: observer)
    }

    public func read() async -> [SubscriptionQuota] {
        aggregator.aggregate(await source.read())
    }

    func aggregate(_ observations: [ProfileQuotaObservation]) -> [SubscriptionQuota] {
        aggregator.aggregate(observations)
    }
}

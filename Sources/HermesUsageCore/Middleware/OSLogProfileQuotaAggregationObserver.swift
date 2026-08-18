import OSLog

public struct OSLogProfileQuotaAggregationObserver: ProfileQuotaAggregationObserver, Sendable {
    private let logger: Logger

    public init(subsystem: String = "HermesUsageMonitor") {
        logger = Logger(subsystem: subsystem, category: "profile-aggregation")
    }

    public func record(_ result: [SubscriptionQuota]) {
        let availableCount = result.reduce(into: 0) { count, subscription in
            if case .snapshot = subscription.result {
                count += 1
            }
        }
        logger.debug(
            "Profile quota aggregation completed: \(availableCount, privacy: .public)/\(result.count, privacy: .public) subscriptions available"
        )
    }
}

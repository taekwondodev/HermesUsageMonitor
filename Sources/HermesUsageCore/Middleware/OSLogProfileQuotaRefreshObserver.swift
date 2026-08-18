import OSLog

public struct OSLogProfileQuotaRefreshObserver: ProfileQuotaRefreshObserver, Sendable {
    private let logger: Logger

    public init(subsystem: String = "HermesUsageMonitor") {
        logger = Logger(subsystem: subsystem, category: "quota-refresh")
    }

    public func record(_ state: SubscriptionRefreshState) {
        let availability: String
        switch state.availability {
        case .live:
            availability = "live"
        case .offline:
            availability = "offline"
        case .waiting:
            availability = "waiting"
        }
        logger.debug("Quota refresh completed: \(availability, privacy: .public)")
    }
}

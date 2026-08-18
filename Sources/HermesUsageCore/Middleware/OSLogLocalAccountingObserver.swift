import OSLog

public struct OSLogLocalAccountingObserver: LocalAccountingObserver, Sendable {
    private let logger: Logger

    public init(subsystem: String = "HermesUsageMonitor") {
        logger = Logger(subsystem: subsystem, category: "local-accounting")
    }

    public func record(_ result: GroupedLocalAccountingResult) {
        let outcome: String
        switch result {
        case let .available(grouped):
            outcome = "available.\(grouped.count)-subscriptions"
        case let .unavailable(reason):
            outcome = "unavailable.\(reason)"
        }
        logger.debug("Local accounting read outcome: \(outcome, privacy: .public)")
    }
}

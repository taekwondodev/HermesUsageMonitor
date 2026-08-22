import OSLog

public struct OSLogManualResetRefreshObserver: ManualResetRefreshObserver, Sendable {
    private let logger: Logger

    public init(subsystem: String = "HermesUsageMonitor") {
        logger = Logger(subsystem: subsystem, category: "manual-reset-refresh")
    }

    public func record(_ state: ManualResetRefreshState) {
        switch state {
        case let .live(summary):
            logger.debug(
                "Manual reset refresh completed: live, count=\(summary.availableCount, privacy: .public), applicable=\(summary.isApplicable, privacy: .public)"
            )
        case let .stale(summary):
            logger.debug(
                "Manual reset refresh completed: stale, count=\(summary.availableCount, privacy: .public)"
            )
        case .unavailable:
            logger.debug("Manual reset refresh completed: unavailable")
        }
    }
}

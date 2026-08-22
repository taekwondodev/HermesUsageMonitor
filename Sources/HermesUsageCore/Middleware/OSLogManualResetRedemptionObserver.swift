import OSLog

public struct OSLogManualResetRedemptionObserver: ManualResetRedemptionObserver, Sendable {
    private let logger: Logger

    public init(subsystem: String = "HermesUsageMonitor") {
        logger = Logger(subsystem: subsystem, category: "manual-reset-redemption")
    }

    public func record(_ state: ManualResetRedemptionState) {
        switch state {
        case .idle:
            logger.debug("Manual reset redemption: idle")
        case .redeeming:
            logger.debug("Manual reset redemption: in flight")
        case .success:
            logger.debug("Manual reset redemption: confirmed success")
        case .verificationRequired:
            logger.debug("Manual reset redemption: outcome unverified, block enabled")
        case .rejected:
            logger.debug("Manual reset redemption: definite rejection")
        case .notConsumed:
            logger.debug("Manual reset redemption: not consumed")
        }
    }
}
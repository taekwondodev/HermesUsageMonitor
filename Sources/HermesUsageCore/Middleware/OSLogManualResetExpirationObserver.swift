import OSLog

public struct OSLogManualResetExpirationObserver: ManualResetExpirationObserver, Sendable {
    private let logger: Logger

    public init(subsystem: String = "HermesUsageMonitor") {
        logger = Logger(subsystem: subsystem, category: "manual-reset-expiration")
    }

    public func record(_ state: ManualResetExpirationObservation) {
        switch state {
        case .eligible(let localDate, let creditCount):
            logger.debug("Manual reset expiration: eligible \(creditCount) credit(s) on \(localDate)")
        case .alreadyNotified(let localDate):
            logger.debug("Manual reset expiration: \(localDate) already notified")
        case .deliverySucceeded(let localDate):
            logger.debug("Manual reset expiration: delivered for \(localDate)")
        case .deliveryFailed(let localDate):
            logger.debug("Manual reset expiration: delivery failed for \(localDate)")
        case .skippedNonLive:
            logger.debug("Manual reset expiration: skipped non-live snapshot")
        }
    }
}
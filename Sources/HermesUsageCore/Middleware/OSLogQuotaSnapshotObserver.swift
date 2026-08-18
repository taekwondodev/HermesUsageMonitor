import OSLog

public struct OSLogQuotaSnapshotObserver: QuotaSnapshotObserver, Sendable {
    private let logger: Logger

    public init(subsystem: String = "HermesUsageMonitor") {
        logger = Logger(subsystem: subsystem, category: "quota")
    }

    public func record(_ result: QuotaReadResult) {
        let outcome: String
        switch result {
        case .snapshot:
            outcome = "snapshot"
        case let .unavailable(reason):
            outcome = "unavailable.\(reason)"
        }
        logger.debug("Quota snapshot read outcome: \(outcome, privacy: .public)")
    }
}

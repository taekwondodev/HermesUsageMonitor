import Foundation

public protocol ManualResetRefreshObserver: Sendable {
    func record(_ state: ManualResetRefreshState)
}

struct NoopManualResetRefreshObserver: ManualResetRefreshObserver {
    func record(_ state: ManualResetRefreshState) {}
}

actor ManualResetRefreshService {
    private let clock: @Sendable () -> Date
    private let observer: any ManualResetRefreshObserver
    private var lastSuccessfulSnapshot: ManualResetSnapshot?
    private var lastSuccessful: ManualResetSummary?

    init(
        clock: @escaping @Sendable () -> Date = Date.init,
        observer: any ManualResetRefreshObserver = NoopManualResetRefreshObserver()
    ) {
        self.clock = clock
        self.observer = observer
    }

    func refresh(_ result: ManualResetReadResult) -> ManualResetRefreshState {
        let state: ManualResetRefreshState
        switch result {
        case let .snapshot(snapshot):
            if let summary = try? summarize(snapshot, now: clock()) {
                lastSuccessfulSnapshot = snapshot
                lastSuccessful = summary
                state = .live(summary)
            } else if let lastSuccessful {
                state = .stale(lastSuccessful)
            } else {
                state = .unavailable
            }
        case .unavailable:
            if let lastSuccessful {
                state = .stale(lastSuccessful)
            } else {
                state = .unavailable
            }
        }
        observer.record(state)
        return state
    }

    private func summarize(_ snapshot: ManualResetSnapshot, now: Date) throws -> ManualResetSummary {
        let eligibleCredits = snapshot.credits.filter { credit in
            guard credit.status == .available,
                  credit.isSupportedByPlan else {
                return false
            }
            return credit.expiresAt.map { $0 > now } ?? true
        }
        let detailsAreComplete = eligibleCredits.count == snapshot.availableCount
        let expiration: ManualResetExpiration
        if snapshot.availableCount == 0 {
            expiration = .unavailable
        } else if !detailsAreComplete {
            expiration = .unavailable
        } else if let nearest = eligibleCredits.compactMap(\.expiresAt).min() {
            expiration = .dated(QuotaTimestamp(date: nearest))
        } else {
            expiration = .doesNotExpire
        }
        let isApplicable = snapshot.applicableAvailableCount > 0
        return try ManualResetSummary(
            availableCount: snapshot.availableCount,
            applicableAvailableCount: snapshot.applicableAvailableCount,
            expiration: expiration,
            isApplicable: isApplicable,
            hasActionableCredit: isApplicable && detailsAreComplete && !eligibleCredits.isEmpty
        )
    }
}

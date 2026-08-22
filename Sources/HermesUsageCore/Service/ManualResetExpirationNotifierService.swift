import Foundation

struct NoopManualResetExpirationNotifier: ManualResetExpirationNotifier {
    func deliver(_ notification: ManualResetExpirationNotification) async -> Bool { true }
}

struct NoopManualResetExpirationHistory: ManualResetExpirationHistory {
    func contains(_ key: ManualResetExpirationGroupKey) async -> Bool { false }
    func record(_ key: ManualResetExpirationGroupKey) async {}
}

/// Evaluates manual reset credit expirations and emits at most one immediate
/// notification per local expiration date, deduplicated across refreshes and
/// restarts. Only coherent live provider snapshots are eligible.
actor ManualResetExpirationNotifierService {
    private static let providerKey = "manual-reset-credit"

    private let notifier: any ManualResetExpirationNotifier
    private let history: any ManualResetExpirationHistory
    private let observer: any ManualResetExpirationObserver
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    init(
        notifier: any ManualResetExpirationNotifier,
        history: any ManualResetExpirationHistory,
        observer: any ManualResetExpirationObserver = NoopManualResetExpirationObserver(),
        clock: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.notifier = notifier
        self.history = history
        self.observer = observer
        self.clock = clock
        self.calendar = calendar
    }

    func process(_ result: ManualResetReadResult) async {
        guard case let .snapshot(snapshot) = result else {
            observer.record(.skippedNonLive)
            return
        }
        let now = clock()
        for group in Self.eligibleGroups(in: snapshot, now: now, calendar: calendar) {
            let key = ManualResetExpirationGroupKey(
                provider: Self.providerKey,
                localDate: group.key.localDate
            )
            if await history.contains(key) {
                observer.record(.alreadyNotified(localDate: key.localDate))
                continue
            }
            observer.record(.eligible(localDate: key.localDate, creditCount: group.value.creditCount))
            if await notifier.deliver(group.value) {
                observer.record(.deliverySucceeded(localDate: key.localDate))
                await history.record(ManualResetExpirationGroupKey(
                    provider: Self.providerKey,
                    localDate: key.localDate
                ))
            } else {
                observer.record(.deliveryFailed(localDate: key.localDate))
            }
        }
    }

    /// Groups unexpired, dated, plan-supported credits by the user's local calendar
    /// expiration date and marks a group eligible when its earliest credit has at
    /// most 24 hours remaining (and not yet expired).
    static func eligibleGroups(
        in snapshot: ManualResetSnapshot,
        now: Date,
        calendar: Calendar
    ) -> [ManualResetExpirationGroupKey: ManualResetExpirationNotification] {
        let deadline: TimeInterval = 24 * 60 * 60
        var buckets: [String: [(expiresAt: Date, count: Int)]] = [:]

        for credit in snapshot.credits {
            guard credit.status == .available,
                  credit.isSupportedByPlan,
                  let expiresAt = credit.expiresAt else {
                continue
            }
            // "unexpired dated credits"
            guard expiresAt > now else { continue }
            let localDate = Self.localDateKey(for: expiresAt, calendar: calendar)
            buckets[localDate, default: []].append((expiresAt, 1))
        }

        var result: [ManualResetExpirationGroupKey: ManualResetExpirationNotification] = [:]
        for (localDate, entries) in buckets where !entries.isEmpty {
            guard let earliest = entries.map(\.expiresAt).min() else { continue }
            let remaining = earliest.timeIntervalSince(now)
            // eligible only when the earliest credit first has <=24h remaining
            guard remaining <= deadline, remaining > 0 else { continue }
            result[ManualResetExpirationGroupKey(provider: Self.providerKey, localDate: localDate)] =
                ManualResetExpirationNotification(
                    provider: Self.providerKey,
                    localDate: localDate,
                    creditCount: entries.map(\.count).reduce(0, +),
                    earliestExpiration: earliest
                )
        }
        return result
    }

    private static func localDateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
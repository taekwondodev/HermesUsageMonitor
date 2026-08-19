import Foundation
import Testing
@testable import HermesUsageCore

struct QuotaRefreshScheduleTests {
    @Test("selects the earliest future reset from live quota windows")
    func selectsEarliestLiveReset() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = try state(
            availability: .live,
            freshness: .live,
            windows: [
                try window(kind: .weekly, usedPercent: 40, resetAt: 1_300),
                try window(kind: .rollingFiveHours, usedPercent: 50, resetAt: 1_120),
                try window(kind: .monthly, usedPercent: 20, resetAt: 1_900)
            ]
        )

        #expect(
            QuotaRefreshSchedule.nextLiveReset(in: state, now: now)
                == Date(timeIntervalSince1970: 1_120)
        )
    }

    @Test("ignores persisted, stale, and missing reset timestamps")
    func ignoresNonLiveAndUnverifiableWindows() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let persistedState = try state(
            availability: .live,
            freshness: .persisted,
            windows: [try window(kind: .weekly, usedPercent: 40, resetAt: 1_100)]
        )
        let staleState = try state(
            availability: .live,
            freshness: .stale,
            windows: [try window(kind: .weekly, usedPercent: 40, resetAt: 1_100)]
        )
        let missingResetState = try state(
            availability: .live,
            freshness: .live,
            windows: [try window(kind: .weekly, usedPercent: 40, resetAt: nil)]
        )

        #expect(QuotaRefreshSchedule.nextLiveReset(in: persistedState, now: now) == nil)
        #expect(QuotaRefreshSchedule.nextLiveReset(in: staleState, now: now) == nil)
        #expect(QuotaRefreshSchedule.nextLiveReset(in: missingResetState, now: now) == nil)
    }

    @Test("reports expired live windows without scheduling a cascade")
    func reportsExpiredWindows() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = try state(
            availability: .live,
            freshness: .live,
            windows: [try window(kind: .rollingFiveHours, usedPercent: 80, resetAt: 900)]
        )

        #expect(
            QuotaRefreshSchedule.expiredLiveWindows(in: state, now: now)
                == [QuotaWindowReference(subscription: .opencodeGo, kind: .rollingFiveHours)]
        )
        #expect(
            QuotaRefreshSchedule.shouldRetry(
                state: state,
                attemptedWindows: [QuotaWindowReference(subscription: .opencodeGo, kind: .rollingFiveHours)],
                now: now
            )
        )
    }

    @Test("allows one retry after 30 seconds and no second retry")
    func limitsRetryAttempts() {
        #expect(QuotaRefreshSchedule.nextRetryDelay(after: 0) == .seconds(30))
        #expect(QuotaRefreshSchedule.nextRetryDelay(after: 1) == nil)
    }

    @Test("retries a partial live result when the attempted subscription is unavailable")
    func retriesPartialLiveResult() {
        let state = SubscriptionRefreshState(
            subscriptions: [SubscriptionQuota(
                subscription: .opencodeGo,
                result: .unavailable(.sourceMissing)
            )],
            availability: .live,
            updatedAt: nil
        )
        let attempted: Set<QuotaWindowReference> = [
            QuotaWindowReference(subscription: .opencodeGo, kind: .rollingFiveHours)
        ]

        #expect(
            QuotaRefreshSchedule.shouldRetry(
                state: state,
                attemptedWindows: attempted,
                now: Date(timeIntervalSince1970: 1_000)
            )
        )
    }

    @Test("retries unavailable refreshes once without using accounting data")
    func retriesUnavailableRefresh() throws {
        let state = try state(
            availability: .offline,
            freshness: .stale,
            windows: [try window(kind: .rollingFiveHours, usedPercent: 80, resetAt: 900)]
        )
        let attempted: Set<QuotaWindowReference> = [QuotaWindowReference(subscription: .opencodeGo, kind: .rollingFiveHours)]

        #expect(
            QuotaRefreshSchedule.shouldRetry(
                state: state,
                attemptedWindows: attempted,
                now: Date(timeIntervalSince1970: 1_000)
            )
        )
        #expect(QuotaRefreshSchedule.retryDelay == .seconds(30))
    }

    private func state(
        availability: RefreshAvailability,
        freshness: QuotaFreshness,
        windows: [QuotaWindow]
    ) throws -> SubscriptionRefreshState {
        let snapshot = try QuotaSnapshot(
            subscription: .opencodeGo,
            capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 900)),
            freshness: freshness,
            windows: windows,
            source: try QuotaSource(identifier: "test")
        )
        return SubscriptionRefreshState(
            subscriptions: [SubscriptionQuota(
                subscription: .opencodeGo,
                result: .snapshot(snapshot)
            )],
            availability: availability,
            updatedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 900))
        )
    }

    private func window(
        kind: QuotaWindowKind,
        usedPercent: Double,
        resetAt: TimeInterval?
    ) throws -> QuotaWindow {
        try QuotaWindow(
            kind: kind,
            label: kind.rawValue,
            usedPercent: usedPercent,
            resetAt: resetAt.map { QuotaReset(date: Date(timeIntervalSince1970: $0)) }
        )
    }
}

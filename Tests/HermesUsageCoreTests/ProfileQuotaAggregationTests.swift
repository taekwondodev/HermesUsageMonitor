import Foundation
import Testing
@testable import HermesUsageCore

struct ProfileQuotaAggregationTests {
    @Test("returns stable subscription groups without exposing profiles")
    func returnsStableSubscriptionGroups() throws {
        let observations = [
            try observation(
                profile: "work",
                subscription: .nousPortal,
                capturedAt: 100,
                usedPercent: 20
            ),
            try observation(
                profile: "personal",
                subscription: .chatGPT,
                capturedAt: 100,
                usedPercent: 30
            )
        ]

        let result = ProfileQuotaAggregationService(
            source: StubSource(observations: observations)
        ).read()

        #expect(result.map(\.subscription) == [.nousPortal, .opencodeGo, .chatGPT])
        #expect(result.count == 3)
        #expect(result[0].result.isSnapshot)
        #expect(result[1].result == .unavailable(.sourceMissing))
        #expect(result[2].result.isSnapshot)
    }

    @Test("does not sum duplicate quota snapshots from profiles")
    func doesNotSumDuplicates() throws {
        let observations = [
            try observation(
                profile: "first",
                subscription: .nousPortal,
                capturedAt: 100,
                usedPercent: 20
            ),
            try observation(
                profile: "second",
                subscription: .nousPortal,
                capturedAt: 100,
                usedPercent: 20
            )
        ]

        let result = ProfileQuotaAggregationService(
            source: StubSource(observations: observations)
        ).read()

        guard case let .snapshot(snapshot) = result[0].result else {
            Issue.record("Expected a Nous Portal snapshot")
            return
        }
        #expect(snapshot.windows[0].usedPercent == 20)
    }

    @Test("chooses the newest reliable snapshot when profiles conflict")
    func choosesNewestReliableSnapshot() throws {
        let observations = [
            try observation(
                profile: "old",
                subscription: .opencodeGo,
                capturedAt: 100,
                usedPercent: 10
            ),
            try observation(
                profile: "new",
                subscription: .opencodeGo,
                capturedAt: 200,
                usedPercent: 80
            )
        ]

        let result = ProfileQuotaAggregationService(
            source: StubSource(observations: observations)
        ).read()

        guard case let .snapshot(snapshot) = result[1].result else {
            Issue.record("Expected an OpenCode Go snapshot")
            return
        }
        #expect(snapshot.windows[0].usedPercent == 80)
    }

    @Test("prefers live data over an older persisted snapshot")
    func prefersMoreReliableFreshness() throws {
        let observations = [
            try observation(
                profile: "persisted",
                subscription: .chatGPT,
                capturedAt: 300,
                usedPercent: 80,
                freshness: .persisted
            ),
            try observation(
                profile: "live",
                subscription: .chatGPT,
                capturedAt: 100,
                usedPercent: 20,
                freshness: .live
            )
        ]

        let result = ProfileQuotaAggregationService(
            source: StubSource(observations: observations)
        ).read()

        guard case let .snapshot(snapshot) = result[2].result else {
            Issue.record("Expected a ChatGPT snapshot")
            return
        }
        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows[0].usedPercent == 20)
    }

    @Test("rejects a profile observation with a mismatched subscription")
    func rejectsMismatchedSubscription() throws {
        let snapshot = try QuotaSnapshot(
            subscription: .chatGPT,
            capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 100)),
            windows: [try QuotaWindow(
                kind: .weekly,
                label: "Weekly",
                usedPercent: 10
            )],
            source: try QuotaSource(identifier: "profile")
        )

        #expect(throws: QuotaDomainError.invalidSnapshot) {
            _ = try ProfileQuotaObservation(
                profile: try HermesProfileID(value: "profile"),
                subscription: .nousPortal,
                observedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 100)),
                result: .snapshot(snapshot)
            )
        }
    }

    private func observation(
        profile: String,
        subscription: Subscription,
        capturedAt: TimeInterval,
        usedPercent: Double,
        freshness: QuotaFreshness = .persisted
    ) throws -> ProfileQuotaObservation {
        let snapshot = try QuotaSnapshot(
            subscription: subscription,
            capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: capturedAt)),
            freshness: freshness,
            windows: [try QuotaWindow(
                kind: .rollingFiveHours,
                label: "5 hours",
                usedPercent: usedPercent
            )],
            source: try QuotaSource(identifier: "profile-\(profile)")
        )
        return try ProfileQuotaObservation(
            profile: try HermesProfileID(value: profile),
            subscription: subscription,
            observedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: capturedAt)),
            result: .snapshot(snapshot)
        )
    }

    private struct StubSource: ProfileQuotaSource {
        let observations: [ProfileQuotaObservation]

        func read() -> [ProfileQuotaObservation] {
            observations
        }
    }
}

private extension QuotaReadResult {
    var isSnapshot: Bool {
        if case .snapshot = self { return true }
        return false
    }
}

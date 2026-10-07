import Foundation
import Testing
@testable import HermesUsageCore

struct ProfileQuotaAggregationTests {
    @Test("returns stable subscription groups without exposing profiles")
    func returnsStableSubscriptionGroups() async throws {
        let observations = [
            try observation(
                profile: "work",
                subscription: .chatGPT,
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

        let result = await ProfileQuotaAggregationService(
            source: StubSource(observations: observations)
        ).read()

        #expect(result.map(\.subscription) == [.chatGPT, .claude])
        #expect(result.count == 2)
        #expect(result[1].result == .unavailable(.sourceMissing))
        #expect(result[0].result.isSnapshot)
    }

    @Test("does not sum duplicate quota snapshots from profiles")
    func doesNotSumDuplicates() async throws {
        let observations = [
            try observation(
                profile: "first",
                subscription: .chatGPT,
                capturedAt: 100,
                usedPercent: 20
            ),
            try observation(
                profile: "second",
                subscription: .chatGPT,
                capturedAt: 100,
                usedPercent: 20
            )
        ]

        let result = await ProfileQuotaAggregationService(
            source: StubSource(observations: observations)
        ).read()

        guard case let .snapshot(snapshot) = result[0].result else {
            Issue.record("Expected a ChatGPT snapshot")
            return
        }
        #expect(snapshot.windows[0].usedPercent == 20)
    }

    @Test("chooses the newest reliable snapshot when profiles conflict")
    func choosesNewestReliableSnapshot() async throws {
        let observations = [
            try observation(
                profile: "old",
                subscription: .chatGPT,
                capturedAt: 100,
                usedPercent: 10
            ),
            try observation(
                profile: "new",
                subscription: .chatGPT,
                capturedAt: 200,
                usedPercent: 80
            )
        ]

        let result = await ProfileQuotaAggregationService(
            source: StubSource(observations: observations)
        ).read()

        guard case let .snapshot(snapshot) = result[0].result else {
            Issue.record("Expected a ChatGPT snapshot")
            return
        }
        #expect(snapshot.windows[0].usedPercent == 80)
    }

    @Test("prefers live data over an older persisted snapshot")
    func prefersMoreReliableFreshness() async throws {
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

        let result = await ProfileQuotaAggregationService(
            source: StubSource(observations: observations)
        ).read()

        guard case let .snapshot(snapshot) = result[0].result else {
            Issue.record("Expected a ChatGPT snapshot")
            return
        }
        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows[0].usedPercent == 20)
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

        func read() async -> [ProfileQuotaObservation] {
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

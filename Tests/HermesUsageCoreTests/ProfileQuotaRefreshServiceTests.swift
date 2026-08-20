import Foundation
import Testing
@testable import HermesUsageCore

struct ProfileQuotaRefreshServiceTests {
    @Test("keeps the last valid snapshot and marks it stale when offline")
    func keepsLastSnapshotWhenOffline() async throws {
        let source = SequenceSource(reads: [[try observation()]])
        let service = ProfileQuotaRefreshService(
            source: source,
            clock: { Date(timeIntervalSince1970: 500) }
        )

        let live = await service.refresh()
        let offline = await service.refresh()

        #expect(live.availability == .live)
        #expect(live.updatedAt?.date == Date(timeIntervalSince1970: 500))
        #expect(offline.availability == .offline)
        guard case let .snapshot(snapshot) = offline.subscriptions.first(where: {
            $0.subscription == .chatGPT
        })?.result else {
            Issue.record("Expected the last snapshot to remain visible")
            return
        }
        #expect(snapshot.freshness == .stale)
        #expect(snapshot.windows[0].usedPercent == 25)
    }

    @Test("starts in waiting state when no snapshot has ever been observed")
    func startsWaitingWithoutData() async {
        let service = ProfileQuotaRefreshService(
            source: SequenceSource(reads: [[]]),
            clock: Date.init
        )

        let state = await service.refresh()

        #expect(state.availability == .waiting)
        #expect(state.updatedAt == nil)
        #expect(state.subscriptions.count == 2)
    }

    @Test("preserves the last snapshot for a partially unavailable subscription")
    func preservesPartialSnapshot() async throws {
        let source = SequenceSource(reads: [
            [try observation(subscription: .chatGPT, usedPercent: 25),
             try observation(subscription: .opencodeGo, usedPercent: 40)],
            [try observation(subscription: .chatGPT, usedPercent: 10)]
        ])
        let service = ProfileQuotaRefreshService(source: source, clock: Date.init)

        _ = await service.refresh()
        let partial = await service.refresh()

        guard case let .snapshot(chatGPT) = partial.subscriptions.first(where: {
            $0.subscription == .chatGPT
        })?.result,
        case let .snapshot(opencode) = partial.subscriptions.first(where: {
            $0.subscription == .opencodeGo
        })?.result else {
            Issue.record("Expected both subscriptions to retain usable snapshots")
            return
        }

        #expect(chatGPT.freshness == .live)
        #expect(chatGPT.windows[0].usedPercent == 10)
        #expect(opencode.freshness == .stale)
        #expect(opencode.windows[0].usedPercent == 40)
    }

    private func observation(
        subscription: Subscription = .chatGPT,
        usedPercent: Double = 25
    ) throws -> ProfileQuotaObservation {
        let snapshot = try QuotaSnapshot(
            subscription: subscription,
            capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 100)),
            freshness: .live,
            windows: [try QuotaWindow(
                kind: .rollingFiveHours,
                label: "5 hours",
                usedPercent: usedPercent
            )],
            source: try QuotaSource(identifier: "test")
        )
        return try ProfileQuotaObservation(
            profile: try HermesProfileID(value: "test"),
            subscription: subscription,
            observedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 100)),
            result: .snapshot(snapshot)
        )
    }

    private actor SequenceSource: ProfileQuotaSource {
        var reads: [[ProfileQuotaObservation]]

        init(reads: [[ProfileQuotaObservation]]) {
            self.reads = reads
        }

        func read() async -> [ProfileQuotaObservation] {
            guard !reads.isEmpty else { return [] }
            return reads.removeFirst()
        }
    }
}

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
        guard case let .snapshot(snapshot) = offline.subscriptions[0].result else {
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
        #expect(state.subscriptions.count == 3)
    }

    private func observation() throws -> ProfileQuotaObservation {
        let snapshot = try QuotaSnapshot(
            subscription: .nousPortal,
            capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 100)),
            freshness: .live,
            windows: [try QuotaWindow(
                kind: .rollingFiveHours,
                label: "5 hours",
                usedPercent: 25
            )],
            source: try QuotaSource(identifier: "test")
        )
        return try ProfileQuotaObservation(
            profile: try HermesProfileID(value: "test"),
            subscription: .nousPortal,
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

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

    @Test("preserves the last snapshot when the provider reports unavailable")
    func preservesSnapshotWhenProviderUnavailable() async throws {
        let unavailable = try ProfileQuotaObservation(
            profile: try HermesProfileID(value: "test"),
            subscription: .chatGPT,
            observedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 200)),
            result: .unavailable(.sourceUnreadable)
        )
        let source = SequenceSource(reads: [
            [try observation(usedPercent: 25)],
            [unavailable]
        ])
        let service = ProfileQuotaRefreshService(source: source, clock: Date.init)

        _ = await service.refresh()
        let state = await service.refresh()

        #expect(state.availability == .live)
        #expect(state.subscriptions.count == 2)
        guard case let .snapshot(snapshot) = state.subscriptions.first(where: {
            $0.subscription == .chatGPT
        })?.result else {
            Issue.record("Expected the last ChatGPT snapshot to remain usable")
            return
        }
        #expect(snapshot.freshness == .stale)
        #expect(snapshot.windows[0].usedPercent == 25)
    }

    @Test("keeps Claude stale while ChatGPT remains live after a provider failure")
    func isolatesClaudeRefreshFailure() async throws {
        let unavailable = try ProfileQuotaObservation(
            profile: try HermesProfileID(value: "test"),
            subscription: .claude,
            observedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 200)),
            result: .unavailable(.authenticationFailed)
        )
        let source = SequenceSource(reads: [
            [try observation(subscription: .claude, usedPercent: 74), try observation(usedPercent: 25)],
            [unavailable, try observation(usedPercent: 10)]
        ])
        let service = ProfileQuotaRefreshService(source: source, clock: Date.init)
        _ = await service.refresh()
        let state = await service.refresh()
        let claude = try #require(state.subscriptions.first { $0.subscription == .claude })
        let chatGPT = try #require(state.subscriptions.first { $0.subscription == .chatGPT })
        guard case let .snapshot(stale) = claude.result,
              case let .snapshot(live) = chatGPT.result else {
            Issue.record("Expected both retained provider snapshots")
            return
        }
        #expect(state.availability == .live)
        #expect(stale.freshness == .stale)
        #expect(stale.windows[0].usedPercent == 74)
        #expect(live.freshness == .live)
        #expect(live.windows[0].usedPercent == 10)
    }

    @Test("propagates quota and manual reset state from one usage read")
    func propagatesCombinedUsageRead() async throws {
        let manualSnapshot = try ManualResetSnapshot(
            availableCount: 1,
            applicableAvailableCount: 0,
            credits: [try ManualResetCredit(
                identifier: "credit-1",
                title: "Full reset",
                status: .available,
                isSupportedByPlan: true,
                expiresAt: Date(timeIntervalSince1970: 1_000)
            )],
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let service = ProfileQuotaRefreshService(
            source: SequenceSource(
                reads: [[try observation()]],
                manualResetResults: [.snapshot(manualSnapshot)]
            ),
            clock: { Date(timeIntervalSince1970: 100) }
        )

        let state = await service.refresh()

        #expect(state.availability == .live)
        guard case let .live(summary) = state.manualReset else {
            Issue.record("Expected the manual reset result from the same source read")
            return
        }
        #expect(summary.availableCount == 1)
        #expect(summary.applicableAvailableCount == 0)
        #expect(summary.expiration == .dated(QuotaTimestamp(date: Date(timeIntervalSince1970: 1_000))))
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

    private actor SequenceSource: ProfileUsageSource {
        var reads: [[ProfileQuotaObservation]]
        var manualResetResults: [ManualResetReadResult]

        init(
            reads: [[ProfileQuotaObservation]],
            manualResetResults: [ManualResetReadResult] = []
        ) {
            self.reads = reads
            self.manualResetResults = manualResetResults
        }

        func readUsage() async -> ProfileUsageRead {
            let observations: [ProfileQuotaObservation]
            if reads.isEmpty {
                observations = []
            } else {
                observations = reads.removeFirst()
            }
            return ProfileUsageRead(
                quotaObservations: observations,
                manualReset: manualResetResults.isEmpty
                    ? .unavailable(.sourceMissing)
                    : manualResetResults.removeFirst()
            )
        }
    }
}

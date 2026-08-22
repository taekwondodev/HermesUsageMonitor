import Foundation
import Testing
@testable import HermesUsageCore

struct ManualResetRedemptionServiceTests {
    private func liveState(
        available: Int = 1,
        applicable: Int = 1,
        actionable: Bool = true
    ) throws -> ManualResetRefreshState {
        ManualResetRefreshState.live(try ManualResetSummary(
            availableCount: available,
            applicableAvailableCount: applicable,
            expiration: .dated(QuotaTimestamp(date: Date(timeIntervalSince1970: 2_000))),
            isApplicable: applicable > 0,
            hasActionableCredit: actionable
        ))
    }

    private func quota(windowPercent: Double) throws -> [SubscriptionQuota] {
        [try SubscriptionQuota(
            subscription: .chatGPT,
            result: .snapshot(try QuotaSnapshot(
                subscription: .chatGPT,
                capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 100)),
                freshness: .live,
                windows: [try QuotaWindow(kind: .rollingFiveHours, label: "Session", usedPercent: windowPercent)],
                source: try QuotaSource(identifier: "test")
            ))
        )]
    }

    @Test("enables Riscatta only when a ChatGPT window is fully used")
    func guardsWindowExhaustion() async throws {
        let service = ManualResetRedemptionService(redeemer: StubRedeemer(.confirmed))
        let live = try liveState()
        let exhausted = try quota(windowPercent: 100)
        let notExhausted = try quota(windowPercent: 40)
        let canStartExhausted = await service.canStart(manualReset: live, subscriptions: exhausted)
        let canStartNotExhausted = await service.canStart(manualReset: live, subscriptions: notExhausted)
        #expect(canStartExhausted)
        #expect(!canStartNotExhausted)
    }

    @Test("disables Riscatta for stale, unavailable, or non-actionable state")
    func guardsState() async throws {
        let service = ManualResetRedemptionService(redeemer: StubRedeemer(.confirmed))
        let exhausted = try quota(windowPercent: 100)
        let summary = try ManualResetSummary(
            availableCount: 1,
            applicableAvailableCount: 1,
            expiration: .dated(QuotaTimestamp(date: Date(timeIntervalSince1970: 2_000))),
            isApplicable: true,
            hasActionableCredit: true
        )
        let unavailable = await service.canStart(manualReset: .unavailable, subscriptions: exhausted)
        let stale = await service.canStart(manualReset: .stale(summary), subscriptions: exhausted)
        let notActionable = await service.canStart(manualReset: try liveState(actionable: false), subscriptions: exhausted)
        #expect(!unavailable)
        #expect(!stale)
        #expect(!notActionable)
    }

    @Test("one confirmed action sends only a fresh idempotency key and no credit identifier")
    func sendsRequestIDOnly() async throws {
        let registry = RequestIDRegistry()
        let service = ManualResetRedemptionService(redeemer: RecordingRedeemer(registry, result: .confirmed))
        _ = await service.confirmRedemption(
            manualReset: try liveState(),
            subscriptions: try quota(windowPercent: 100)
        )
        let ids = registry.requestIDs()
        #expect(ids.count == 1)
        #expect(ids[0] != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test("reports one less than the available count as expected remaining")
    func reportsExpectedRemaining() async throws {
        let service = ManualResetRedemptionService(redeemer: StubRedeemer(.confirmed))
        let result = await service.confirmRedemption(
            manualReset: try liveState(available: 2, applicable: 1),
            subscriptions: try quota(windowPercent: 100)
        )
        #expect(result == .confirmed(remainingCount: 1))
    }

    @Test("rejected outcome is a definite rejection surfaced for a dialog")
    func rejectedIsDefinite() async throws {
        let service = ManualResetRedemptionService(redeemer: StubRedeemer(.rejected))
        let result = await service.confirmRedemption(
            manualReset: try liveState(),
            subscriptions: try quota(windowPercent: 100)
        )
        #expect(result == .rejected)
    }

    @Test("already_redeemed is an idempotent success")
    func idempotentAlreadyRedeemed() async throws {
        let service = ManualResetRedemptionService(redeemer: StubRedeemer(.alreadyRedeemed))
        let result = await service.confirmRedemption(
            manualReset: try liveState(available: 2, applicable: 1),
            subscriptions: try quota(windowPercent: 100)
        )
        #expect(result == .alreadyRedeemed(remainingCount: 1))
    }

    @Test("nothing_to_reset and no_credit are non-consuming")
    func notConsumedOutcomes() async throws {
        for read in [ManualResetRedemptionReadResult.nothingToReset, .noCredit] {
            let service = ManualResetRedemptionService(redeemer: StubRedeemer(read))
            let result = await service.confirmRedemption(
                manualReset: try liveState(),
                subscriptions: try quota(windowPercent: 100)
            )
            #expect(result == .notConsumed)
        }
    }

    @Test("an unverified outcome blocks redemption until a coherent refresh")
    func blocksUntilCoherentRefresh() async throws {
        let service = ManualResetRedemptionService(redeemer: StubRedeemer(.unverified))
        _ = await service.confirmRedemption(
            manualReset: try liveState(),
            subscriptions: try quota(windowPercent: 100)
        )
        let blocked = await service.canStart(manualReset: try liveState(), subscriptions: try quota(windowPercent: 100))
        #expect(!blocked)

        await service.clearVerificationAfterRefresh(manualReset: try liveState())
        let cleared = await service.canStart(manualReset: try liveState(), subscriptions: try quota(windowPercent: 100))
        #expect(cleared)
    }

    @Test("an unresolved retry reuses the same idempotency key")
    func reusesKeyOnRetry() async throws {
        let registry = RequestIDRegistry()
        let service = ManualResetRedemptionService(redeemer: RecordingRedeemer(registry, result: .unverified))
        _ = await service.confirmRedemption(
            manualReset: try liveState(),
            subscriptions: try quota(windowPercent: 100)
        )
        _ = await service.retryRedemption()
        let ids = registry.requestIDs()
        #expect(ids.count == 2)
        #expect(ids[0] == ids[1])
    }
}

private struct StubRedeemer: ManualResetRedeemer {
    let result: ManualResetRedemptionReadResult
    init(_ result: ManualResetRedemptionReadResult) { self.result = result }
    func redeem(requestID: UUID) async -> ManualResetRedemptionReadResult { result }
}

private final class RequestIDRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID] = []
    func append(_ id: UUID) { lock.lock(); ids.append(id); lock.unlock() }
    func requestIDs() -> [UUID] { lock.lock(); defer { lock.unlock() }; return ids }
}

private struct RecordingRedeemer: ManualResetRedeemer {
    let registry: RequestIDRegistry
    let result: ManualResetRedemptionReadResult
    init(_ registry: RequestIDRegistry, result: ManualResetRedemptionReadResult) {
        self.registry = registry
        self.result = result
    }
    func redeem(requestID: UUID) async -> ManualResetRedemptionReadResult {
        registry.append(requestID)
        return result
    }
}
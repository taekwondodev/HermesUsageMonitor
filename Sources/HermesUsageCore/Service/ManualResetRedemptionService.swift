import Foundation

/// Determines when a redemption is permitted. The app exposes no force path,
/// so the provider's no-force exhaustion guard is replicated here: a ChatGPT/Codex
/// quota window must be fully used before `Riscatta` is actionable.
enum ManualResetRedemptionGuard {
    static func isWindowExhausted(
        in subscriptions: [SubscriptionQuota],
        subscription: Subscription = .chatGPT
    ) -> Bool {
        subscriptions
            .first { $0.subscription == subscription }
            .flatMap { quota -> [QuotaWindow]? in
                guard case let .snapshot(snapshot) = quota.result else { return nil }
                return snapshot.windows
            }
            .map { windows in
                windows.contains { $0.usedPercent >= 100 }
            } ?? false
    }
}

public protocol ManualResetRedemptionObserver: Sendable {
    func record(_ state: ManualResetRedemptionState)
}

public struct NoopManualResetRedemptionObserver: ManualResetRedemptionObserver {
    public init() {}
    public func record(_ state: ManualResetRedemptionState) {}
}

public enum ManualResetRedemptionState: Equatable, Sendable {
    case idle
    case redeeming
    case verificationRequired
    case success
    case rejected
    case notConsumed
}

public actor ManualResetRedemptionService {
    private let redeemer: any ManualResetRedeemer
    private let observer: any ManualResetRedemptionObserver
    private var inFlightAttempt: ManualResetRedemptionAttempt?
    private var verificationBlocked = false
    private var lastOutcome: ManualResetRedemptionOutcome?

    public init(
        redeemer: any ManualResetRedeemer,
        observer: any ManualResetRedemptionObserver = NoopManualResetRedemptionObserver()
    ) {
        self.redeemer = redeemer
        self.observer = observer
    }

    /// The button enablement guard.
    public func canStart(
        manualReset: ManualResetRefreshState,
        subscriptions: [SubscriptionQuota]
    ) -> Bool {
        guard case let .live(summary) = manualReset,
              summary.hasActionableCredit,
              summary.isApplicable,
              !verificationBlocked else {
            return false
        }
        return ManualResetRedemptionGuard.isWindowExhausted(in: subscriptions)
    }

    /// Called after a user confirms redemption. Generates a fresh idempotency key
    /// and consumes one credit. Refuses when the guard no longer holds or a
    /// verification block is active.
    public func confirmRedemption(
        manualReset: ManualResetRefreshState,
        subscriptions: [SubscriptionQuota]
    ) async -> ManualResetRedemptionResult {
        guard let summary = liveSummary(manualReset),
              summary.hasActionableCredit,
              summary.isApplicable,
              !verificationBlocked,
              ManualResetRedemptionGuard.isWindowExhausted(in: subscriptions) else {
            return .rejected
        }
        let attempt = ManualResetRedemptionAttempt(
            idempotencyKey: UUID(),
            expectedRemainingCount: max(0, summary.availableCount - 1)
        )
        inFlightAttempt = attempt
        return await perform(attempt)
    }

    /// Reuses the unresolved in-flight attempt's idempotency key. Only valid while
    /// a verification block is active; a retry after a coherent refresh starts fresh.
    public func retryRedemption() async -> ManualResetRedemptionResult {
        guard verificationBlocked, let attempt = inFlightAttempt else {
            return .rejected
        }
        return await perform(attempt)
    }

    public func clearVerificationAfterRefresh(manualReset: ManualResetRefreshState) {
        if case .live = manualReset {
            verificationBlocked = false
            inFlightAttempt = nil
        }
    }

    var isVerificationBlocked: Bool { verificationBlocked }

    var outcome: ManualResetRedemptionOutcome? { lastOutcome }

    func clearLastOutcome() {
        lastOutcome = nil
    }

    private func liveSummary(_ manualReset: ManualResetRefreshState) -> ManualResetSummary? {
        guard case let .live(summary) = manualReset else { return nil }
        return summary
    }

    private func perform(_ attempt: ManualResetRedemptionAttempt) async -> ManualResetRedemptionResult {
        observer.record(.redeeming)
        let read = await redeemer.redeem(requestID: attempt.idempotencyKey)
        let result: ManualResetRedemptionResult
        switch read {
        case .confirmed:
            result = .confirmed(remainingCount: attempt.expectedRemainingCount)
            verificationBlocked = false
            inFlightAttempt = nil
            storeOutcome(.success)
            observer.record(.success)
        case .alreadyRedeemed:
            result = .alreadyRedeemed(remainingCount: attempt.expectedRemainingCount)
            verificationBlocked = false
            inFlightAttempt = nil
            storeOutcome(.success)
            observer.record(.success)
        case .nothingToReset, .noCredit:
            result = .notConsumed
            inFlightAttempt = nil
            storeOutcome(.notConsumed)
            observer.record(.notConsumed)
        case .rejected:
            result = .rejected
            inFlightAttempt = nil
            storeOutcome(.rejected)
            observer.record(.rejected)
        case .unverified:
            result = .unverified
            verificationBlocked = true
            storeOutcome(.verificationRequired)
            observer.record(.verificationRequired)
        }
        return result
    }

    private func storeOutcome(_ outcome: ManualResetRedemptionOutcome) {
        lastOutcome = outcome
    }
}

enum ManualResetRedemptionOutcome: Equatable {
    case success
    case verificationRequired
    case rejected
    case notConsumed
}
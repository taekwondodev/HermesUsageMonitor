import Foundation

/// Outcome of a redemption read through the `ManualResetRedeemer` port.
public enum ManualResetRedemptionReadResult: Equatable, Sendable {
    case confirmed
    case alreadyRedeemed
    case nothingToReset
    case noCredit
    case rejected
    case unverified
}

/// Provider-agnostic result surfaced to the Handler.
public enum ManualResetRedemptionResult: Equatable, Sendable {
    case confirmed(remainingCount: Int)
    case alreadyRedeemed(remainingCount: Int)
    case notConsumed
    case rejected
    case unverified
}

/// Consumes one banked ChatGPT/Codex reset credit through the provider.
public protocol ManualResetRedeemer: Sendable {
    func redeem(requestID: UUID) async -> ManualResetRedemptionReadResult
}

public enum ManualResetRedeemerFactory {
    public static func make(hermesHome: URL) -> any ManualResetRedeemer {
        HermesUsageCommandReader(hermesHome: hermesHome)
    }
}

/// A confirmed redemption attempt. One user confirmation owns one idempotency
/// key; any retry of the same unresolved attempt reuses it.
struct ManualResetRedemptionAttempt: Equatable, Sendable {
    let idempotencyKey: UUID
    let expectedRemainingCount: Int
}
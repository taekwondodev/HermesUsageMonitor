import Foundation

struct HermesProfileID: Equatable, Hashable, Sendable {
    let value: String

    init(value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuotaDomainError.invalidProfile
        }
        self.value = value
    }
}

struct ProfileQuotaObservation: Equatable, Sendable {
    let profile: HermesProfileID
    let subscription: Subscription
    let observedAt: QuotaTimestamp
    let result: QuotaReadResult

    init(
        profile: HermesProfileID,
        subscription: Subscription,
        observedAt: QuotaTimestamp,
        result: QuotaReadResult
    ) throws {
        if case let .snapshot(snapshot) = result, snapshot.subscription != subscription {
            throw QuotaDomainError.invalidSnapshot
        }
        self.profile = profile
        self.subscription = subscription
        self.observedAt = observedAt
        self.result = result
    }
}

struct ProfileUsageRead: Equatable, Sendable {
    let quotaObservations: [ProfileQuotaObservation]
    let manualReset: ManualResetReadResult
}

public struct SubscriptionQuota: Equatable, Identifiable, Sendable {
    public let subscription: Subscription
    public let result: QuotaReadResult

    public var id: String { subscription.rawValue }

    public init(subscription: Subscription, result: QuotaReadResult) {
        self.subscription = subscription
        self.result = result
    }
}

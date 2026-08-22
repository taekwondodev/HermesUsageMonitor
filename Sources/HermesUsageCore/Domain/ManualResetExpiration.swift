import Foundation

/// Stable provider + local-date group key. Persisted only in this minimal form;
/// never carries credentials, account ids, credit ids, payloads, or usage history.
public struct ManualResetExpirationGroupKey: Equatable, Hashable, Sendable {
    public let provider: String
    public let localDate: String

    public init(provider: String, localDate: String) {
        self.provider = provider
        self.localDate = localDate
    }

    public var rawValue: String { "\(provider)#\(localDate)" }
}

/// One immediate notification covering every known credit expiring on one local date.
public struct ManualResetExpirationNotification: Equatable, Sendable {
    public let provider: String
    public let localDate: String
    public let creditCount: Int
    public let earliestExpiration: Date?

    public init(
        provider: String,
        localDate: String,
        creditCount: Int,
        earliestExpiration: Date?
    ) {
        self.provider = provider
        self.localDate = localDate
        self.creditCount = creditCount
        self.earliestExpiration = earliestExpiration
    }
}

/// Delivers an immediate expiration warning. No future-trigger scheduling.
public protocol ManualResetExpirationNotifier: Sendable {
    func deliver(_ notification: ManualResetExpirationNotification) async -> Bool
}

/// Persists which group keys have already been notified, so a local date stays
/// silent after restart and when a late-discovered credit is added.
public protocol ManualResetExpirationHistory: Sendable {
    func contains(_ key: ManualResetExpirationGroupKey) async -> Bool
    func record(_ key: ManualResetExpirationGroupKey) async
}

/// Non-sensitive observability categories for the expiration notifier.
public enum ManualResetExpirationObservation: Equatable, Sendable {
    case eligible(localDate: String, creditCount: Int)
    case alreadyNotified(localDate: String)
    case deliverySucceeded(localDate: String)
    case deliveryFailed(localDate: String)
    case skippedNonLive
}

public protocol ManualResetExpirationObserver: Sendable {
    func record(_ state: ManualResetExpirationObservation)
}

public struct NoopManualResetExpirationObserver: ManualResetExpirationObserver {
    public init() {}
    public func record(_ state: ManualResetExpirationObservation) {}
}
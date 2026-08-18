import Foundation

public enum QuotaDomainError: Error, Equatable, Sendable {
    case invalidPercentage
    case invalidProfile
    case invalidSnapshot
    case unsupportedVersion
}

public enum QuotaFreshness: String, Codable, Sendable {
    case live
    case persisted
    case stale
}

public struct QuotaSnapshot: Equatable, Sendable {
    public let subscription: Subscription
    public let capturedAt: QuotaTimestamp
    public let freshness: QuotaFreshness
    public let windows: [QuotaWindow]
    public let source: QuotaSource

    public init(
        subscription: Subscription,
        capturedAt: QuotaTimestamp,
        freshness: QuotaFreshness = .persisted,
        windows: [QuotaWindow],
        source: QuotaSource
    ) throws {
        guard !windows.isEmpty else {
            throw QuotaDomainError.invalidSnapshot
        }

        self.subscription = subscription
        self.capturedAt = capturedAt
        self.freshness = freshness
        self.windows = windows
        self.source = source
    }

    public func withFreshness(_ freshness: QuotaFreshness) -> QuotaSnapshot {
        QuotaSnapshot(copying: self, freshness: freshness)
    }

    private init(copying snapshot: QuotaSnapshot, freshness: QuotaFreshness) {
        subscription = snapshot.subscription
        capturedAt = snapshot.capturedAt
        self.freshness = freshness
        windows = snapshot.windows
        source = snapshot.source
    }
}

public enum QuotaUnavailableReason: Equatable, Sendable {
    case sourceMissing
    case sourceUnreadable
    case malformedSnapshot
    case unsupportedVersion
    case commandMissing
    case authenticationFailed
    case endpointUnavailable
}

public enum QuotaReadResult: Equatable, Sendable {
    case snapshot(QuotaSnapshot)
    case unavailable(QuotaUnavailableReason)
}

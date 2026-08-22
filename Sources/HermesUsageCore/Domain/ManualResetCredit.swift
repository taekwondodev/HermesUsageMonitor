import Foundation

enum ManualResetDomainError: Error, Equatable, Sendable {
    case invalidCount
    case invalidIdentifier
    case invalidStatus
    case invalidSummary
    case invalidTitle
}

enum ManualResetCreditStatus: String, Equatable, Sendable {
    case available
    case redeemed
    case expired
}

struct ManualResetCreditID: Equatable, Hashable, Sendable {
    let rawValue: String

    init(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw ManualResetDomainError.invalidIdentifier
        }
        rawValue = value
    }
}

struct ManualResetCredit: Equatable, Sendable {
    let identifier: ManualResetCreditID
    let title: String
    let status: ManualResetCreditStatus
    let isSupportedByPlan: Bool
    let grantedAt: Date?
    let expiresAt: Date?

    init(
        identifier: String,
        title: String,
        status: ManualResetCreditStatus,
        isSupportedByPlan: Bool,
        grantedAt: Date? = nil,
        expiresAt: Date? = nil
    ) throws {
        let identifier = try ManualResetCreditID(identifier)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ManualResetDomainError.invalidTitle
        }
        self.identifier = identifier
        self.title = title
        self.status = status
        self.isSupportedByPlan = isSupportedByPlan
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }
}

struct ManualResetSnapshot: Equatable, Sendable {
    let availableCount: Int
    let applicableAvailableCount: Int
    let credits: [ManualResetCredit]
    let capturedAt: Date

    init(
        availableCount: Int,
        applicableAvailableCount: Int,
        credits: [ManualResetCredit],
        capturedAt: Date
    ) throws {
        guard availableCount >= 0,
              applicableAvailableCount >= 0,
              applicableAvailableCount <= availableCount else {
            throw ManualResetDomainError.invalidCount
        }
        self.availableCount = availableCount
        self.applicableAvailableCount = applicableAvailableCount
        self.credits = credits
        self.capturedAt = capturedAt
    }
}

enum ManualResetUnavailableReason: Equatable, Sendable {
    case sourceMissing
    case sourceUnavailable
    case malformedData
}

enum ManualResetReadResult: Equatable, Sendable {
    case snapshot(ManualResetSnapshot)
    case unavailable(ManualResetUnavailableReason)
}

public enum ManualResetExpiration: Equatable, Sendable {
    case dated(QuotaTimestamp)
    case doesNotExpire
    case unavailable
}

public struct ManualResetSummary: Equatable, Sendable {
    public let availableCount: Int
    public let applicableAvailableCount: Int
    public let expiration: ManualResetExpiration
    public let isApplicable: Bool
    public let hasActionableCredit: Bool

    public init(
        availableCount: Int,
        applicableAvailableCount: Int,
        expiration: ManualResetExpiration,
        isApplicable: Bool,
        hasActionableCredit: Bool
    ) throws {
        guard availableCount >= 0,
              applicableAvailableCount >= 0,
              applicableAvailableCount <= availableCount,
              isApplicable == (applicableAvailableCount > 0),
              !hasActionableCredit || isApplicable else {
            throw ManualResetDomainError.invalidSummary
        }
        if availableCount == 0,
           expiration != .unavailable || isApplicable || hasActionableCredit {
            throw ManualResetDomainError.invalidSummary
        }
        self.availableCount = availableCount
        self.applicableAvailableCount = applicableAvailableCount
        self.expiration = expiration
        self.isApplicable = isApplicable
        self.hasActionableCredit = hasActionableCredit
    }
}

public enum ManualResetRefreshState: Equatable, Sendable {
    case live(ManualResetSummary)
    case stale(ManualResetSummary)
    case unavailable

    public var canRedeem: Bool {
        guard case let .live(summary) = self else { return false }
        return summary.hasActionableCredit
    }
}

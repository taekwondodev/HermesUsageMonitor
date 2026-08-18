import Foundation

public enum QuotaWindowKind: String, Codable, Sendable {
    case rollingFiveHours = "rolling-5h"
    case daily
    case weekly
    case monthly
}

public struct QuotaWindow: Equatable, Sendable {
    public let kind: QuotaWindowKind
    public let label: String
    public let usedPercent: Double
    public let resetAt: QuotaReset?

    public init(
        kind: QuotaWindowKind,
        label: String,
        usedPercent: Double,
        resetAt: QuotaReset? = nil
    ) throws {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuotaDomainError.invalidSnapshot
        }

        guard usedPercent.isFinite, (0...100).contains(usedPercent) else {
            throw QuotaDomainError.invalidPercentage
        }

        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.resetAt = resetAt
    }
}

import Foundation

public struct QuotaWindowOpaqueKind: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasControlCharacter = rawValue.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
        }
        guard !trimmed.isEmpty, rawValue.count <= 200, !hasControlCharacter else {
            throw QuotaDomainError.invalidSnapshot
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let rawValue = try String(from: decoder)
        do {
            self = try Self(rawValue)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid opaque quota window kind"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}

public enum QuotaWindowKind: Hashable, Codable, Sendable {
    case rollingFiveHours
    case daily
    case weekly
    case monthly
    case opaque(QuotaWindowOpaqueKind)

    public static func unknown(_ rawValue: String) throws -> Self {
        .opaque(try QuotaWindowOpaqueKind(rawValue))
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "rolling-5h": self = .rollingFiveHours
        case "daily": self = .daily
        case "weekly": self = .weekly
        case "monthly": self = .monthly
        default:
            guard let opaque = try? QuotaWindowOpaqueKind(rawValue) else { return nil }
            self = .opaque(opaque)
        }
    }

    public var rawValue: String {
        switch self {
        case .rollingFiveHours: return "rolling-5h"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case let .opaque(value): return value.rawValue
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try String(from: decoder)
        guard let kind = QuotaWindowKind(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Quota window kind must not be empty"
            )
        }
        self = kind
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }
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

import Foundation

public struct QuotaSource: Equatable, Sendable {
    public let identifier: String

    public init(identifier: String) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuotaDomainError.invalidSnapshot
        }
        self.identifier = identifier
    }
}

public struct QuotaTimestamp: Equatable, Sendable {
    public let date: Date

    public init(date: Date) {
        self.date = date
    }
}

public struct QuotaReset: Equatable, Sendable {
    public let at: QuotaTimestamp

    public init(date: Date) {
        at = QuotaTimestamp(date: date)
    }
}

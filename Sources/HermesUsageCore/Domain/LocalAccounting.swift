import Foundation

public struct AccountingTokens: Equatable, Sendable {
    public let input: Int?
    public let output: Int?

    public init(input: Int? = nil, output: Int? = nil) {
        self.input = input
        self.output = output
    }

    public var total: Int? {
        guard let input, let output else { return nil }
        return input + output
    }
}

public struct AccountingCost: Equatable, Sendable {
    public let amount: Decimal
    public let currency: String

    public init(amount: Decimal, currency: String) throws {
        guard !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuotaDomainError.invalidSnapshot
        }
        self.amount = amount
        self.currency = currency
    }
}

public struct LocalAccounting: Equatable, Sendable {
    public let subscription: Subscription
    public let profile: String?
    public let tokens: AccountingTokens?
    public let requests: Int?
    public let models: [String]
    public let cost: AccountingCost?
    public let provider: String?

    public init(
        subscription: Subscription,
        profile: String? = nil,
        tokens: AccountingTokens? = nil,
        requests: Int? = nil,
        models: [String] = [],
        cost: AccountingCost? = nil,
        provider: String? = nil
    ) throws {
        guard requests == nil || requests! >= 0 else { throw QuotaDomainError.invalidSnapshot }
        self.subscription = subscription
        self.profile = profile
        self.tokens = tokens
        self.requests = requests
        self.models = models
        self.cost = cost
        self.provider = provider
    }
}

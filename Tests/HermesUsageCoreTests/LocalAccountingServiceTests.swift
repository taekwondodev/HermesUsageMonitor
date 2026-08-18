import Foundation
import Testing
@testable import HermesUsageCore

struct LocalAccountingServiceTests {
    @Test("groups profiles by commercial subscription and preserves partial fields")
    func groupsPartialAccounting() throws {
        let first = try LocalAccounting(
            subscription: .chatGPT,
            profile: "work",
            tokens: try AccountingTokens(input: 100, output: 25),
            requests: 2,
            models: ["gpt-5"],
            provider: "openai"
        )
        let second = try LocalAccounting(
            subscription: .chatGPT,
            profile: "personal",
            requests: 1,
            models: ["gpt-5-mini"],
            cost: try AccountingCost(amount: 0.12, currency: "USD"),
            provider: "openai"
        )
        let other = try LocalAccounting(subscription: .nousPortal, requests: 4)
        let result = LocalAccountingService(source: StubSource([first, second, other]))
            .readGroupedBySubscription()
        guard case let .available(grouped) = result else {
            Issue.record("Expected available accounting")
            return
        }

        #expect(grouped[.chatGPT]?.count == 2)
        #expect(grouped[.chatGPT]?.contains { $0.cost != nil } == true)
        #expect(grouped[.chatGPT]?.contains { $0.tokens != nil } == true)
        #expect(grouped[.nousPortal]?.count == 1)
        #expect(grouped[.opencodeGo] == nil)
    }

    @Test("rejects negative accounting metrics")
    func rejectsNegativeMetrics() {
        #expect(throws: AccountingDomainError.invalidTokenCount) {
            _ = try AccountingTokens(input: -1)
        }
        #expect(throws: AccountingDomainError.invalidRequestCount) {
            _ = try LocalAccounting(subscription: .chatGPT, requests: -1)
        }
        #expect(throws: AccountingDomainError.invalidCost) {
            _ = try AccountingCost(amount: -0.01, currency: "USD")
        }
    }

    private struct StubSource: LocalAccountingSource {
        let values: [LocalAccounting]
        init(_ values: [LocalAccounting]) { self.values = values }
        func read() throws -> [LocalAccounting] { values }
    }
}

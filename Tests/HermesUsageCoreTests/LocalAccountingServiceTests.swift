import Foundation
import Testing
@testable import HermesUsageCore

struct LocalAccountingServiceTests {
    @Test("groups profiles by commercial subscription and preserves partial fields")
    func groupsPartialAccounting() throws {
        let first = try LocalAccounting(
            subscription: .chatGPT,
            profile: "work",
            tokens: AccountingTokens(input: 100, output: 25),
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
        let grouped = LocalAccountingService(source: StubSource([first, second, other]))
            .readGroupedBySubscription()

        #expect(grouped[.chatGPT]?.count == 2)
        #expect(grouped[.chatGPT]?.contains { $0.cost != nil } == true)
        #expect(grouped[.chatGPT]?.contains { $0.tokens != nil } == true)
        #expect(grouped[.nousPortal]?.count == 1)
        #expect(grouped[.opencodeGo] == nil)
    }

    private struct StubSource: LocalAccountingSource {
        let values: [LocalAccounting]
        init(_ values: [LocalAccounting]) { self.values = values }
        func read() -> [LocalAccounting] { values }
    }
}

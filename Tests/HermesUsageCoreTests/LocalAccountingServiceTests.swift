import Foundation
import Testing
@testable import HermesUsageCore

struct LocalAccountingServiceTests {
    @Test("groups profiles by commercial subscription and preserves partial fields")
    func groupsPartialAccounting() async throws {
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
        let service = LocalAccountingService(source: StubSource([first, second]))
        let groupedResult = await service.readGroupedBySubscription()
        guard case let .available(grouped) = groupedResult else {
            Issue.record("Expected available accounting")
            return
        }

        #expect(grouped[.chatGPT]?.count == 2)
        #expect(grouped[.chatGPT]?.contains { $0.cost != nil } == true)
        #expect(grouped[.chatGPT]?.contains { $0.tokens != nil } == true)
        #expect(grouped[.opencodeGo] == nil)
    }

    @Test("passes a thirty day window from its refresh clock to the source")
    func passesAccountingWindowToSource() async throws {
        let expectedWindow = AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000))
        let value = try LocalAccounting(subscription: .chatGPT, requests: 1)
        let service = LocalAccountingService(
            source: WindowAwareSource(expected: expectedWindow, values: [value]),
            clock: { Date(timeIntervalSince1970: 2_000) }
        )
        let result = await service.readGroupedBySubscription()

        guard case let .available(grouped) = result else {
            Issue.record("Expected available accounting")
            return
        }
        #expect(grouped[.chatGPT]?.count == 1)
    }

    @MainActor
    @Test("accounting acquisition keeps the main actor responsive")
    func accountingAcquisitionKeepsMainActorResponsive() async throws {
        let value = try LocalAccounting(subscription: .chatGPT, requests: 1)
        let source = BlockingSource([value])
        let service = LocalAccountingService(source: source)

        let read = Task { await service.readGroupedBySubscription() }
        await source.waitUntilStarted()

        let mainActorOperation = Task { @MainActor in true }
        #expect(await mainActorOperation.value)
        #expect(source.isReading)
        source.release()

        guard case let .available(grouped) = await read.value else {
            Issue.record("Expected available accounting")
            return
        }
        #expect(grouped[.chatGPT]?.count == 1)
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

    private struct WindowAwareSource: LocalAccountingSource {
        let expected: AccountingWindow
        let values: [LocalAccounting]

        func read(window: AccountingWindow) throws -> [LocalAccounting] {
            window == expected ? values : []
        }
    }

    private struct StubSource: LocalAccountingSource {
        let values: [LocalAccounting]
        init(_ values: [LocalAccounting]) { self.values = values }
        func read(window: AccountingWindow) throws -> [LocalAccounting] { values }
    }

    private final class BlockingSource: LocalAccountingSource, @unchecked Sendable {
        private let condition = NSCondition()
        private let values: [LocalAccounting]
        private var started = false
        private var released = false
        private var reading = false

        init(_ values: [LocalAccounting]) {
            self.values = values
        }

        var isReading: Bool {
            condition.withLock { reading }
        }

        func read(window: AccountingWindow) throws -> [LocalAccounting] {
            condition.lock()
            started = true
            reading = true
            condition.broadcast()
            let deadline = Date.now.addingTimeInterval(5)
            while !released, condition.wait(until: deadline) {}
            reading = false
            condition.unlock()
            return values
        }

        func waitUntilStarted() async {
            await withCheckedContinuation { continuation in
                Thread.detachNewThread { [self] in
                    condition.lock()
                    while !started {
                        condition.wait()
                    }
                    condition.unlock()
                    continuation.resume()
                }
            }
        }

        func release() {
            condition.withLock {
                released = true
                condition.broadcast()
            }
        }
    }
}

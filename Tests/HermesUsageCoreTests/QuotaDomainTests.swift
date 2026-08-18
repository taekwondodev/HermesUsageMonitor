import Foundation
import Testing
@testable import HermesUsageCore

struct QuotaDomainTests {
    @Test("accepts a finite percentage inside the quota range")
    func acceptsValidWindow() throws {
        let resetAt = Date(timeIntervalSince1970: 1_900_000_000)
        let window = try QuotaWindow(
            kind: .rollingFiveHours,
            label: "5 hours",
            usedPercent: 42.5,
            resetAt: QuotaReset(date: resetAt)
        )

        #expect(window.usedPercent == 42.5)
        #expect(window.resetAt?.at.date == resetAt)
    }

    @Test("rejects percentages outside the quota range")
    func rejectsInvalidWindow() {
        #expect(throws: QuotaDomainError.invalidPercentage) {
            _ = try QuotaWindow(
                kind: .weekly,
                label: "Weekly",
                usedPercent: 100.1
            )
        }
    }

    @Test("service returns a valid result through its source port")
    func serviceUsesSourcePort() throws {
        let window = try QuotaWindow(
            kind: .monthly,
            label: "Monthly",
            usedPercent: 12
        )
        let snapshot = try QuotaSnapshot(
            subscription: .nousPortal,
            capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 1_900_000_000)),
            windows: [window],
            source: try QuotaSource(identifier: "test-source")
        )

        let service = QuotaSnapshotService(
            source: StubSource(result: .snapshot(snapshot))
        )

        #expect(service.read() == .snapshot(snapshot))
    }

    @Test("service preserves an unavailable source result")
    func servicePreservesUnavailableResult() {
        let service = QuotaSnapshotService(
            source: StubSource(result: .unavailable(.sourceMissing))
        )

        #expect(service.read() == .unavailable(.sourceMissing))
    }

    @Test("service preserves a malformed source result")
    func servicePreservesMalformedResult() {
        let service = QuotaSnapshotService(
            source: StubSource(result: .unavailable(.malformedSnapshot))
        )

        #expect(service.read() == .unavailable(.malformedSnapshot))
    }

    @Test("rejects a snapshot without windows or a source")
    func rejectsEmptySnapshot() throws {
        #expect(throws: QuotaDomainError.invalidSnapshot) {
            _ = try QuotaSnapshot(
                subscription: .chatGPT,
                capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 1_900_000_000)),
                windows: [],
                source: try QuotaSource(identifier: "")
            )
        }
    }

    private struct StubSource: QuotaSnapshotSource {
        let result: QuotaReadResult

        func read() -> QuotaReadResult {
            result
        }
    }
}

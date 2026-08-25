import Foundation
import Testing
@testable import HermesUsageCore

struct QuotaDomainTests {
    @Test("OpenCode Go quota windows use the fixed display order")
    func opencodeGoDisplayOrder() throws {
        let windows = try [
            QuotaWindow(kind: .monthly, label: "Monthly", usedPercent: 95, resetAt: QuotaReset(date: Date(timeIntervalSince1970: 3_000))),
            QuotaWindow(kind: .rollingFiveHours, label: "5 hour", usedPercent: 10, resetAt: QuotaReset(date: Date(timeIntervalSince1970: 1_000))),
            QuotaWindow(kind: .weekly, label: "Weekly", usedPercent: 50, resetAt: QuotaReset(date: Date(timeIntervalSince1970: 2_000)))]

        #expect(
            QuotaWindowDisplayOrder.windows(for: .opencodeGo, windows: windows).map(\.kind) == [
                .rollingFiveHours,
                .weekly,
                .monthly
            ]
        )

        let changedValues = try [
            QuotaWindow(kind: .monthly, label: "Monthly", usedPercent: 1, resetAt: QuotaReset(date: Date(timeIntervalSince1970: 1_000))),
            QuotaWindow(kind: .rollingFiveHours, label: "5 hour", usedPercent: 99, resetAt: QuotaReset(date: Date(timeIntervalSince1970: 3_000))),
            QuotaWindow(kind: .weekly, label: "Weekly", usedPercent: 2, resetAt: QuotaReset(date: Date(timeIntervalSince1970: 2_000)))]

        #expect(
            QuotaWindowDisplayOrder.windows(for: .opencodeGo, windows: changedValues).map(\.kind) == [
                .rollingFiveHours,
                .weekly,
                .monthly
            ]
        )
    }

    @Test("OpenCode Go display order omits no reported supported windows")
    func opencodeGoDisplayOrderPreservesPartialSnapshots() throws {
        let windows = try [
            QuotaWindow(kind: .monthly, label: "Monthly", usedPercent: 95),
            QuotaWindow(kind: .rollingFiveHours, label: "5 hour", usedPercent: 5)
        ]

        #expect(
            QuotaWindowDisplayOrder.windows(for: .opencodeGo, windows: windows).map(\.kind) == [
                .rollingFiveHours,
                .monthly
            ]
        )
    }

    @Test("ChatGPT keeps its weekly quota window")
    func chatGPTDisplayOrderRemainsUnchanged() throws {
        let weekly = try QuotaWindow(kind: .weekly, label: "Weekly", usedPercent: 42)

        #expect(
            QuotaWindowDisplayOrder.windows(for: .chatGPT, windows: [weekly]).map(\.kind) == [.weekly]
        )
    }

    @Test("ChatGPT displays known windows before unknown windows in provider order")
    func chatGPTDisplayOrderKeepsUnknownWindows() throws {
        let unknownA = try QuotaWindow(
            kind: try .unknown("rolling-7d"), label: "Longer window", usedPercent: 10
        )
        let unknownB = try QuotaWindow(
            kind: try .unknown("experimental"), label: "Experimental", usedPercent: 80
        )
        let windows = try [
            unknownA,
            QuotaWindow(kind: .weekly, label: "Weekly", usedPercent: 20),
            unknownB,
            QuotaWindow(kind: .rollingFiveHours, label: "5 hours", usedPercent: 30)
        ]

        #expect(
            QuotaWindowDisplayOrder.windows(for: .chatGPT, windows: windows).map(\.kind) == [
                .rollingFiveHours,
                .weekly,
                try .unknown("rolling-7d"),
                try .unknown("experimental")
            ]
        )
    }

    @Test("unknown quota window kinds preserve their wire identity")
    func preservesUnknownKindIdentity() throws {
        let kind = try QuotaWindowKind.unknown("rolling-7d")
        let data = Data("\"rolling-7d\"".utf8)
        let decoded = try JSONDecoder().decode(QuotaWindowKind.self, from: data)

        #expect(decoded == kind)
        #expect(kind.rawValue == "rolling-7d")
        #expect((try JSONEncoder().encode(kind)) == data)
    }

    @Test("rejects invalid opaque quota window identities")
    func rejectsInvalidOpaqueIdentity() {
        #expect(throws: QuotaDomainError.invalidSnapshot) {
            _ = try QuotaWindowOpaqueKind(" \n")
        }
        #expect(throws: QuotaDomainError.invalidSnapshot) {
            _ = try QuotaWindowOpaqueKind(String(repeating: "x", count: 201))
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                QuotaWindowOpaqueKind.self,
                from: Data("\"\\n\"".utf8)
            )
        }
    }

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
            subscription: .chatGPT,
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

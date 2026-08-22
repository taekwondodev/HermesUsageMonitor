import Foundation
import Testing
@testable import HermesUsageCore

struct ManualResetRefreshServiceTests {
    @Test("keeps ownership separate from provider applicability")
    func separatesAvailabilityFromApplicability() async throws {
        let service = ManualResetRefreshService(clock: {
            Date(timeIntervalSince1970: 100)
        })
        let state = await service.refresh(.snapshot(try snapshot(
            availableCount: 1,
            applicableCount: 0,
            expirations: [1_000]
        )))

        let summary = try #require(state.liveSummary)
        #expect(summary.availableCount == 1)
        #expect(summary.applicableAvailableCount == 0)
        #expect(!summary.isApplicable)
        #expect(summary.hasActionableCredit == false)
        #expect(summary.expiration == .dated(QuotaTimestamp(date: Date(timeIntervalSince1970: 1_000))))
    }

    @Test("selects the nearest expiration from out-of-order details")
    func selectsNearestExpiration() async throws {
        let service = ManualResetRefreshService(clock: {
            Date(timeIntervalSince1970: 100)
        })
        let state = await service.refresh(.snapshot(try snapshot(
            availableCount: 2,
            applicableCount: 1,
            expirations: [2_000, 1_000]
        )))

        let summary = try #require(state.liveSummary)
        #expect(summary.expiration == .dated(QuotaTimestamp(date: Date(timeIntervalSince1970: 1_000))))
        #expect(summary.isApplicable)
        #expect(summary.hasActionableCredit)
    }

    @Test("places a non-expiring credit after dated credits")
    func selectsDatedBeforeNonExpiring() async throws {
        let service = ManualResetRefreshService(clock: {
            Date(timeIntervalSince1970: 100)
        })
        let state = await service.refresh(.snapshot(try snapshot(
            availableCount: 2,
            applicableCount: 1,
            expirations: [nil, 1_000]
        )))

        #expect(try #require(state.liveSummary).expiration == .dated(
            QuotaTimestamp(date: Date(timeIntervalSince1970: 1_000))
        ))
    }

    @Test("reports non-expiring when every complete detail lacks expiration")
    func reportsNonExpiring() async throws {
        let service = ManualResetRefreshService(clock: {
            Date(timeIntervalSince1970: 100)
        })
        let state = await service.refresh(.snapshot(try snapshot(
            availableCount: 1,
            applicableCount: 1,
            expirations: [nil]
        )))

        #expect(try #require(state.liveSummary).expiration == .doesNotExpire)
    }

    @Test("keeps a positive count but disables action when details are incomplete")
    func disablesIncompleteDetails() async throws {
        let service = ManualResetRefreshService(clock: {
            Date(timeIntervalSince1970: 100)
        })
        let state = await service.refresh(.snapshot(try snapshot(
            availableCount: 2,
            applicableCount: 1,
            expirations: [1_000]
        )))

        let summary = try #require(state.liveSummary)
        #expect(summary.availableCount == 2)
        #expect(summary.expiration == .unavailable)
        #expect(!summary.hasActionableCredit)
    }

    @Test("treats zero as a live state rather than unavailable")
    func keepsZeroLive() async throws {
        let service = ManualResetRefreshService(clock: Date.init)
        let state = await service.refresh(.snapshot(try snapshot(
            availableCount: 0,
            applicableCount: 0,
            expirations: []
        )))

        let summary = try #require(state.liveSummary)
        #expect(summary.availableCount == 0)
        #expect(summary.expiration == .unavailable)
        #expect(!summary.hasActionableCredit)
    }

    @Test("keeps the last valid summary stale after a read failure")
    func keepsLastSummaryStale() async throws {
        let service = ManualResetRefreshService(clock: {
            Date(timeIntervalSince1970: 100)
        })
        _ = await service.refresh(.snapshot(try snapshot(
            availableCount: 1,
            applicableCount: 1,
            expirations: [1_000]
        )))

        let stale = await service.refresh(.unavailable(.sourceUnavailable))

        let summary = try #require(stale.staleSummary)
        #expect(summary.availableCount == 1)
        #expect(summary.expiration == .dated(QuotaTimestamp(date: Date(timeIntervalSince1970: 1_000))))
        #expect(!stale.canRedeem)
    }

    @Test("keeps expired and unsupported-plan credits non-actionable")
    func rejectsExpiredAndUnsupportedCredits() async throws {
        let service = ManualResetRefreshService(clock: {
            Date(timeIntervalSince1970: 100)
        })
        let expired = try ManualResetCredit(
            identifier: "expired",
            title: "Full reset",
            status: .available,
            isSupportedByPlan: true,
            expiresAt: Date(timeIntervalSince1970: 50)
        )
        let unsupported = try ManualResetCredit(
            identifier: "unsupported",
            title: "Full reset",
            status: .available,
            isSupportedByPlan: false,
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        for credit in [expired, unsupported] {
            let state = await service.refresh(.snapshot(try ManualResetSnapshot(
                availableCount: 1,
                applicableAvailableCount: 1,
                credits: [credit],
                capturedAt: Date(timeIntervalSince1970: 100)
            )))
            let summary = try #require(state.liveSummary)
            #expect(summary.expiration == .unavailable)
            #expect(!summary.hasActionableCredit)
        }
    }

    @Test("starts unavailable when no provider snapshot has succeeded")
    func startsUnavailable() async {
        let service = ManualResetRefreshService(clock: Date.init)

        let state = await service.refresh(.unavailable(.sourceMissing))

        #expect(state == .unavailable)
        #expect(!state.canRedeem)
    }

    private func snapshot(
        availableCount: Int,
        applicableCount: Int,
        expirations: [TimeInterval?]
    ) throws -> ManualResetSnapshot {
        let credits = try expirations.enumerated().map { index, expiration in
            try ManualResetCredit(
                identifier: "credit-\(index)",
                title: "Full reset",
                status: .available,
                isSupportedByPlan: true,
                expiresAt: expiration.map { Date(timeIntervalSince1970: $0) }
            )
        }
        return try ManualResetSnapshot(
            availableCount: availableCount,
            applicableAvailableCount: applicableCount,
            credits: credits,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private extension ManualResetRefreshState {
    var liveSummary: ManualResetSummary? {
        guard case let .live(summary) = self else { return nil }
        return summary
    }

    var staleSummary: ManualResetSummary? {
        guard case let .stale(summary) = self else { return nil }
        return summary
    }
}

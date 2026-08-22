import Foundation
import Testing
@testable import HermesUsageCore

struct ManualResetDomainTests {
    @Test("preserves valid provider-owned reset credit fields")
    func preservesValidCredit() throws {
        let credit = try ManualResetCredit(
            identifier: "credit-1",
            title: "Full reset",
            status: .available,
            isSupportedByPlan: true,
            grantedAt: Date(timeIntervalSince1970: 500),
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(credit.title == "Full reset")
        #expect(credit.status == .available)
        #expect(credit.isSupportedByPlan)
        #expect(credit.grantedAt == Date(timeIntervalSince1970: 500))
        #expect(credit.expiresAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test("rejects an empty opaque credit identifier")
    func rejectsEmptyIdentifier() {
        #expect(throws: ManualResetDomainError.invalidIdentifier) {
            _ = try ManualResetCredit(
                identifier: "   ",
                title: "Full reset",
                status: .available,
                isSupportedByPlan: true
            )
        }
    }

    @Test("rejects negative and inconsistent provider counts")
    func rejectsInvalidCounts() throws {
        #expect(throws: ManualResetDomainError.invalidCount) {
            _ = try ManualResetSnapshot(
                availableCount: -1,
                applicableAvailableCount: 0,
                credits: [],
                capturedAt: Date(timeIntervalSince1970: 100)
            )
        }

        #expect(throws: ManualResetDomainError.invalidCount) {
            _ = try ManualResetSnapshot(
                availableCount: 1,
                applicableAvailableCount: 2,
                credits: [],
                capturedAt: Date(timeIntervalSince1970: 100)
            )
        }
    }

    @Test("rejects inconsistent public display summaries")
    func rejectsInvalidSummary() {
        #expect(throws: ManualResetDomainError.invalidSummary) {
            _ = try ManualResetSummary(
                availableCount: 0,
                applicableAvailableCount: 0,
                expiration: .doesNotExpire,
                isApplicable: false,
                hasActionableCredit: false
            )
        }
        #expect(throws: ManualResetDomainError.invalidSummary) {
            _ = try ManualResetSummary(
                availableCount: 1,
                applicableAvailableCount: 0,
                expiration: .unavailable,
                isApplicable: true,
                hasActionableCredit: true
            )
        }
    }

    @Test("keeps a missing expiration non-expiring")
    func keepsMissingExpiration() throws {
        let credit = try ManualResetCredit(
            identifier: "credit-1",
            title: "Full reset",
            status: .available,
            isSupportedByPlan: true,
            expiresAt: nil
        )

        #expect(credit.expiresAt == nil)
    }
}

import Foundation
import Testing
@testable import HermesUsageCore

struct QuotaTemporalPolicyTests {
    @Test("rounds a future reset up to the next whole second")
    func roundsFutureResetUp() {
        let now = Date(timeIntervalSince1970: 1_000)
        let resetAt = Date(timeIntervalSince1970: 1_018.1)

        #expect(QuotaTemporalPolicy.secondsRemaining(until: resetAt, now: now) == 19)
    }

    @Test("does not expose negative countdown values after reset")
    func clampsPastResetToZero() {
        let now = Date(timeIntervalSince1970: 1_000)
        let resetAt = Date(timeIntervalSince1970: 999)

        #expect(QuotaTemporalPolicy.secondsRemaining(until: resetAt, now: now) == 0)
    }
}

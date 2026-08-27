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

    @Test("formats snapshot age with the relative suffix")
    func formatsSnapshotAge() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            QuotaTemporalPolicy.snapshotAgeLabel(
                capturedAt: Date(timeIntervalSince1970: 988),
                now: now
            ) == "12s fa"
        )
        #expect(
            QuotaTemporalPolicy.snapshotAgeLabel(
                capturedAt: Date(timeIntervalSince1970: 760),
                now: now
            ) == "4 min fa"
        )
        #expect(
            QuotaTemporalPolicy.snapshotAgeLabel(
                capturedAt: Date(timeIntervalSince1970: -6_200),
                now: now
            ) == "2 h fa"
        )
        #expect(
            QuotaTemporalPolicy.snapshotAgeLabel(
                capturedAt: Date(timeIntervalSince1970: -171_800),
                now: now
            ) == "2 g fa"
        )
    }

    @Test("clamps a current or future snapshot to just acquired")
    func clampsFutureSnapshotAge() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(
            QuotaTemporalPolicy.snapshotAgeLabel(
                capturedAt: now,
                now: now
            ) == "appena acquisito"
        )
        #expect(
            QuotaTemporalPolicy.snapshotAgeLabel(
                capturedAt: Date(timeIntervalSince1970: 1_001),
                now: now
            ) == "appena acquisito"
        )
    }

    @Test("formats long countdowns without rounding the remaining minutes into the next hour")
    func formatsLongCountdownPrecisely() {
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 14_401) == "tra 4 h 1 min")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 14_400) == "tra 4 h")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 3_601) == "tra 1 h 1 min")
    }

    @Test("formats every countdown range and clamps invalid input")
    func formatsAllCountdownRanges() {
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: -1) == "tra 0s")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 0) == "tra 0s")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 59) == "tra 59s")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 60) == "tra 1 min")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 3_600) == "tra 1 h")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 86_399) == "tra 23 h 59 min")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 86_100) == "tra 23 h 55 min")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 86_340) == "tra 23 h 59 min")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 86_400) == "tra 1 g")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 86_460) == "tra 1 g")
        #expect(QuotaTemporalPolicy.countdownLabel(seconds: 172_800) == "tra 2 g")
    }
}

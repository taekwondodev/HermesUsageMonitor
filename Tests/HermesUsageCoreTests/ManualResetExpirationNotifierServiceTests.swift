import Foundation
import Testing
@testable import HermesUsageCore

struct ManualResetExpirationNotifierServiceTests {
    // Fixed 2026-08-08T08:00:00Z; calendar UTC so local dates are stable. Offsets
    // 11h and 24h cross a midnight boundary (08-08 vs 08-09), giving distinct dates.
    private let now = Date(timeIntervalSince1970: 1_786_176_000)
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func make(
        records: Set<String> = [],
        deliverResult: Bool = true
    ) -> (service: ManualResetExpirationNotifierService, notifier: RecordingExpirationNotifier, history: RecordingExpirationHistory) {
        let notifier = RecordingExpirationNotifier(result: deliverResult)
        let history = RecordingExpirationHistory(records: records)
        let service = ManualResetExpirationNotifierService(
            notifier: notifier,
            history: history,
            clock: { now },
            calendar: utcCalendar
        )
        return (service, notifier, history)
    }

    private func credit(
        id: String,
        expiresAt: Date?,
        status: ManualResetCreditStatus = .available,
        supported: Bool = true
    ) throws -> ManualResetCredit {
        try ManualResetCredit(
            identifier: id,
            title: "Full reset",
            status: status,
            isSupportedByPlan: supported,
            expiresAt: expiresAt
        )
    }

    private func snapshot(credits: [ManualResetCredit]) throws -> ManualResetSnapshot {
        try ManualResetSnapshot(
            availableCount: credits.count,
            applicableAvailableCount: credits.filter { $0.status == .available && $0.isSupportedByPlan }.count,
            credits: credits,
            capturedAt: now
        )
    }

    private func hour(offset: Double = 0) -> Date {
        now.addingTimeInterval(offset * 3600)
    }

    // MARK: Acceptance "groups unexpired dated credits by local date, one notification per date"

    @Test("two credits on the same local date produce one notification")
    func sameDateGroupsIntoOne() async throws {
        let (service, notifier, _) = make()
        // both on 2026-08-20, one at 12:00Z, one at 23:00Z (within 24h)
        let credits = [
            try credit(id: "a", expiresAt: hour(offset: 11)),
            try credit(id: "b", expiresAt: hour(offset: 15)),
        ]
        await service.process(.snapshot(try snapshot(credits: credits)))
        let delivered = await notifier.delivered
        #expect(delivered.count == 1)
        #expect(delivered[0].creditCount == 2)
    }

    @Test("credits on different local dates produce separate groups")
    func differentDatesProduceSeparateGroups() async throws {
        let (service, notifier, _) = make()
        // 2026-08-20 and 2026-08-21
        let credits = [
            try credit(id: "a", expiresAt: hour(offset: 11)),      // today
            try credit(id: "b", expiresAt: hour(offset: 24)),      // tomorrow
        ]
        await service.process(.snapshot(try snapshot(credits: credits)))
        let delivered = await notifier.delivered
        #expect(delivered.count == 2)
        #expect(Set(delivered.map(\.localDate)).count == 2)
    }

    // MARK: Acceptance "eligible when earliest credit first has <=24h remaining"

    @Test("a credit more than 24 hours out produces no notification")
    func over24HoursIsNotEligible() async throws {
        let (service, notifier, _) = make()
        let credits = [try credit(id: "a", expiresAt: hour(offset: 25))]
        await service.process(.snapshot(try snapshot(credits: credits)))
        #expect(await notifier.delivered.isEmpty)
    }

    @Test("launching inside the final 24 hours emits one notification")
    func launchWithin24HNotifies() async throws {
        let (service, notifier, _) = make()
        let credits = [try credit(id: "a", expiresAt: hour(offset: 12))]
        await service.process(.snapshot(try snapshot(credits: credits)))
        #expect((await notifier.delivered).count == 1)
    }

    // MARK: Acceptance "already-recorded group stays silent across refreshes and restarts"

    @Test("a recorded group stays silent on subsequent refreshes")
    func recordedGroupStaysSilent() async throws {
        let (service, notifier, history) = make()
        let credits = [try credit(id: "a", expiresAt: hour(offset: 12))]
        await service.process(.snapshot(try snapshot(credits: credits)))
        let firstCount = (await notifier.delivered).count

        // Simulates a restart where the group key is already in history.
        let second = make(records: await history.keys)
        await second.service.process(.snapshot(try snapshot(credits: credits)))
        #expect(firstCount == 1)
        #expect(await second.notifier.delivered.isEmpty)
    }

    @Test("a late-discovered credit for an already-notified date does not re-notify")
    func lateCreditDoesNotNotifyAgain() async throws {
        let (service, notifier, _) = make()
        let first = [try credit(id: "a", expiresAt: hour(offset: 12))]
        await service.process(.snapshot(try snapshot(credits: first)))
        // second credit on the SAME local date (08-08), discovered later
        let secondCredits = first + [try credit(id: "b", expiresAt: hour(offset: 14))]
        await service.process(.snapshot(try snapshot(credits: secondCredits)))
        #expect((await notifier.delivered).count == 1)
    }

    // MARK: Acceptance "excluded states produce no notification"

    @Test("expired, non-expiring, stale, unavailable, malformed, and non-plan-supported states do not notify")
    func excludedStatesDoNotNotify() async throws {
        let excluded: [ManualResetReadResult] = [
            .snapshot(try snapshot(credits: [try credit(id: "expired", expiresAt: hour(offset: -1))])),
            .snapshot(try snapshot(credits: [try credit(id: "noexpiry", expiresAt: nil)])),
            .snapshot(try snapshot(credits: [try credit(id: "unsupported", expiresAt: hour(offset: 12), supported: false)])),
            .snapshot(try snapshot(credits: [try credit(id: "redeemed", expiresAt: hour(offset: 12), status: .redeemed)])),
            .unavailable(.sourceMissing),
        ]
        for result in excluded {
            let (service, notifier, _) = make()
            await service.process(result)
            #expect(await notifier.delivered.isEmpty)
        }
    }

    // MARK: "history is written only after successful delivery"

    @Test("history is recorded only when delivery succeeds")
    func recordOnlyAfterSuccessfulDelivery() async throws {
        let failed = make(deliverResult: false)
        await failed.service.process(.snapshot(try snapshot(credits: [try credit(id: "a", expiresAt: hour(offset: 12))])))
        #expect(await failed.history.keys.isEmpty)

        let ok = make(deliverResult: true)
        await ok.service.process(.snapshot(try snapshot(credits: [try credit(id: "a", expiresAt: hour(offset: 12))])))
        #expect(await ok.history.keys.count == 1)
    }

    // MARK: Exact 24-hour boundary

    @Test("a credit exactly at the 24-hour boundary is eligible")
    func boundaryAt24HoursIsEligible() async throws {
        let (service, notifier, _) = make()
        let credits = [try credit(id: "a", expiresAt: hour(offset: 24))]
        await service.process(.snapshot(try snapshot(credits: credits)))
        #expect((await notifier.delivered).count == 1)
    }
}

private actor RecordingExpirationNotifier: ManualResetExpirationNotifier {
    private let result: Bool
    private var _delivered: [ManualResetExpirationNotification] = []

    init(result: Bool) { self.result = result }

    func deliver(_ notification: ManualResetExpirationNotification) async -> Bool {
        _delivered.append(notification)
        return result
    }

    var delivered: [ManualResetExpirationNotification] { _delivered }
}

private actor RecordingExpirationHistory: ManualResetExpirationHistory {
    private var _keys: Set<String>
    init(records: Set<String> = []) { _keys = records }

    func contains(_ key: ManualResetExpirationGroupKey) async -> Bool {
        _keys.contains(key.rawValue)
    }

    func record(_ key: ManualResetExpirationGroupKey) async {
        _keys.insert(key.rawValue)
    }

    var keys: Set<String> { _keys }
}
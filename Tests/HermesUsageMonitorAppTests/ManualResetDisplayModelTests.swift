import Foundation
import HermesUsageCore
import Testing
@testable import HermesUsageMonitorApp

struct ManualResetDisplayModelTests {
    @Test("shows known count, applicability, and nearest expiration")
    func showsLiveApplicableState() throws {
        let expiration = try #require(ISO8601DateFormatter().date(from: "2030-09-21T12:00:00Z"))
        let model = ManualResetDisplayModel(
            state: .live(try ManualResetSummary(
                availableCount: 1,
                applicableAvailableCount: 1,
                expiration: .dated(QuotaTimestamp(date: expiration)),
                isApplicable: true,
                hasActionableCredit: true
            )),
            locale: Locale(identifier: "it_IT"),
            timeZone: try #require(TimeZone(secondsFromGMT: 0))
        )

        #expect(model.countLabel == "1 disponibile")
        #expect(model.title == "Full reset disponibile")
        #expect(model.statusLabel == nil)
        #expect(model.applicabilityLabel == "Utilizzabile ora")
        #expect(model.expirationLabel == "Scade il 21/9")
        #expect(!model.isStale)
    }

    @Test("pluralizes zero and keeps it distinct from unavailable")
    func showsZeroState() throws {
        let model = ManualResetDisplayModel(
            state: .live(try ManualResetSummary(
                availableCount: 0,
                applicableAvailableCount: 0,
                expiration: .unavailable,
                isApplicable: false,
                hasActionableCredit: false
            )))

        #expect(model.countLabel == "0 disponibili")
        #expect(model.title == "Nessun Full reset disponibile")
        #expect(model.statusLabel == nil)
        #expect(model.applicabilityLabel == nil)
        #expect(model.expirationLabel == nil)
    }

    @Test("marks retained reset data stale without losing known values")
    func showsStaleState() throws {
        let model = ManualResetDisplayModel(
            state: .stale(try ManualResetSummary(
                availableCount: 2,
                applicableAvailableCount: 1,
                expiration: .doesNotExpire,
                isApplicable: true,
                hasActionableCredit: true
            ))
        )

        #expect(model.countLabel == "2 disponibili")
        #expect(model.statusLabel == "Non aggiornato")
        #expect(model.applicabilityLabel == "Utilizzabile all’ultimo aggiornamento")
        #expect(model.expirationLabel == "Nessuna scadenza")
        #expect(model.isStale)
    }

    @Test("shows unavailable without inventing count or expiration")
    func showsUnavailableState() {
        let model = ManualResetDisplayModel(state: .unavailable)

        #expect(model.countLabel == nil)
        #expect(model.title == "Stato reset non disponibile")
        #expect(model.statusLabel == nil)
        #expect(model.applicabilityLabel == nil)
        #expect(model.expirationLabel == nil)
        #expect(!model.isStale)
    }

    @Test("keeps a known positive count while expiration is unavailable")
    func showsIncompleteDetails() throws {
        let model = ManualResetDisplayModel(
            state: .live(try ManualResetSummary(
                availableCount: 2,
                applicableAvailableCount: 1,
                expiration: .unavailable,
                isApplicable: true,
                hasActionableCredit: false
            ))
        )

        #expect(model.countLabel == "2 disponibili")
        #expect(model.statusLabel == nil)
        #expect(model.applicabilityLabel == "Utilizzabile ora")
        #expect(model.expirationLabel == "Scadenza non disponibile")
    }
}

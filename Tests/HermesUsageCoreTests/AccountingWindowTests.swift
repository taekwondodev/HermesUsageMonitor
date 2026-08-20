import Foundation
import Testing
@testable import HermesUsageCore

struct AccountingWindowTests {
    @Test("defines a rolling thirty day window from the refresh instant")
    func definesRollingWindow() {
        let window = AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000))

        #expect(window.start == Date(timeIntervalSince1970: -2_590_000))
        #expect(window.end == Date(timeIntervalSince1970: 2_000))
    }

    @Test("includes the boundary and recent rows but excludes older rows")
    func appliesInclusiveStartBoundary() {
        let window = AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000))

        #expect(window.includes(lastSeen: Date(timeIntervalSince1970: -2_590_000)))
        #expect(window.includes(lastSeen: Date(timeIntervalSince1970: 2_000)))
        #expect(window.includes(lastSeen: Date(timeIntervalSince1970: -2_590_001)) == false)
        #expect(window.includes(lastSeen: Date(timeIntervalSince1970: 2_001)) == false)
        #expect(window.includes(lastSeen: nil))
    }
}

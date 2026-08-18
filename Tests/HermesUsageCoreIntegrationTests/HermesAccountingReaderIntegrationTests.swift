import Foundation
import Testing
@testable import HermesUsageCore

struct HermesAccountingReaderIntegrationTests {
    @Test("reads partial accounting and missing cost without inventing values")
    func readsPartialAccounting() throws {
        let fileURL = try makeTemporaryFile(
            """
            {"version":1,"entries":[
              {"subscription":"chatgpt","profile":"work","tokens":{"input":100,"output":25},"requests":2,"models":["gpt-5"],"provider":"openai"},
              {"subscription":"chatgpt","profile":"personal","requests":1,"provider":"openai"}
            ]}
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let values = try HermesAccountingReader(fileURL: fileURL).read()
        #expect(values.count == 2)
        #expect(values[0].tokens?.total == 125)
        #expect(values[0].cost == nil)
        #expect(values[1].tokens == nil)
        #expect(values[1].cost == nil)
    }

    @Test("reads multiple profiles and commercial subscriptions")
    func readsMultipleProfiles() throws {
        let fileURL = try makeTemporaryFile(
            """
            {"version":1,"entries":[
              {"subscription":"nous-portal","profile":"one","requests":3,"models":["claude"],"cost":{"amount":0.5,"currency":"USD"}},
              {"subscription":"opencode-go","profile":"two","tokens":{"input":10},"requests":1,"models":["gpt-5"]}
            ]}
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = LocalAccountingService(source: HermesAccountingReader(fileURL: fileURL))
            .readGroupedBySubscription()
        guard case let .available(grouped) = result else {
            Issue.record("Expected available accounting")
            return
        }
        #expect(grouped[.nousPortal]?.first?.profile == "one")
        #expect(grouped[.nousPortal]?.first?.cost?.currency == "USD")
        #expect(grouped[.opencodeGo]?.first?.profile == "two")
        #expect(grouped[.opencodeGo]?.first?.tokens?.output == nil)
    }

    private func makeTemporaryFile(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(json.utf8).write(to: url, options: [.atomic])
        return url
    }
}

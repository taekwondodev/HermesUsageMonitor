import Foundation
import Testing
@testable import HermesUsageCore

struct FileManualResetExpirationHistoryIntegrationTests {
    @Test("reloads recorded keys and deduplicates across a new instance")
    func reloadsAndDeduplicates() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let key = ManualResetExpirationGroupKey(provider: "p", localDate: "2026-08-08")
        let first = FileManualResetExpirationHistory(
            fileURL: dir.appendingPathComponent("history.json")
        )
        await first.record(key)
        #expect(await first.contains(key))

        // a fresh instance over the same file must reload the key
        let second = FileManualResetExpirationHistory(
            fileURL: dir.appendingPathComponent("history.json")
        )
        #expect(await second.contains(key))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("persists only the provider+date group key, never a credit id")
    func persistsOnlyGroupKey() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent("history.json")

        let key = ManualResetExpirationGroupKey(provider: "manual-reset-credit", localDate: "2026-08-08")
        await FileManualResetExpirationHistory(fileURL: file).record(key)

        let raw = try String(contentsOf: file, encoding: .utf8)
        #expect(raw.contains("manual-reset-credit#2026-08-08"))
        #expect(!raw.contains("credit-"))
        #expect(!raw.contains("payload"))
        #expect(!raw.contains("account"))
        try? FileManager.default.removeItem(at: dir)
    }
}
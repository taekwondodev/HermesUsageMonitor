import Foundation
import Testing
@testable import HermesUsageCore

struct HermesBridgeIntegrationTests {
    @Test("decodes live Hermes usage output and preserves unavailable providers")
    func decodesUsageCommandOutput() async throws {
        let fixture = Data(
            """
            {
              "version": 1,
              "providers": {
                "nous": {
                  "status": "available",
                  "subscription": "nous-portal",
                  "capturedAt": "2030-03-17T12:00:00Z",
                  "windows": [{"kind":"monthly","label":"Subscription","usedPercent":83.0}]
                },
                "openai-codex": {
                  "status": "unavailable",
                  "subscription": "chatgpt",
                  "reason": "authentication failed (401)"
                }
              }
            }
            """.utf8
        )
        let observations = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        ).read()

        #expect(observations.count == 2)
        guard let nous = observations.first(where: { $0.subscription == .nousPortal }),
              let chatGPT = observations.first(where: { $0.subscription == .chatGPT })
        else {
            Issue.record("Expected both commercial subscriptions")
            return
        }
        guard case let .snapshot(snapshot) = nous.result else {
            Issue.record("Expected Nous Portal quota snapshot")
            return
        }
        #expect(snapshot.windows[0].kind == .monthly)
        #expect(snapshot.windows[0].usedPercent == 83)
        #expect(chatGPT.result == .unavailable(.authenticationFailed))
    }

    @Test("marks an unsupported usage contract explicitly")
    func marksUnsupportedUsageVersion() async throws {
        let fixture = Data(
            """
            {"version": 99, "providers": {}}
            """.utf8
        )
        let observations = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        ).read()

        #expect(observations.count == Subscription.allCases.count)
        #expect(observations.allSatisfy { $0.result == .unavailable(.unsupportedVersion) })
    }

    @Test("marks malformed usage JSON without hiding providers")
    func marksMalformedUsagePayload() async throws {
        let observations = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: Data("not-json".utf8)
        ).read()

        #expect(observations.count == Subscription.allCases.count)
        #expect(observations.allSatisfy { $0.result == .unavailable(.malformedSnapshot) })
    }

    @Test("reads the real state.db accounting schema read-only")
    func readsStateDatabase() throws {
        let hermesHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = hermesHome.appendingPathComponent("state.db")
        try FileManager.default.createDirectory(
            at: hermesHome,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: hermesHome) }

        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            CREATE TABLE session_model_usage (
              billing_provider TEXT,
              model TEXT,
              input_tokens INTEGER,
              output_tokens INTEGER,
              api_call_count INTEGER,
              estimated_cost_usd REAL,
              actual_cost_usd REAL
            );
            INSERT INTO session_model_usage VALUES ('nous','openai/gpt-5.6-luna',100,25,2,0.12,0);
            """
        )

        let values = try HermesStateDBAccountingReader(hermesHome: hermesHome)
            .read()
        let value = try #require(values.first)

        #expect(value.subscription == .nousPortal)
        #expect(value.tokens?.total == 125)
        #expect(value.requests == 2)
        let expectedCost = try #require(Decimal(string: "0.12"))
        let actualCost = try #require(value.cost?.amount)
        let tolerance = try #require(Decimal(string: "0.0001"))
        #expect(abs(actualCost - expectedCost) < tolerance)
        #expect(value.models == ["openai/gpt-5.6-luna"])
    }

    @Test("reads a state.db that uses WAL journal mode")
    func readsWalStateDatabase() throws {
        let hermesHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = hermesHome.appendingPathComponent("state.db")
        try FileManager.default.createDirectory(
            at: hermesHome,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: hermesHome) }

        // Hermes keeps state.db in WAL mode, which previously broke the
        // `-readonly` open (exit 14). Guard the WAL read path explicitly.
        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            PRAGMA journal_mode=WAL;
            CREATE TABLE session_model_usage (
              billing_provider TEXT,
              model TEXT,
              input_tokens INTEGER,
              output_tokens INTEGER,
              api_call_count INTEGER,
              estimated_cost_usd REAL,
              actual_cost_usd REAL
            );
            INSERT INTO session_model_usage VALUES ('nous','openai/gpt-5.6-luna',100,25,2,0.12,0);
            """
        )

        let values = try HermesStateDBAccountingReader(hermesHome: hermesHome)
            .read()
        let value = try #require(values.first)

        #expect(value.subscription == .nousPortal)
        #expect(value.requests == 2)
    }

    private func runSQLite(databaseURL: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

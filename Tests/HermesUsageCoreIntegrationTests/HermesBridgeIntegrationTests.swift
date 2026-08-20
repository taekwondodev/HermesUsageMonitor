import Foundation
import Testing
@testable import HermesUsageCore

struct HermesBridgeIntegrationTests {
    @Test("invokes the installed bridge launcher with the JSON contract")
    func invokesBridgeLauncher() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let launcher = root.appendingPathComponent("hermes-usage-bridge")
        let fixture = """
        {"version":1,"providers":{"openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"rolling-5h","label":"Session","usedPercent":40.0,"resetAt":"2030-03-17T17:00:00Z"}]}}}
        """
        try "#!/bin/sh\n[ \"$1\" = \"--json\" ] || exit 2\nprintf '%s' '\(fixture)'\n".write(
            to: launcher,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let observations = await HermesUsageCommandReader(
            hermesHome: root,
            executable: launcher
        ).read()

        let chatGPT = try #require(observations.first { $0.subscription == .chatGPT })
        guard case let .snapshot(snapshot) = chatGPT.result else {
            Issue.record("Expected a live snapshot from the bridge launcher")
            return
        }
        #expect(snapshot.windows.first?.usedPercent == 40.0)
    }

    @Test("ignores unsupported providers and preserves supported unavailable providers")
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

        #expect(observations.count == 1)
        guard let chatGPT = observations.first(where: { $0.subscription == .chatGPT })
        else {
            Issue.record("Expected the supported ChatGPT observation")
            return
        }
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
              actual_cost_usd REAL,
              last_seen REAL
            );
            INSERT INTO session_model_usage VALUES ('nous','openai/gpt-5.6-luna',100,25,2,0.12,0,1000);
            """
        )

        let values = try HermesStateDBAccountingReader(hermesHome: hermesHome)
            .read(window: AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000)))
        #expect(values.isEmpty)
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
              actual_cost_usd REAL,
              last_seen REAL
            );
            INSERT INTO session_model_usage VALUES ('nous','openai/gpt-5.6-luna',100,25,2,0.12,0,1000);
            """
        )

        let values = try HermesStateDBAccountingReader(hermesHome: hermesHome)
            .read(window: AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000)))
        #expect(values.isEmpty)
    }

    @Test("filters accounting rows to the rolling window before aggregation")
    func filtersRowsByLastSeen() throws {
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
              actual_cost_usd REAL,
              last_seen REAL
            );
            INSERT INTO session_model_usage VALUES ('opencode-go','gpt-5',10,20,1,0.10,0,1000);
            INSERT INTO session_model_usage VALUES ('opencode-go','gpt-5',30,40,2,0.20,0,-2590000);
            INSERT INTO session_model_usage VALUES ('opencode-go','gpt-5',100,100,9,0.90,0,-2590001);
            INSERT INTO session_model_usage VALUES ('opencode-go','gpt-5',50,50,4,0.40,0,2001);
            INSERT INTO session_model_usage VALUES ('openai-codex','gpt-5',5,6,1,0.05,0,NULL);
            """
        )

        let values = try HermesStateDBAccountingReader(hermesHome: hermesHome)
            .read(window: AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000)))

        #expect(values.count == 2)
        let openCode = try #require(values.first { $0.subscription == .opencodeGo })
        #expect(openCode.tokens?.input == 40)
        #expect(openCode.tokens?.output == 60)
        #expect(openCode.requests == 3)
        let expectedCost = try #require(Decimal(string: "0.3"))
        let actualCost = try #require(openCode.cost?.amount)
        let tolerance = try #require(Decimal(string: "0.0001"))
        #expect(abs(actualCost - expectedCost) < tolerance)
        let chatGPT = try #require(values.first { $0.subscription == .chatGPT })
        #expect(chatGPT.tokens?.total == 11)
        #expect(chatGPT.requests == 1)
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

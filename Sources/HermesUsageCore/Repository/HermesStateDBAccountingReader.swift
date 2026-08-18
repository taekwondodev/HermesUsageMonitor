import Foundation

public struct HermesStateDBAccountingReader: LocalAccountingSource, Sendable {
    private let databaseURL: URL

    public init(hermesHome: URL) {
        databaseURL = hermesHome.appendingPathComponent("state.db")
    }

    public func read() throws -> [LocalAccounting] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw HermesAccountingReadError.sourceMissing
        }

        let sql = """
        SELECT billing_provider AS provider,
               model,
               SUM(input_tokens) AS inputTokens,
               SUM(output_tokens) AS outputTokens,
               SUM(api_call_count) AS requests,
               SUM(estimated_cost_usd) AS estimatedCost,
               SUM(actual_cost_usd) AS actualCost
        FROM session_model_usage
        WHERE billing_provider IS NOT NULL AND billing_provider != ''
        GROUP BY billing_provider, model
        ORDER BY billing_provider, model;
        """

        let data = try runSQLite(sql)
        let rows: [Row]
        do {
            rows = try JSONDecoder().decode([Row].self, from: data)
        } catch {
            throw HermesAccountingReadError.malformedData
        }

        return try rows.compactMap { row in
            guard let provider = row.provider,
                  let subscription = subscription(for: provider) else {
                return nil
            }

            let tokens: AccountingTokens?
            if row.inputTokens != nil || row.outputTokens != nil {
                tokens = try AccountingTokens(
                    input: max(0, row.inputTokens ?? 0),
                    output: max(0, row.outputTokens ?? 0)
                )
            } else {
                tokens = nil
            }

            let costValue = (row.actualCost ?? 0) > 0 ? row.actualCost : row.estimatedCost
            let cost = try costValue.map {
                try AccountingCost(amount: max(0, $0), currency: "USD")
            }

            return try LocalAccounting(
                subscription: subscription,
                tokens: tokens,
                requests: row.requests.map { max(0, $0) },
                models: row.model.map { [$0] } ?? [],
                cost: cost,
                provider: provider
            )
        }
    }

    private func subscription(for provider: String) -> Subscription? {
        switch provider.lowercased() {
        case "nous", "nous-portal":
            return .nousPortal
        case "openai-codex", "chatgpt":
            return .chatGPT
        case "opencode-go":
            return .opencodeGo
        default:
            return nil
        }
    }

    private func runSQLite(_ sql: String) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", databaseURL.path, sql]

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning {
                guard Date() < deadline else {
                    process.terminate()
                    throw HermesAccountingReadError.sourceUnreadable
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } catch {
            throw HermesAccountingReadError.sourceUnreadable
        }
        guard process.terminationStatus == 0 else {
            throw HermesAccountingReadError.sourceUnreadable
        }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}

private extension HermesStateDBAccountingReader {
    struct Row: Decodable {
        let provider: String?
        let model: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let requests: Int?
        let estimatedCost: Decimal?
        let actualCost: Decimal?
    }
}

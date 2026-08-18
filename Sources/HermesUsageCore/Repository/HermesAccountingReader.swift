import Foundation

public struct HermesAccountingReader: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let hermesHome = environment["HERMES_HOME"].map(URL.init(fileURLWithPath:))
            ?? homeDirectory.appendingPathComponent(".hermes", isDirectory: true)
        self.init(fileURL: hermesHome.appendingPathComponent("usage/accounting.json"))
    }

    public func read() throws -> [LocalAccounting] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LocalAccountingReadError.sourceMissing
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw LocalAccountingReadError.sourceUnreadable
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw LocalAccountingReadError.malformedData
        }

        guard payload.version == 1 else {
            throw LocalAccountingReadError.unsupportedVersion
        }

        do {
            return try payload.entries.map { entry in
                try LocalAccounting(
                    subscription: entry.subscription,
                    profile: entry.profile,
                    tokens: try entry.tokens.map {
                        try AccountingTokens(input: $0.input, output: $0.output)
                    },
                    requests: entry.requests,
                    models: entry.models ?? [],
                    cost: try entry.cost.map {
                        try AccountingCost(amount: $0.amount, currency: $0.currency)
                    },
                    provider: entry.provider
                )
            }
        } catch {
            throw LocalAccountingReadError.malformedData
        }
    }
}

private extension HermesAccountingReader {
    struct Payload: Decodable {
        let version: Int
        let entries: [Entry]
    }

    struct Entry: Decodable {
        let subscription: Subscription
        let profile: String?
        let tokens: Tokens?
        let requests: Int?
        let models: [String]?
        let cost: Cost?
        let provider: String?
    }

    struct Tokens: Decodable {
        let input: Int?
        let output: Int?
    }

    struct Cost: Decodable {
        let amount: Decimal
        let currency: String
    }
}

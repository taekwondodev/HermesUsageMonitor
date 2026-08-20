import Foundation

enum HermesAccountingReadError: Error {
    case sourceMissing
    case sourceUnreadable
    case malformedData
    case unsupportedVersion
}

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

    public func read(window: AccountingWindow) throws -> [LocalAccounting] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw HermesAccountingReadError.sourceMissing
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw HermesAccountingReadError.sourceUnreadable
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw HermesAccountingReadError.malformedData
        }

        guard payload.version == 1 else {
            throw HermesAccountingReadError.unsupportedVersion
        }

        do {
            return try payload.entries.compactMap { entry in
                guard let subscription = Subscription(rawValue: entry.subscription) else {
                    return nil
                }
                return try LocalAccounting(
                    subscription: subscription,
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
            throw HermesAccountingReadError.malformedData
        }
    }
}

private extension HermesAccountingReader {
    struct Payload: Decodable {
        let version: Int
        let entries: [Entry]
    }

    struct Entry: Decodable {
        let subscription: String
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

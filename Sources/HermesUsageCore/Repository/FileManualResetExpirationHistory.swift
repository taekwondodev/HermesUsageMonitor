import Foundation
import os

/// Persists notified manual-reset expiration group keys under Application Support.
/// Stored data is only the stable `provider#local-date` keys: no credentials,
/// account ids, credit ids, payloads, or usage history.
public actor FileManualResetExpirationHistory: ManualResetExpirationHistory {
    private let fileURL: URL
    private var cache: Set<String>?
    private let logger = os.Logger(subsystem: "HermesUsageMonitor", category: "manual-reset-expiration-history")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func contains(_ key: ManualResetExpirationGroupKey) async -> Bool {
        await loaded().contains(key.rawValue)
    }

    public func record(_ key: ManualResetExpirationGroupKey) async {
        var existing = await loaded()
        existing.insert(key.rawValue)
        await persist(existing)
    }

    private func loaded() async -> Set<String> {
        if let cache { return cache }
        let data = try? Data(contentsOf: fileURL)
        let keys = data.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let value = Set(keys)
        cache = value
        return value
    }

    private func persist(_ keys: Set<String>) async {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Array(keys).sorted())
            try data.write(to: fileURL, options: .atomic)
            cache = keys
        } catch {
            logger.error("Could not persist manual reset expiration history: \(error.localizedDescription)")
            cache = keys
        }
    }
}
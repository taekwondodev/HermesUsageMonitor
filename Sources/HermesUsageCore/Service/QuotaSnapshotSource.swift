import Foundation

public protocol QuotaSnapshotSource: Sendable {
    func read() -> QuotaReadResult
}

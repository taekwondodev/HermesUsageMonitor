import Foundation

public protocol QuotaSnapshotObserver: Sendable {
    func record(_ result: QuotaReadResult)
}

public struct NoopQuotaSnapshotObserver: QuotaSnapshotObserver, Sendable {
    public init() {}

    public func record(_ result: QuotaReadResult) {}
}

public struct QuotaSnapshotService: Sendable {
    private let source: any QuotaSnapshotSource
    private let observer: any QuotaSnapshotObserver

    public init(
        source: any QuotaSnapshotSource,
        observer: any QuotaSnapshotObserver = NoopQuotaSnapshotObserver()
    ) {
        self.source = source
        self.observer = observer
    }

    public func read() -> QuotaReadResult {
        let result = source.read()
        observer.record(result)
        return result
    }
}

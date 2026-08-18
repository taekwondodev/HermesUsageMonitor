import Foundation

public protocol LocalAccountingSource: Sendable {
    func read() throws -> [LocalAccounting]
}

extension HermesAccountingReader: LocalAccountingSource {}

public struct LocalAccountingService: Sendable {
    private let source: any LocalAccountingSource

    public init(source: any LocalAccountingSource) {
        self.source = source
    }

    public func readGroupedBySubscription() throws -> [Subscription: [LocalAccounting]] {
        Dictionary(grouping: try source.read(), by: \.subscription)
    }
}

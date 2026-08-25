import Foundation

public enum QuotaWindowDisplayOrder {
    private static let opencodeGo: [QuotaWindowKind] = [
        .rollingFiveHours,
        .weekly,
        .monthly
    ]

    public static func windows(
        for subscription: Subscription,
        windows: [QuotaWindow]
    ) -> [QuotaWindow] {
        switch subscription {
        case .opencodeGo:
            return opencodeGoWindows(windows)
        case .chatGPT:
            return chatGPTWindows(windows)
        }
    }

    private static func chatGPTWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        let knownOrder: [QuotaWindowKind] = [.rollingFiveHours, .weekly]
        return windows.enumerated().sorted { lhs, rhs in
            let lhsRank = knownOrder.firstIndex(of: lhs.element.kind) ?? knownOrder.count
            let rhsRank = knownOrder.firstIndex(of: rhs.element.kind) ?? knownOrder.count
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func opencodeGoWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        let knownKinds = Set(opencodeGo)
        return windows.sorted { lhs, rhs in
            let lhsIndex = knownKinds.contains(lhs.kind) ? index(of: lhs.kind) : opencodeGo.count
            let rhsIndex = knownKinds.contains(rhs.kind) ? index(of: rhs.kind) : opencodeGo.count
            return lhsIndex < rhsIndex
        }
    }

    private static func index(of kind: QuotaWindowKind) -> Int {
        guard let index = opencodeGo.firstIndex(of: kind) else {
            preconditionFailure("Unsupported OpenCode Go quota window kind")
        }
        return index
    }

}
import Foundation

public enum QuotaWindowDisplayOrder {
    public static func windows(
        for subscription: Subscription,
        windows: [QuotaWindow]
    ) -> [QuotaWindow] {
        switch subscription {
        case .chatGPT, .claude:
            return orderedWindows(windows)
        }
    }

    private static func orderedWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        let knownOrder: [QuotaWindowKind] = [.rollingFiveHours, .weekly]
        return windows.enumerated().sorted { lhs, rhs in
            let lhsRank = knownOrder.firstIndex(of: lhs.element.kind) ?? knownOrder.count
            let rhsRank = knownOrder.firstIndex(of: rhs.element.kind) ?? knownOrder.count
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

import Foundation

public enum QuotaTemporalPolicy {
    public static func secondsRemaining(until date: Date, now: Date) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now))))
    }
}

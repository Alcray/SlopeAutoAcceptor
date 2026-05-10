import Foundation

public struct DedupeCache {
    private let cooldown: TimeInterval
    private var lastProcessed: [String: Date] = [:]

    public init(cooldown: TimeInterval) {
        self.cooldown = cooldown
    }

    public mutating func shouldProcess(
        _ key: String,
        now: Date = Date(),
        cooldownOverride: TimeInterval? = nil
    ) -> Bool {
        let activeCooldown = cooldownOverride ?? cooldown
        if let previous = lastProcessed[key], now.timeIntervalSince(previous) < activeCooldown {
            return false
        }

        lastProcessed[key] = now
        prune(now: now)
        return true
    }

    public mutating func removeAll() {
        lastProcessed.removeAll()
    }

    private mutating func prune(now: Date) {
        let staleAge = max(cooldown * 4, 60)
        lastProcessed = lastProcessed.filter { _, date in
            now.timeIntervalSince(date) < staleAge
        }
    }
}

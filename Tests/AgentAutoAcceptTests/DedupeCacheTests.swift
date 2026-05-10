import AgentAutoAcceptCore
import Foundation

func runDedupeCacheTests(_ suite: TestSuite) {
    suite.run("dedupe cache enforces cooldown and reset") {
        var cache = DedupeCache(cooldown: 10)

        suite.expect(cache.shouldProcess("prompt", now: Date(timeIntervalSince1970: 100)), "first prompt should process")
        suite.expect(!cache.shouldProcess("prompt", now: Date(timeIntervalSince1970: 109)), "same prompt should be blocked during cooldown")
        suite.expect(cache.shouldProcess("prompt", now: Date(timeIntervalSince1970: 110)), "same prompt should process at cooldown boundary")

        cache.removeAll()
        suite.expect(cache.shouldProcess("prompt", now: Date(timeIntervalSince1970: 111)), "reset should allow immediate reprocess")
    }

    suite.run("dedupe cache prunes stale keys") {
        var cache = DedupeCache(cooldown: 10)

        suite.expect(cache.shouldProcess("old", now: Date(timeIntervalSince1970: 0)), "old key should process")
        suite.expect(cache.shouldProcess("new", now: Date(timeIntervalSince1970: 100)), "new key should process and prune stale entries")
        suite.expect(cache.shouldProcess("old", now: Date(timeIntervalSince1970: 101)), "pruned old key should process again")
    }
}

import Foundation

@main
struct TestRunner {
    static func main() {
        let suite = TestSuite()
        runAppProfileTests(suite)
        runTextNormalizerTests(suite)
        runPromptDetectorTests(suite)
        runAutoApprovalControllerTests(suite)
        runDedupeCacheTests(suite)
        runAuditLoggerTests(suite)
        runSettingsStoreTests(suite)
        suite.finish()
    }
}

final class TestSuite {
    private var currentTestName = ""
    private var testCount = 0
    private var failures: [String] = []

    func run(_ name: String, _ body: () -> Void) {
        currentTestName = name
        testCount += 1
        body()

        if failures.contains(where: { $0.hasPrefix("[\(name)]") }) {
            print("FAIL \(name)")
        } else {
            print("PASS \(name)")
        }

        currentTestName = ""
    }

    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else {
            return
        }

        failures.append("[\(currentTestName)] \(message)")
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("\n\(testCount) tests passed.")
            exit(0)
        }

        print("\n\(failures.count) assertion(s) failed:")
        for failure in failures {
            print("- \(failure)")
        }
        exit(1)
    }
}

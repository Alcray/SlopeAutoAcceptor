import AgentAutoAcceptCore
import Foundation

func runAuditLoggerTests(_ suite: TestSuite) {
    suite.run("JSONL audit logger persists recent events and skips malformed lines") {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("audit.jsonl")
        guard let logger = try? JSONLAuditLogger(fileURL: fileURL) else {
            suite.expect(false, "logger should initialize in a temporary directory")
            return
        }

        let first = auditEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: 100
        )
        let second = auditEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestamp: 200
        )

        do {
            try logger.append(first)
            try appendText("not-json\n", to: fileURL)
            try logger.append(second)
        } catch {
            suite.expect(false, "logger append should not throw: \(error)")
            return
        }

        let rawLines = (try? String(contentsOf: fileURL, encoding: .utf8).split(separator: "\n").count) ?? 0
        suite.expect(rawLines == 3, "audit file should contain both JSON events and the malformed line")
        suite.expect(logger.recentEvents(limit: 10) == [first, second], "recent events should decode valid JSONL entries")
        suite.expect(logger.recentEvents(limit: 1) == [second], "recent events should honor the limit")
    }
}

private func auditEvent(id: UUID, timestamp: TimeInterval) -> AuditEvent {
    AuditEvent(
        id: id,
        timestamp: Date(timeIntervalSince1970: timestamp),
        appName: "Cursor",
        bundleIdentifier: AppProfile.cursorDefault.bundleIdentifier,
        windowTitle: "Cursor",
        matchedRule: "codex-approval-v1",
        mode: .live,
        action: .pressed,
        confidence: 0.96,
        commandPreview: "$ swift test",
        dedupeKey: "key-\(timestamp)"
    )
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentAutoAcceptTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func appendText(_ text: String, to url: URL) throws {
    guard let data = text.data(using: .utf8) else {
        return
    }

    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.close()
}

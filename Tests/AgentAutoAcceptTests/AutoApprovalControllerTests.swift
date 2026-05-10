import AgentAutoAcceptCore
import Foundation

func runAutoApprovalControllerTests(_ suite: TestSuite) {
    suite.run("dry run logs without pressing") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .dryRun, auditSink: sink, cooldown: 10)
        let candidate = makeCandidate(button: button)

        let decision = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))

        suite.expect(decision == .dryRunLogged, "dry run decision should be logged")
        suite.expect(button.pressCount == 0, "dry run must not press the button")
        suite.expect(sink.events.count == 1, "dry run should append one audit event")
        suite.expect(sink.events.first?.action == .detectedDryRun, "dry run audit action should match")
    }

    suite.run("live mode presses candidate button") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .live, auditSink: sink, cooldown: 10)
        let candidate = makeCandidate(button: button)

        let decision = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))

        suite.expect(decision == .pressed(true), "live mode should report a successful press")
        suite.expect(button.pressCount == 1, "live mode should press exactly once")
        suite.expect(sink.events.first?.action == .pressed, "live mode audit action should be pressed")
    }

    suite.run("paused mode logs without pressing") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .paused, auditSink: sink, cooldown: 10)
        let candidate = makeCandidate(button: button)

        let decision = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))

        suite.expect(decision == .ignoredPaused, "paused mode should report ignoredPaused")
        suite.expect(button.pressCount == 0, "paused mode must not press")
        suite.expect(sink.events.count == 1, "paused mode should still audit the ignored detection")
        suite.expect(sink.events.first?.action == .ignoredPaused, "paused audit action should match")
    }

    suite.run("live mode missing button audits press failure") {
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .live, auditSink: sink, cooldown: 10)
        let candidate = makeCandidate(button: nil)

        let decision = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))

        suite.expect(decision == .missingButton, "missing button should be reported")
        suite.expect(sink.events.count == 1, "missing button should write an audit event")
        suite.expect(sink.events.first?.action == .pressFailed, "missing button should be audited as pressFailed")
    }

    suite.run("audit sink failures are surfaced") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let controller = AutoApprovalController(mode: .dryRun, auditSink: ThrowingAuditSink())
        let candidate = makeCandidate(button: button)

        let decision = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))

        guard case .auditFailed(let message) = decision else {
            suite.expect(false, "audit failure should return auditFailed")
            return
        }

        suite.expect(message.contains("synthetic audit failure"), "audit failure should include the thrown error")
        suite.expect(button.pressCount == 0, "dry run should still avoid pressing when audit fails")
    }

    suite.run("dedupe cooldown skips repeated candidate") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .live, auditSink: sink, cooldown: 10)
        let candidate = makeCandidate(button: button)

        let first = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))
        let second = controller.handle(candidate, now: Date(timeIntervalSince1970: 105))
        let third = controller.handle(candidate, now: Date(timeIntervalSince1970: 111))

        suite.expect(first == .pressed(true), "first decision should press")
        suite.expect(second == .duplicate, "second decision should be deduped")
        suite.expect(third == .pressed(true), "third decision should press after cooldown")
        suite.expect(button.pressCount == 2, "button should be pressed twice")
        suite.expect(sink.events.count == 2, "duplicate should not write an audit event")
    }

    suite.run("live mode retries a stuck prompt after short cooldown") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .live, auditSink: sink)
        let candidate = makeCandidate(button: button)

        let first = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))
        let second = controller.handle(candidate, now: Date(timeIntervalSince1970: 105))
        let third = controller.handle(candidate, now: Date(timeIntervalSince1970: 111))

        suite.expect(first == .pressed(true), "first decision should press")
        suite.expect(second == .duplicate, "same prompt should not be pressed repeatedly within the short live cooldown")
        suite.expect(third == .pressed(true), "same prompt should be retried if it remains after the live cooldown")
        suite.expect(button.pressCount == 2, "live retry cooldown should allow a second press")
    }

    suite.run("monitor mode keeps default long dedupe cooldown") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .dryRun, auditSink: sink)
        let candidate = makeCandidate(button: button)

        let first = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))
        let second = controller.handle(candidate, now: Date(timeIntervalSince1970: 250))
        let third = controller.handle(candidate, now: Date(timeIntervalSince1970: 401))

        suite.expect(first == .dryRunLogged, "first monitor decision should log")
        suite.expect(second == .duplicate, "monitor should avoid duplicate log spam before five minutes")
        suite.expect(third == .dryRunLogged, "monitor should log again after default cooldown")
        suite.expect(button.pressCount == 0, "monitor mode must never press")
    }

    suite.run("reset dedupe lets live press after monitor detection") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .dryRun, auditSink: sink)
        let candidate = makeCandidate(button: button)

        let monitor = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))
        controller.mode = .live
        controller.resetDedupe()
        let live = controller.handle(candidate, now: Date(timeIntervalSince1970: 101))

        suite.expect(monitor == .dryRunLogged, "monitor should log the candidate")
        suite.expect(live == .pressed(true), "live should press immediately after dedupe reset")
        suite.expect(button.pressCount == 1, "live should not be blocked by monitor dedupe")
    }

    suite.run("cursor live uses targeted mouse click only when mouse fallback is allowed") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .live, auditSink: sink)
        let candidate = makeCandidate(
            bundleIdentifier: AppProfile.cursorDefault.bundleIdentifier,
            button: button,
            allowsMouseFallback: true
        )

        let decision = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))

        suite.expect(decision == .pressed(true), "cursor live should report a successful action")
        suite.expect(button.mouseClickCount == 1, "cursor live should use the targeted click path")
        suite.expect(button.pressCount == 0, "cursor live should not AXPress when the mouse click succeeds")
    }

    suite.run("cursor live falls back to AXPress when allowed targeted click is unavailable") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        button.mouseClickResult = false
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .live, auditSink: sink)
        let candidate = makeCandidate(
            bundleIdentifier: AppProfile.cursorDefault.bundleIdentifier,
            button: button,
            allowsMouseFallback: true
        )

        let decision = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))

        suite.expect(decision == .pressed(true), "cursor live should fall back to AXPress")
        suite.expect(button.mouseClickCount == 1, "cursor live should try targeted click first")
        suite.expect(button.pressCount == 1, "cursor live should AXPress after a failed targeted click")
    }

    suite.run("cursor background live uses AXPress without mouse fallback") {
        let button = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let sink = RecordingAuditSink()
        let controller = AutoApprovalController(mode: .live, auditSink: sink)
        let candidate = makeCandidate(
            bundleIdentifier: AppProfile.cursorDefault.bundleIdentifier,
            button: button
        )

        let decision = controller.handle(candidate, now: Date(timeIntervalSince1970: 100))

        suite.expect(decision == .pressed(true), "cursor background live should still try AXPress")
        suite.expect(button.mouseClickCount == 0, "cursor background live must not post a mouse click")
        suite.expect(button.pressCount == 1, "cursor background live should press through Accessibility")
    }
}

private func makeCandidate(
    bundleIdentifier: String = "com.openai.codex",
    button: FakeAccessibilityElement?,
    allowsMouseFallback: Bool = false
) -> ApprovalCandidate {
    ApprovalCandidate(
        appName: "Codex",
        bundleIdentifier: bundleIdentifier,
        windowTitle: "Test",
        matchedRuleID: "codex-approval-v1",
        commandPreview: "$ swift test",
        confidence: 0.96,
        dedupeKey: "candidate-key",
        button: button,
        allowsMouseFallback: allowsMouseFallback
    )
}

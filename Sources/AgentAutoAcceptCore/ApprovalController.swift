import Foundation

public enum ApprovalDecision: Equatable {
    case ignoredPaused
    case duplicate
    case dryRunLogged
    case pressed(Bool)
    case missingButton
    case auditFailed(String)
}

public final class AutoApprovalController {
    public var mode: AutoAcceptMode

    private var dedupe: DedupeCache
    private let auditSink: any AuditSink
    private let liveRetryCooldown: TimeInterval

    public init(
        mode: AutoAcceptMode = .dryRun,
        auditSink: any AuditSink,
        cooldown: TimeInterval = 300,
        liveRetryCooldown: TimeInterval = 10
    ) {
        self.mode = mode
        self.auditSink = auditSink
        self.dedupe = DedupeCache(cooldown: cooldown)
        self.liveRetryCooldown = liveRetryCooldown
    }

    @discardableResult
    public func handle(_ candidate: ApprovalCandidate, now: Date = Date()) -> ApprovalDecision {
        let cooldownOverride = mode == .live ? liveRetryCooldown : nil
        guard dedupe.shouldProcess(candidate.dedupeKey, now: now, cooldownOverride: cooldownOverride) else {
            return .duplicate
        }

        let action: AuditAction
        let decision: ApprovalDecision

        switch mode {
        case .paused:
            action = .ignoredPaused
            decision = .ignoredPaused
        case .dryRun:
            action = .detectedDryRun
            decision = .dryRunLogged
        case .live:
            guard let button = candidate.button else {
                action = .pressFailed
                decision = .missingButton
                return appendEvent(for: candidate, action: action, mode: mode, now: now, fallback: decision)
            }

            let didPress = performLiveAction(on: button, for: candidate)
            action = didPress ? .pressed : .pressFailed
            decision = .pressed(didPress)
        }

        return appendEvent(for: candidate, action: action, mode: mode, now: now, fallback: decision)
    }

    public func resetDedupe() {
        dedupe.removeAll()
    }

    private func performLiveAction(
        on button: any AccessibilityElement,
        for candidate: ApprovalCandidate
    ) -> Bool {
        let isCursor = candidate.bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(AppProfile.cursorDefault.bundleIdentifier) == .orderedSame

        if isCursor, candidate.allowsMouseFallback, let clickable = button as? any MouseClickableAccessibilityElement {
            return clickable.performMouseClick() || button.performPress()
        }

        return button.performPress()
    }

    private func appendEvent(
        for candidate: ApprovalCandidate,
        action: AuditAction,
        mode: AutoAcceptMode,
        now: Date,
        fallback: ApprovalDecision
    ) -> ApprovalDecision {
        let event = AuditEvent(
            timestamp: now,
            appName: candidate.appName,
            bundleIdentifier: candidate.bundleIdentifier,
            windowTitle: candidate.windowTitle,
            matchedRule: candidate.matchedRuleID,
            mode: mode,
            action: action,
            confidence: candidate.confidence,
            commandPreview: candidate.commandPreview,
            dedupeKey: candidate.dedupeKey
        )

        do {
            try auditSink.append(event)
            return fallback
        } catch {
            return .auditFailed(error.localizedDescription)
        }
    }
}

import Foundation

public struct PromptDetector {
    private let maxNodes: Int
    private let maxDepth: Int

    public init(maxNodes: Int = 2_000, maxDepth: Int = 24) {
        self.maxNodes = maxNodes
        self.maxDepth = maxDepth
    }

    public func candidates(
        in root: any AccessibilityElement,
        app: RunningAppInfo,
        windowTitle: String,
        profile: AppProfile,
        allowsMouseFallback: Bool = false
    ) -> [ApprovalCandidate] {
        let nodes = flatten(root)
        guard !nodes.isEmpty else {
            return []
        }

        return candidates(
            inNodes: nodes,
            app: app,
            windowTitle: windowTitle,
            profile: profile,
            includeChildButtonLabels: true,
            allowsMouseFallback: allowsMouseFallback
        )
    }

    public func candidates(
        inFlat nodes: [any AccessibilityElement],
        app: RunningAppInfo,
        windowTitle: String,
        profile: AppProfile,
        allowsMouseFallback: Bool = false
    ) -> [ApprovalCandidate] {
        candidates(
            inNodes: nodes,
            app: app,
            windowTitle: windowTitle,
            profile: profile,
            includeChildButtonLabels: false,
            allowsMouseFallback: allowsMouseFallback
        )
    }

    private func candidates(
        inNodes nodes: [any AccessibilityElement],
        app: RunningAppInfo,
        windowTitle: String,
        profile: AppProfile,
        includeChildButtonLabels: Bool,
        allowsMouseFallback: Bool
    ) -> [ApprovalCandidate] {
        guard !nodes.isEmpty else {
            return []
        }

        let fragments = textFragments(from: nodes)
        let contextText = fragments.joined(separator: " ")
        let normalizedContext = TextNormalizer.normalizedText(contextText)

        return profile.rules.flatMap { rule in
            candidates(
                for: rule,
                nodes: nodes,
                normalizedContext: normalizedContext,
                fragments: fragments,
                app: app,
                windowTitle: windowTitle,
                includeChildButtonLabels: includeChildButtonLabels,
                allowsMouseFallback: allowsMouseFallback
            )
        }
    }

    public func debugSnapshot(
        in root: any AccessibilityElement,
        profile: AppProfile
    ) -> DetectionDebugSnapshot {
        let nodes = flatten(root)
        return debugSnapshot(inFlat: nodes, profile: profile, includeChildButtonLabels: true)
    }

    public func debugSnapshot(
        inFlat nodes: [any AccessibilityElement],
        profile: AppProfile
    ) -> DetectionDebugSnapshot {
        debugSnapshot(inFlat: nodes, profile: profile, includeChildButtonLabels: false)
    }

    private func debugSnapshot(
        inFlat nodes: [any AccessibilityElement],
        profile: AppProfile,
        includeChildButtonLabels: Bool
    ) -> DetectionDebugSnapshot {
        let fragments = textFragments(from: nodes)
        let normalizedContext = TextNormalizer.normalizedText(fragments.joined(separator: " "))

        let labelsForButtons = nodes
            .filter(isButton)
            .flatMap { buttonLabels(for: $0, includeChildren: includeChildButtonLabels) }
            .map(TextNormalizer.normalizedPreviewText)
            .filter { !$0.isEmpty }

        let runButtonLabels = labelsForButtons.filter(TextNormalizer.isRunButtonLabel)
        let hasSkip = normalizedContext.contains("skip")
        let hasAutoRunSandbox = containsApprovalModeCue(normalizedContext)
        let hasShellCue = containsShellCue(normalizedContext)

        return DetectionDebugSnapshot(
            profileName: profile.displayName,
            nodeCount: nodes.count,
            fragmentCount: fragments.count,
            buttonLabels: Array(labelsForButtons.prefix(16)),
            runButtonLabels: Array(runButtonLabels.prefix(8)),
            hasSkip: hasSkip,
            hasAutoRunSandbox: hasAutoRunSandbox,
            hasShellCue: hasShellCue,
            commandPreview: TextNormalizer.commandPreview(from: fragments, limit: 180)
        )
    }

    private func candidates(
        for rule: DetectionRule,
        nodes: [any AccessibilityElement],
        normalizedContext: String,
        fragments: [String],
        app: RunningAppInfo,
        windowTitle: String,
        includeChildButtonLabels: Bool,
        allowsMouseFallback: Bool
    ) -> [ApprovalCandidate] {
        switch rule.kind {
        case .codexApprovalV1:
            guard codexContextMatches(normalizedContext) else {
                return []
            }

            let runButtons = nodes.filter { node in
                isButton(node) && buttonLabels(for: node, includeChildren: includeChildButtonLabels).contains { label in
                    TextNormalizer.isRunButtonLabel(label)
                }
            }

            guard !runButtons.isEmpty else {
                return []
            }

            let preview = TextNormalizer.commandPreview(from: fragments)
            let key = dedupeKey(
                app: app,
                windowTitle: windowTitle,
                ruleID: rule.id,
                signature: TextNormalizer.promptDedupeSignature(from: fragments)
            )

            return runButtons.map { button in
                ApprovalCandidate(
                    appName: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    windowTitle: windowTitle,
                    matchedRuleID: rule.id,
                    commandPreview: preview,
                    confidence: confidence(for: normalizedContext),
                    dedupeKey: key,
                    button: button,
                    allowsMouseFallback: allowsMouseFallback
                )
            }
        }
    }

    private func flatten(_ root: any AccessibilityElement) -> [any AccessibilityElement] {
        var output: [any AccessibilityElement] = []
        var queue: [(any AccessibilityElement, Int)] = [(root, 0)]
        var seen = Set<Int>()
        var index = 0

        while index < queue.count, output.count < maxNodes {
            let (node, depth) = queue[index]
            index += 1

            guard seen.insert(node.accessibilityIdentity).inserted else {
                continue
            }

            output.append(node)

            guard depth < maxDepth else {
                continue
            }

            queue.append(contentsOf: node.children.map { ($0, depth + 1) })
        }

        return output
    }

    private func textFragments(from nodes: [any AccessibilityElement]) -> [String] {
        nodes.flatMap(labels(for:))
    }

    private func labels(for node: any AccessibilityElement) -> [String] {
        rawLabels(for: node)
    }

    private func buttonLabels(for node: any AccessibilityElement, includeChildren: Bool) -> [String] {
        if includeChildren {
            return rawLabels(for: node) + node.children.flatMap(rawLabels(for:))
        }

        return rawLabels(for: node)
    }

    private func rawLabels(for node: any AccessibilityElement) -> [String] {
        [node.title, node.valueText, node.descriptionText, node.identifier]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isButton(_ node: any AccessibilityElement) -> Bool {
        if node.canPress {
            return true
        }

        let roleText = [node.role, node.roleDescription]
            .compactMap { $0 }
            .joined(separator: " ")
        let normalizedRole = TextNormalizer.normalizedText(roleText)

        return normalizedRole == "axbutton" || normalizedRole == "button" || normalizedRole.contains("button")
    }

    private func codexContextMatches(_ normalizedContext: String) -> Bool {
        let hasSkip = normalizedContext.contains("skip")
        let hasAutoRunSandbox = containsApprovalModeCue(normalizedContext)
        let hasShellCue = containsShellCue(normalizedContext)

        return [hasSkip, hasAutoRunSandbox, hasShellCue].filter { $0 }.count >= 2
    }

    private func confidence(for normalizedContext: String) -> Double {
        let features = [
            normalizedContext.contains("skip"),
            containsApprovalModeCue(normalizedContext),
            containsShellCue(normalizedContext)
        ]

        let score = features.filter { $0 }.count
        switch score {
        case 3:
            return 0.96
        case 2:
            return 0.84
        default:
            return 0.0
        }
    }

    private func containsShellCue(_ normalizedContext: String) -> Bool {
        let cues = [
            "$ ",
            " && ",
            "source ",
            " python ",
            "python -m",
            "pytest ",
            "npm ",
            "pnpm ",
            "yarn ",
            "cargo ",
            "swift ",
            "git "
        ]

        return cues.contains { normalizedContext.contains($0) }
    }

    private func containsApprovalModeCue(_ normalizedContext: String) -> Bool {
        let cues = [
            "auto-run in sandbox",
            "auto run in sandbox",
            "autorun mode",
            "shell command options"
        ]

        return cues.contains { normalizedContext.contains($0) }
    }

    private func dedupeKey(
        app: RunningAppInfo,
        windowTitle: String,
        ruleID: String,
        signature: String
    ) -> String {
        [
            app.bundleIdentifier.isEmpty ? app.name : app.bundleIdentifier,
            windowTitle,
            ruleID,
            TextNormalizer.stableFingerprint(signature)
        ]
        .joined(separator: "|")
    }
}

public struct DetectionDebugSnapshot: Equatable {
    public var profileName: String
    public var nodeCount: Int
    public var fragmentCount: Int
    public var buttonLabels: [String]
    public var runButtonLabels: [String]
    public var hasSkip: Bool
    public var hasAutoRunSandbox: Bool
    public var hasShellCue: Bool
    public var commandPreview: String

    public var compactDescription: String {
        let buttons = buttonLabels.isEmpty ? "none" : buttonLabels.joined(separator: " | ")
        let runButtons = runButtonLabels.isEmpty ? "none" : runButtonLabels.joined(separator: " | ")
        return "profile=\(profileName) nodes=\(nodeCount) fragments=\(fragmentCount) buttons=[\(buttons)] runButtons=[\(runButtons)] skip=\(hasSkip) sandbox=\(hasAutoRunSandbox) shell=\(hasShellCue) preview=\(commandPreview)"
    }
}

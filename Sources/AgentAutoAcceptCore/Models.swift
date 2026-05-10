import Foundation

public enum AutoAcceptMode: String, Codable, CaseIterable, Identifiable {
    case dryRun
    case live
    case paused

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .dryRun:
            return "Monitor"
        case .live:
            return "Live"
        case .paused:
            return "Paused"
        }
    }

    public var shortStatus: String {
        switch self {
        case .dryRun:
            return "AA Monitor"
        case .live:
            return "AA Live"
        case .paused:
            return "AA Off"
        }
    }
}

public struct RunningAppInfo: Codable, Equatable {
    public var name: String
    public var bundleIdentifier: String
    public var processIdentifier: pid_t

    public init(name: String, bundleIdentifier: String, processIdentifier: pid_t) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public struct AppProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var displayName: String
    public var bundleIdentifier: String
    public var appNameHints: [String]
    public var isEnabled: Bool
    public var rules: [DetectionRule]

    public init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String,
        appNameHints: [String] = [],
        isEnabled: Bool = true,
        rules: [DetectionRule]
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appNameHints = appNameHints
        self.isEnabled = isEnabled
        self.rules = rules
    }

    public func matches(_ app: RunningAppInfo) -> Bool {
        let wantedBundleID = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let actualBundleID = app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !wantedBundleID.isEmpty {
            return wantedBundleID == actualBundleID
        }

        let actualName = app.name.lowercased()
        return appNameHints.contains { hint in
            let normalizedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalizedHint.isEmpty && actualName.contains(normalizedHint)
        }
    }

    public static var codexDefault: AppProfile {
        AppProfile(
            id: UUID(uuidString: "A5034D6E-5848-4B8D-8D83-843E68842770")!,
            displayName: "Codex",
            bundleIdentifier: "com.openai.codex",
            appNameHints: ["Codex"],
            rules: [.codexApprovalV1]
        )
    }

    public static var cursorDefault: AppProfile {
        AppProfile(
            id: UUID(uuidString: "F4461671-EC34-4CE7-B6FA-2352BD121C91")!,
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            appNameHints: ["Cursor"],
            rules: [.codexApprovalV1]
        )
    }

    public static var bundledDefaults: [AppProfile] {
        [.codexDefault, .cursorDefault]
    }
}

public struct DetectionRule: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case codexApprovalV1
    }

    public var id: String
    public var kind: Kind
    public var runButtonLabels: [String]

    public init(id: String, kind: Kind, runButtonLabels: [String]) {
        self.id = id
        self.kind = kind
        self.runButtonLabels = runButtonLabels
    }

    public static var codexApprovalV1: DetectionRule {
        DetectionRule(
            id: "codex-approval-v1",
            kind: .codexApprovalV1,
            runButtonLabels: ["Run"]
        )
    }
}

public struct ApprovalCandidate {
    public var appName: String
    public var bundleIdentifier: String
    public var windowTitle: String
    public var matchedRuleID: String
    public var commandPreview: String
    public var confidence: Double
    public var dedupeKey: String
    public var button: (any AccessibilityElement)?
    public var allowsMouseFallback: Bool

    public init(
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        matchedRuleID: String,
        commandPreview: String,
        confidence: Double,
        dedupeKey: String,
        button: (any AccessibilityElement)?,
        allowsMouseFallback: Bool = false
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.matchedRuleID = matchedRuleID
        self.commandPreview = commandPreview
        self.confidence = confidence
        self.dedupeKey = dedupeKey
        self.button = button
        self.allowsMouseFallback = allowsMouseFallback
    }
}

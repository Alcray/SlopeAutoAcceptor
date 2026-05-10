import AgentAutoAcceptCore
import AppKit

final class AppScanner {
    private let settings: SettingsStore
    private let controller: AutoApprovalController
    private let detector = PromptDetector()
    private let backgroundDetector = PromptDetector(maxNodes: 1_000, maxDepth: 18)
    private let diagnostics = DiagnosticsLog()
    private let scanQueue = DispatchQueue(label: "dev.agentautoaccept.scanner", qos: .utility)
    private var timer: Timer?
    private var scanCount = 0
    private var isScanInProgress = false

    init(settings: SettingsStore, controller: AutoApprovalController) {
        self.settings = settings
        self.controller = controller
    }

    func start() {
        stop()
        diagnostics.append("scanner started")
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scheduleScan()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        scheduleScan()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleScan() {
        guard !isScanInProgress else {
            return
        }

        isScanInProgress = true
        scanQueue.async { [weak self] in
            self?.scan()
            DispatchQueue.main.async {
                self?.isScanInProgress = false
            }
        }
    }

    private func scan() {
        scanCount += 1
        let shouldTraceScan = scanCount <= 5

        guard AXIsProcessTrusted() else {
            if shouldTraceScan || scanCount.isMultiple(of: 30) {
                diagnostics.append("scan \(scanCount): accessibility not trusted")
            }
            return
        }

        guard settings.mode != .paused else {
            if shouldTraceScan {
                diagnostics.append("scan \(scanCount): paused")
            }
            return
        }

        let profiles = settings.profiles.filter(\.isEnabled)
        guard !profiles.isEmpty else {
            diagnostics.append("scan \(scanCount): no enabled profiles")
            return
        }

        var matchedApps = 0
        var matchedWindows = 0
        var matchedCandidates = 0

        for runningApp in NSWorkspace.shared.runningApplications {
            guard runningApp.processIdentifier != getpid() else {
                continue
            }

            let appInfo = RunningAppInfo(
                name: runningApp.localizedName ?? runningApp.bundleIdentifier ?? "Unknown App",
                bundleIdentifier: runningApp.bundleIdentifier ?? "",
                processIdentifier: runningApp.processIdentifier
            )

            let matchingProfiles = profiles.filter { $0.matches(appInfo) }
            guard !matchingProfiles.isEmpty else {
                continue
            }

            if shouldTraceScan {
                diagnostics.append("scan \(scanCount): matched app \(appInfo.name) bundle=\(appInfo.bundleIdentifier) pid=\(appInfo.processIdentifier)")
            }

            matchedApps += 1
            var matchedCandidatesForApp = 0
            let shouldTraceMiss = shouldTraceScan || scanCount.isMultiple(of: 30)

            let windows = SystemAccessibilityElement.windows(forPID: runningApp.processIdentifier)
            matchedWindows += windows.count
            for profile in matchingProfiles {
                for window in windows {
                    matchedCandidatesForApp += scan(
                        root: window,
                        rootKind: "background-ax-window",
                        detector: backgroundDetector,
                        app: appInfo,
                        windowTitle: window.title ?? appInfo.name,
                        profile: profile,
                        forceSnapshot: false,
                        allowsMouseFallback: false
                    )
                }
            }

            if matchedCandidatesForApp == 0 {
                let sampledElements = SystemAccessibilityElement.sampledVisibleElements(forPID: runningApp.processIdentifier)
                matchedWindows += sampledElements.count

                for profile in matchingProfiles {
                    matchedCandidatesForApp += scanFlat(
                        nodes: sampledElements,
                        rootKind: runningApp.isActive ? "visible-active-ui" : "visible-background-ui",
                        app: appInfo,
                        windowTitle: appInfo.name,
                        profile: profile,
                        forceSnapshot: shouldTraceMiss,
                        allowsMouseFallback: runningApp.isActive
                    )
                }
            }

            if matchedCandidatesForApp == 0 {
                if shouldTraceMiss {
                    diagnostics.append("scan \(scanCount): no prompt in background AX or visible UI for \(appInfo.name)")
                }
            } else if shouldTraceScan {
                diagnostics.append("scan \(scanCount): found \(matchedCandidatesForApp) prompt candidate(s) for \(appInfo.name)")
            }

            matchedCandidates += matchedCandidatesForApp
        }

        if scanCount <= 5 || matchedCandidates > 0 {
            diagnostics.append("scan \(scanCount): profiles=\(profiles.map(\.displayName).joined(separator: ",")) apps=\(matchedApps) windows=\(matchedWindows) candidates=\(matchedCandidates)")
        }
    }

    private func scan(
        root: SystemAccessibilityElement,
        rootKind: String,
        detector: PromptDetector,
        app: RunningAppInfo,
        windowTitle: String,
        profile: AppProfile,
        forceSnapshot: Bool = false,
        allowsMouseFallback: Bool = false
    ) -> Int {
        let candidates = detector.candidates(
            in: root,
            app: app,
            windowTitle: windowTitle,
            profile: profile,
            allowsMouseFallback: allowsMouseFallback
        )

        if !candidates.isEmpty || forceSnapshot {
            let snapshot = detector.debugSnapshot(in: root, profile: profile)
            diagnostics.append("\(rootKind): app=\(app.name) bundle=\(app.bundleIdentifier) title=\(windowTitle) mouseFallback=\(allowsMouseFallback) \(snapshot.compactDescription)")
        }

        for candidate in candidates {
            diagnostics.append("candidate: \(candidate.appName) \(candidate.windowTitle) \(candidate.commandPreview)")
            let decision = controller.handle(candidate)
            diagnostics.append("decision: \(decision)")
        }

        return candidates.count
    }

    private func scanFlat(
        nodes: [SystemAccessibilityElement],
        rootKind: String,
        app: RunningAppInfo,
        windowTitle: String,
        profile: AppProfile,
        forceSnapshot: Bool = false,
        allowsMouseFallback: Bool = false
    ) -> Int {
        let candidates = detector.candidates(
            inFlat: nodes,
            app: app,
            windowTitle: windowTitle,
            profile: profile,
            allowsMouseFallback: allowsMouseFallback
        )

        if !candidates.isEmpty || forceSnapshot {
            let snapshot = detector.debugSnapshot(inFlat: nodes, profile: profile)
            diagnostics.append("\(rootKind): app=\(app.name) bundle=\(app.bundleIdentifier) title=\(windowTitle) mouseFallback=\(allowsMouseFallback) \(snapshot.compactDescription)")
        }

        for candidate in candidates {
            diagnostics.append("candidate: \(candidate.appName) \(candidate.windowTitle) \(candidate.commandPreview)")
            let decision = controller.handle(candidate)
            diagnostics.append("decision: \(decision)")
        }

        return candidates.count
    }
}

private final class DiagnosticsLog {
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("AgentAutoAccept", isDirectory: true)

        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("diagnostics.log")
    }

    func append(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }

        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    }
}

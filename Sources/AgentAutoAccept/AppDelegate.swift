import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = VisionSettingsStore()
    private let activityLogStore = ActivityLogStore()
    private var settings: VisionAutomationSettings
    private let automationEngine = VisionAutomationEngine()
    private let autoRegionPicker = AutoRegionPickerService()
    private let regionSelector = ScreenRegionSelector()
    private let regionHighlighter = ScreenRegionHighlighter()
    private let updateChecker = GitHubReleaseUpdateChecker()

    private var statusItem: NSStatusItem?
    private var controlWindow: ControlWindowController?
    private var recentWindow: TextWindowController?
    private var testingGroundWindow: TestingGroundWindowController?
    private var recentEvents: [String] = []
    private var isRunInProgress = false
    private var isAutoPickingRegion = false
    private var isCheckingForUpdates = false

    override init() {
        settings = settingsStore.load()
        super.init()
        wireEngineCallbacks()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateDuplicateCopies()
        NSApp.setActivationPolicy(.regular)
        let restoredLiveMode = settings.mode == .live
        if restoredLiveMode {
            settings.mode = .paused
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        migrateCaptureRegionIfNeeded()
        persistSettings()
        automationEngine.apply(settings: settings)
        rebuildMenu()
        updateControlWindow()
        showControlWindow()

        appendEvent(startupStatusText())
        if restoredLiveMode {
            appendEvent("Started paused instead of restoring Live mode.")
        }
        appendEvent("Controls ready: Pick Region, Auto Region (Beta), Show Region, Test Ground, Run Once, Run Tabs.")
        checkForUpdates(isAutomatic: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        automationEngine.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlWindow()
        return true
    }

    @objc private func showControlWindow() {
        let controller = controlWindow ?? makeControlWindow()
        controlWindow = controller
        updateControlWindow()
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    @objc private func pickRegion() {
        NSApp.activate(ignoringOtherApps: true)
        regionSelector.beginSelection { [weak self] selectedAppKitRect in
            guard let self else {
                return
            }

            guard let selectedAppKitRect else {
                self.appendEvent("Region selection cancelled.")
                return
            }

            let quartzRect = DisplayCoordinateSpace.appKitToQuartz(rect: selectedAppKitRect)
            self.settings.captureRegionQuartz = quartzRect
            self.persistSettings()
            self.automationEngine.apply(settings: self.settings)
            self.appendEvent("Region selected: \(self.regionDescription()).")
            self.refreshUI()
        }
    }

    @objc private func autoPickRegion() {
        guard !isAutoPickingRegion else {
            appendEvent("Auto-region pick already in progress.")
            return
        }

        let snapshot = settings
        isAutoPickingRegion = true
        appendEvent("Auto-region pick requested with Ollama model \(snapshot.autoRegionModel) at \(snapshot.autoRegionURL).")
        appendEvent("Temporarily hiding Vision Clicker control/activity windows before full-screen VLM capture.")
        refreshUI()

        let shouldRestoreControlWindow = controlWindow?.window?.isVisible == true
        let shouldRestoreActivityWindow = recentWindow?.window?.isVisible == true
        controlWindow?.window?.orderOut(nil)
        recentWindow?.window?.orderOut(nil)

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                let result = try await self.autoRegionPicker.pickRegion(settings: snapshot)
                await MainActor.run {
                    self.finishAutoRegionPick(
                        result: .success(result),
                        shouldRestoreControlWindow: shouldRestoreControlWindow,
                        shouldRestoreActivityWindow: shouldRestoreActivityWindow
                    )
                }
            } catch {
                await MainActor.run {
                    self.finishAutoRegionPick(
                        result: .failure(error),
                        shouldRestoreControlWindow: shouldRestoreControlWindow,
                        shouldRestoreActivityWindow: shouldRestoreActivityWindow
                    )
                }
            }
        }
    }

    @objc private func showRegion() {
        guard let quartzRect = settings.captureRegionQuartz else {
            appendEvent("No region selected yet.")
            refreshUI()
            return
        }

        let appKitRect = DisplayCoordinateSpace.quartzToAppKit(
            rect: DisplayCoordinateSpace.normalizedQuartz(rect: quartzRect)
        ).standardized
        regionHighlighter.show(appKitRect: appKitRect)
        appendEvent("Showing selected region: \(regionDescription()).")
        refreshUI()
    }

    @objc private func showTestingGround() {
        let controller = testingGroundWindow ?? TestingGroundWindowController()
        testingGroundWindow = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        appendEvent("Testing Ground opened with mock agent approval buttons.")
    }

    @objc private func toggleLiveMode() {
        setMode(settings.mode == .live ? .paused : .live)
    }

    @objc private func setLiveMode() {
        setMode(.live)
    }

    @objc private func setPausedMode() {
        setMode(.paused)
    }

    @objc private func runOnce() {
        appendEvent("Run Once requested for target labels: \(settings.targetLabel).")
        automationEngine.triggerManualRun()
    }

    @objc private func runCursorTabs() {
        guard settings.isCursorTabSwitchingEnabled else {
            appendEvent("Cursor tab sweep is off. Turn on Change Cursor Tabs before running a sweep.")
            refreshUI()
            return
        }

        appendEvent("Cursor tab sweep requested for target labels: \(settings.targetLabel), \(settings.cursorTabCount) tab\(settings.cursorTabCount == 1 ? "" : "s").")
        automationEngine.triggerCursorTabSweep()
    }

    @objc private func requestAccessibilityPermission() {
        MousePermission.request()
        appendEvent("Requested Accessibility permission. If macOS changed the permission, restart Vision Clicker.")
        refreshUI()
    }

    @objc private func requestScreenCapturePermission() {
        _ = ScreenCapturePermission.request()
        appendEvent("Requested Screen Recording permission. If macOS changed the permission, restart Vision Clicker.")
        refreshUI()
    }

    @objc private func showActivityLog() {
        let lines = activityLogStore.recentLines(limit: 220)
        let text = lines.isEmpty ? "No activity yet." : lines.joined(separator: "\n\n")
        showTextWindow(title: "Vision Clicker Activity", text: text)
    }

    @objc private func checkForUpdatesFromMenu() {
        checkForUpdates(isAutomatic: false)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setMode(_ mode: AutomationMode) {
        guard mode != settings.mode else {
            return
        }

        if mode == .live && !confirmLiveMode() {
            refreshUI()
            return
        }

        settings.mode = mode
        persistSettings()
        automationEngine.apply(settings: settings)
        appendEvent(modeChangeText(mode))
        if mode == .paused {
            appendEvent("Active automation run cancelled.")
        }
        refreshUI()
    }

    private func updateInputs(_ inputs: ControlWindowController.Inputs) {
        let cleanedTarget = TargetLabelParser.canonicalText(from: inputs.targetLabel)

        settings.targetLabel = cleanedTarget
        settings.pollingInterval = max(0.75, inputs.pollingInterval)
        settings.confidenceThreshold = min(max(inputs.confidenceThreshold, 0), 1)
        settings.isCursorTabSwitchingEnabled = inputs.isCursorTabSwitchingEnabled
        settings.cursorTabCount = min(max(inputs.cursorTabCount, 1), 40)
        settings.cursorTabChangeInterval = min(max(inputs.cursorTabChangeInterval, 0.05), 5.0)
        settings.autoRegionModel = inputs.autoRegionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "moondream" : inputs.autoRegionModel
        settings.autoRegionURL = inputs.autoRegionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "http://localhost:11434" : inputs.autoRegionURL

        persistSettings()
        automationEngine.apply(settings: settings)
        refreshUI()
    }

    private func persistSettings() {
        settingsStore.save(settings)
    }

    private func migrateCaptureRegionIfNeeded() {
        guard let storedRegion = settings.captureRegionQuartz else {
            return
        }

        guard !DisplayCoordinateSpace.isQuartzRectOnAnyDisplay(storedRegion) else {
            return
        }

        settings.captureRegionQuartz = DisplayCoordinateSpace.normalizedQuartz(rect: storedRegion)
        persistSettings()
        appendEvent("Updated selected region for current display layout.")
    }

    private func wireEngineCallbacks() {
        automationEngine.onEvent = { [weak self] message in
            DispatchQueue.main.async {
                self?.appendEvent(message)
                self?.refreshUI()
            }
        }

        automationEngine.onRunningChanged = { [weak self] isRunning in
            DispatchQueue.main.async {
                self?.isRunInProgress = isRunning
                self?.refreshUI()
            }
        }
    }

    private func appendEvent(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp)  \(message)"
        activityLogStore.append(line)
        recentEvents.insert(line, at: 0)
        if recentEvents.count > 180 {
            recentEvents.removeLast()
        }
    }

    private func refreshUI() {
        rebuildMenu()
        updateControlWindow()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(disabledItem("Vision Clicker: \(statusSummaryText())"))
        menu.addItem(disabledItem("Version: \(AppVersion.current.displayText)"))
        let updateItem = actionItem(
            isCheckingForUpdates ? "Checking for Updates..." : "Check for Updates...",
            #selector(checkForUpdatesFromMenu)
        )
        updateItem.isEnabled = !isCheckingForUpdates
        menu.addItem(updateItem)
        menu.addItem(disabledItem("Engine: Apple OCR"))
        menu.addItem(disabledItem("Region: \(regionDescription())"))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Show Control Window", #selector(showControlWindow)))
        menu.addItem(actionItem("Testing Ground", #selector(showTestingGround)))
        menu.addItem(actionItem("Pick Region...", #selector(pickRegion)))
        menu.addItem(actionItem("Auto Pick Region (Beta)", #selector(autoPickRegion)))
        menu.addItem(actionItem("Show Region", #selector(showRegion)))
        menu.addItem(actionItem("Run Once", #selector(runOnce)))
        if settings.isCursorTabSwitchingEnabled {
            menu.addItem(actionItem("Run Cursor Tabs", #selector(runCursorTabs)))
        } else {
            menu.addItem(disabledItem("Run Cursor Tabs (Off)"))
        }
        menu.addItem(actionItem(settings.mode == .live ? "Pause" : "Go Live", #selector(toggleLiveMode)))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Grant Accessibility", #selector(requestAccessibilityPermission)))
        menu.addItem(actionItem("Grant Screen Recording", #selector(requestScreenCapturePermission)))
        menu.addItem(actionItem("Activity Log...", #selector(showActivityLog)))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Quit Vision Clicker", #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
        updateStatusItemButton()
    }

    private func updateStatusItemButton() {
        guard let button = statusItem?.button else {
            return
        }

        let symbolName: String
        switch settings.mode {
        case .live:
            symbolName = isRunInProgress ? "bolt.circle.fill" : "play.circle.fill"
        case .paused:
            symbolName = "pause.circle.fill"
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Vision Clicker")
        button.image?.isTemplate = true
        button.toolTip = "Vision Clicker: \(statusSummaryText())"
        button.setAccessibilityLabel("Vision Clicker \(statusSummaryText())")
    }

    private func updateControlWindow() {
        let state = ControlWindowController.State(
            mode: settings.mode,
            statusText: statusSummaryText(),
            regionText: regionDescription(),
            running: isRunInProgress || isAutoPickingRegion,
            hasAccessibility: MousePermission.hasAccess,
            hasScreenCapture: ScreenCapturePermission.hasAccess,
            targetLabel: settings.targetLabel,
            pollingInterval: settings.pollingInterval,
            confidenceThreshold: settings.confidenceThreshold,
            isCursorTabSwitchingEnabled: settings.isCursorTabSwitchingEnabled,
            cursorTabCount: settings.cursorTabCount,
            cursorTabChangeInterval: settings.cursorTabChangeInterval,
            autoRegionModel: settings.autoRegionModel,
            autoRegionURL: settings.autoRegionURL,
            isAutoPickingRegion: isAutoPickingRegion,
            isCheckingForUpdates: isCheckingForUpdates
        )
        controlWindow?.update(with: state)
    }

    private func makeControlWindow() -> ControlWindowController {
        let controller = ControlWindowController()

        controller.onModeSelected = { [weak self] mode in
            self?.setMode(mode)
        }
        controller.onInputsChanged = { [weak self] inputs in
            self?.updateInputs(inputs)
        }
        controller.onRequestAccessibility = { [weak self] in
            self?.requestAccessibilityPermission()
        }
        controller.onRequestScreenCapture = { [weak self] in
            self?.requestScreenCapturePermission()
        }
        controller.onPickRegion = { [weak self] in
            self?.pickRegion()
        }
        controller.onAutoPickRegion = { [weak self] in
            self?.autoPickRegion()
        }
        controller.onShowRegion = { [weak self] in
            self?.showRegion()
        }
        controller.onRunOnce = { [weak self] in
            self?.runOnce()
        }
        controller.onRunCursorTabs = { [weak self] in
            self?.runCursorTabs()
        }
        controller.onShowTestingGround = { [weak self] in
            self?.showTestingGround()
        }
        controller.onShowActivity = { [weak self] in
            self?.showActivityLog()
        }
        controller.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates(isAutomatic: false)
        }

        return controller
    }

    private func checkForUpdates(isAutomatic: Bool) {
        guard !isCheckingForUpdates else {
            if !isAutomatic {
                appendEvent("Update check already in progress.")
            }
            return
        }

        isCheckingForUpdates = true
        appendEvent(isAutomatic ? "Checking GitHub for updates." : "Manual update check requested.")
        refreshUI()

        let currentVersion = AppVersion.current.version
        Task { [weak self] in
            guard let self else {
                return
            }

            let result: Result<UpdateCheckResult, Error>
            do {
                result = .success(try await self.updateChecker.checkForUpdate(currentVersion: currentVersion))
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                self.finishUpdateCheck(result, isAutomatic: isAutomatic)
            }
        }
    }

    private func finishUpdateCheck(_ result: Result<UpdateCheckResult, Error>, isAutomatic: Bool) {
        isCheckingForUpdates = false

        switch result {
        case let .success(.updateAvailable(update)):
            appendEvent("Update available: \(update.tagName).")
            refreshUI()
            promptForUpdate(update)
        case let .success(.upToDate(latestVersion)):
            appendEvent("No update available. Latest published version: \(latestVersion).")
            refreshUI()
            if !isAutomatic {
                showNoUpdateAlert(latestVersion: latestVersion)
            }
        case .success(.noPublishedVersions):
            appendEvent("No GitHub releases or version tags are published yet.")
            refreshUI()
            if !isAutomatic {
                showNoPublishedVersionsAlert()
            }
        case let .failure(error):
            appendEvent("Update check failed: \(error.localizedDescription)")
            refreshUI()
            if !isAutomatic {
                showUpdateCheckFailedAlert(error)
            }
        }
    }

    private func finishAutoRegionPick(
        result: Result<AutoRegionPickResult, Error>,
        shouldRestoreControlWindow: Bool,
        shouldRestoreActivityWindow: Bool
    ) {
        isAutoPickingRegion = false

        switch result {
        case let .success(pick):
            settings.captureRegionQuartz = pick.quartzRect
            persistSettings()
            automationEngine.apply(settings: settings)

            let confidenceText = pick.confidence.map { String(format: "%.2f", $0) } ?? "unknown"
            appendEvent("Auto-region selected \(regionDescription()) from \(Int(pick.screenshotPixelSize.width))x\(Int(pick.screenshotPixelSize.height)) screenshot.")
            appendEvent("VLM candidate label: \(pick.label ?? "unknown"), confidence: \(confidenceText).\(pick.reason.map { " \($0)" } ?? "")")
            appendEvent("VLM raw response: \(pick.rawResponse)")
            regionHighlighter.show(appKitRect: pick.appKitRect)
        case let .failure(error):
            appendEvent("Auto-region pick failed: \(error.localizedDescription)")
        }

        refreshUI()
        if shouldRestoreControlWindow {
            showControlWindow()
        }
        if shouldRestoreActivityWindow {
            showActivityLog()
        }
    }

    private func promptForUpdate(_ update: AvailableUpdate) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Vision Clicker \(update.tagName) is available"
        alert.informativeText = "You are running \(AppVersion.current.displayText). Open the GitHub release to download the update?"
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")

        guard alert.runModal() == .alertFirstButtonReturn else {
            appendEvent("Update postponed: \(update.tagName).")
            return
        }

        NSWorkspace.shared.open(update.actionURL)
        appendEvent("Opened update URL: \(update.actionURL.absoluteString)")
    }

    private func showNoUpdateAlert(latestVersion: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Vision Clicker is up to date"
        alert.informativeText = "Installed: \(AppVersion.current.displayText)\nLatest published version: \(latestVersion)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showNoPublishedVersionsAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "No published updates yet"
        alert.informativeText = "GitHub does not have a Release or version tag for Vision Clicker yet."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateCheckFailedAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showTextWindow(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let controller = TextWindowController(title: title, text: text)
        recentWindow = controller
        controller.showWindow(nil)
    }

    private func statusSummaryText() -> String {
        if isAutoPickingRegion {
            return "Picking Region"
        }

        switch settings.mode {
        case .paused:
            return "Paused"
        case .live:
            if settings.isCursorTabSwitchingEnabled, settings.cursorTabCount > 1 {
                return isRunInProgress ? "Live (Sweeping Tabs)" : "Live (Tab Sweep Waiting)"
            }

            return isRunInProgress ? "Live (Scanning)" : "Live (Waiting)"
        }
    }

    private func regionDescription() -> String {
        guard let quartzRect = settings.captureRegionQuartz else {
            return "Not selected"
        }

        let appKitRect = DisplayCoordinateSpace.quartzToAppKit(
            rect: DisplayCoordinateSpace.normalizedQuartz(rect: quartzRect)
        ).standardized
        return "x:\(Int(appKitRect.minX)) y:\(Int(appKitRect.minY)) w:\(Int(appKitRect.width)) h:\(Int(appKitRect.height))"
    }

    private func actionItem(
        _ title: String,
        _ selector: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func confirmLiveMode() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Enable Live Mode?"
        alert.informativeText = "Live mode will capture the selected screen region, use on-device Apple OCR to find the target label, click it, then return your cursor."
        alert.addButton(withTitle: "Enable Live")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func startupStatusText() -> String {
        let accessibility = MousePermission.hasAccess ? "granted" : "missing"
        let screenRecording = ScreenCapturePermission.hasAccess ? "granted" : "missing"
        let tabSwitching = settings.isCursorTabSwitchingEnabled ? "on" : "off"
        return "Ready. Version: \(AppVersion.current.detailedText). Mode: \(settings.mode.displayName). Target labels: \(settings.targetLabel). Cursor tab switching: \(tabSwitching). Cursor tabs: \(settings.cursorTabCount). Auto-region model: \(settings.autoRegionModel). Region: \(regionDescription()). Permissions: Accessibility \(accessibility), Screen Recording \(screenRecording)."
    }

    private func modeChangeText(_ mode: AutomationMode) -> String {
        var text = "Mode switched to \(mode.displayName). Target labels: \(settings.targetLabel)."
        if mode == .live, settings.isCursorTabSwitchingEnabled, settings.cursorTabCount > 1 {
            text += " Live tab sweep enabled: \(settings.cursorTabCount) tabs, \(String(format: "%.2f", settings.cursorTabChangeInterval))s tab delay."
        }
        return text
    }

    private func terminateDuplicateCopies() {
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "") {
            guard app.processIdentifier != getpid() else {
                continue
            }

            if app.bundleURL?.standardizedFileURL != currentBundleURL {
                app.terminate()
            }
        }
    }
}

private final class ActivityLogStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.visionclicker.activity-log")

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser

        let directory = supportDirectory.appendingPathComponent("VisionClicker", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("activity.log")
    }

    func append(_ line: String) {
        queue.async { [fileURL] in
            guard let data = "\(line)\n".data(using: .utf8) else {
                return
            }

            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                    return
                }
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    func recentLines(limit: Int) -> [String] {
        queue.sync { [fileURL] in
            guard
                let data = try? Data(contentsOf: fileURL),
                let text = String(data: data, encoding: .utf8)
            else {
                return []
            }

            return text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .suffix(limit)
                .reversed()
                .map(String.init)
        }
    }
}

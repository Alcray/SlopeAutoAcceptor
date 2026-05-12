import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = VisionSettingsStore()
    private let activityLogStore = ActivityLogStore()
    private var settings: VisionAutomationSettings
    private let automationEngine = VisionAutomationEngine()
    private let regionSelector = ScreenRegionSelector()
    private let regionHighlighter = ScreenRegionHighlighter()

    private var statusItem: NSStatusItem?
    private var controlWindow: ControlWindowController?
    private var recentWindow: TextWindowController?
    private var recentEvents: [String] = []
    private var isRunInProgress = false

    override init() {
        settings = settingsStore.load()
        super.init()
        wireEngineCallbacks()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateDuplicateCopies()
        NSApp.setActivationPolicy(.regular)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        migrateCaptureRegionIfNeeded()
        persistSettings()
        automationEngine.apply(settings: settings)
        rebuildMenu()
        updateControlWindow()
        showControlWindow()

        appendEvent(startupStatusText())
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
        appendEvent("Mode switched to \(mode.displayName). Target labels: \(settings.targetLabel).")
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
        menu.addItem(disabledItem("Engine: Apple OCR"))
        menu.addItem(disabledItem("Region: \(regionDescription())"))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Show Control Window", #selector(showControlWindow)))
        menu.addItem(actionItem("Pick Region...", #selector(pickRegion)))
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
            running: isRunInProgress,
            hasAccessibility: MousePermission.hasAccess,
            hasScreenCapture: ScreenCapturePermission.hasAccess,
            targetLabel: settings.targetLabel,
            pollingInterval: settings.pollingInterval,
            confidenceThreshold: settings.confidenceThreshold,
            isCursorTabSwitchingEnabled: settings.isCursorTabSwitchingEnabled,
            cursorTabCount: settings.cursorTabCount,
            cursorTabChangeInterval: settings.cursorTabChangeInterval
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
        controller.onShowRegion = { [weak self] in
            self?.showRegion()
        }
        controller.onRunOnce = { [weak self] in
            self?.runOnce()
        }
        controller.onRunCursorTabs = { [weak self] in
            self?.runCursorTabs()
        }
        controller.onShowActivity = { [weak self] in
            self?.showActivityLog()
        }

        return controller
    }

    private func showTextWindow(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let controller = TextWindowController(title: title, text: text)
        recentWindow = controller
        controller.showWindow(nil)
    }

    private func statusSummaryText() -> String {
        switch settings.mode {
        case .paused:
            return "Paused"
        case .live:
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
        return "Ready. Mode: \(settings.mode.displayName). Target labels: \(settings.targetLabel). Cursor tab switching: \(tabSwitching). Cursor tabs: \(settings.cursorTabCount). Region: \(regionDescription()). Permissions: Accessibility \(accessibility), Screen Recording \(screenRecording)."
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

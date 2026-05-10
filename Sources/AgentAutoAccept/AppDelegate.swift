import AgentAutoAcceptCore
import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let auditLogger: JSONLAuditLogger
    private let auditSink: BroadcastingAuditSink
    private let approvalController: AutoApprovalController
    private let scanner: AppScanner

    private var statusItem: NSStatusItem?
    private var recentEvents: [AuditEvent] = []
    private var recentWindow: TextWindowController?
    private var controlWindow: ControlWindowController?

    override init() {
        do {
            auditLogger = try JSONLAuditLogger()
        } catch {
            fatalError("Could not initialize audit log: \(error)")
        }

        if settings.mode == .live {
            settings.mode = .dryRun
        }

        auditSink = BroadcastingAuditSink(logger: auditLogger)
        approvalController = AutoApprovalController(mode: settings.mode, auditSink: auditSink)
        scanner = AppScanner(settings: settings, controller: approvalController)
        recentEvents = Array(auditLogger.recentEvents(limit: 100).reversed())
        super.init()

        auditSink.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.recentEvents.insert(event, at: 0)
                if self?.recentEvents.count ?? 0 > 100 {
                    self?.recentEvents.removeLast()
                }
                self?.rebuildMenu()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateDuplicateCopies()
        NSApp.setActivationPolicy(.regular)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        rebuildMenu()
        showControlWindow()

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.request()
        }

        scanner.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scanner.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlWindow()
        return true
    }

    @objc private func setDryRunMode() {
        setMode(.dryRun)
    }

    @objc private func setLiveMode() {
        setMode(.live)
    }

    @objc private func setPausedMode() {
        setMode(.paused)
    }

    @objc private func requestAccessibility() {
        AccessibilityPermission.request()
        rebuildMenu()
        updateControlWindow()
    }

    @objc private func showControlWindow() {
        let controller = controlWindow ?? makeControlWindow()
        controlWindow = controller
        updateControlWindow()
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    @objc private func showRecentDetections() {
        let events = recentEvents.isEmpty
            ? Array(auditLogger.recentEvents(limit: 100).reversed())
            : recentEvents
        let lines = events.isEmpty
            ? ["No detections yet."]
            : events.map(formatEvent)

        showTextWindow(title: "Recent Detections", text: lines.joined(separator: "\n\n"))
    }

    @objc private func showAuditLog() {
        let events = auditLogger.recentEvents(limit: 100)
        let text: String

        if events.isEmpty {
            let raw = rawAuditTail()
            text = raw.isEmpty
                ? "No audit events yet.\n\nAudit path:\n\(auditLogger.fileURL.path)"
                : "Could not decode audit events. Raw audit tail:\n\n\(raw)\n\nAudit path:\n\(auditLogger.fileURL.path)"
        } else {
            text = events.map(formatEvent).joined(separator: "\n\n") + "\n\nAudit path:\n\(auditLogger.fileURL.path)"
        }

        showTextWindow(title: "Audit Log", text: text)
    }

    @objc private func revealAuditLog() {
        NSWorkspace.shared.activateFileViewerSelecting([auditLogger.fileURL])
    }

    @objc private func addAppProfile() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add Allowed App"
        alert.informativeText = "Enter the display name and bundle identifier. The Codex approval rule will be used for this app."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Display name, e.g. Cursor"

        let bundleField = NSTextField(string: "")
        bundleField.placeholderString = "Bundle identifier, e.g. com.todesktop.230313mzl4w4u92"

        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(bundleField)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 360)
        ])

        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = bundleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !bundleID.isEmpty else {
            return
        }

        settings.addProfile(displayName: name, bundleIdentifier: bundleID)
        rebuildMenu()
    }

    @objc private func resetProfiles() {
        settings.resetProfiles()
        rebuildMenu()
    }

    @objc private func toggleProfile(_ sender: NSMenuItem) {
        guard
            let rawID = sender.representedObject as? String,
            let id = UUID(uuidString: rawID),
            let profile = settings.profiles.first(where: { $0.id == id })
        else {
            return
        }

        settings.setProfileEnabled(id, isEnabled: !profile.isEnabled)
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setMode(_ mode: AutoAcceptMode) {
        if mode == .live, settings.mode != .live, !confirmLiveMode() {
            rebuildMenu()
            updateControlWindow()
            return
        }

        if approvalController.mode != mode {
            approvalController.resetDedupe()
        }

        settings.mode = mode
        approvalController.mode = mode
        rebuildMenu()
        updateControlWindow()
    }

    private func rebuildMenu() {
        approvalController.mode = settings.mode

        statusItem?.length = NSStatusItem.squareLength
        if let button = statusItem?.button {
            button.image = statusImage(for: settings.mode)
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Agent AutoAccept is \(settings.mode.displayName)"
            button.setAccessibilityLabel("Agent AutoAccept \(settings.mode.displayName)")
        }

        let menu = NSMenu()
        menu.addItem(disabledItem("Agent AutoAccept: \(settings.mode.displayName)"))

        if !AccessibilityPermission.isTrusted {
            let item = NSMenuItem(
                title: "Grant Accessibility Permission...",
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        } else {
            menu.addItem(disabledItem("Accessibility: Granted"))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(modeItem(.dryRun, selector: #selector(setDryRunMode)))
        menu.addItem(modeItem(.live, selector: #selector(setLiveMode)))
        menu.addItem(modeItem(.paused, selector: #selector(setPausedMode)))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(allowedAppsMenu())

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Show Control Window", #selector(showControlWindow)))
        menu.addItem(actionItem("Recent Detections...", #selector(showRecentDetections)))
        menu.addItem(actionItem("View Audit Log...", #selector(showAuditLog)))
        menu.addItem(actionItem("Reveal Audit Log in Finder", #selector(revealAuditLog)))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Quit Agent AutoAccept", #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func allowedAppsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Allowed Apps", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for profile in settings.profiles {
            let profileItem = NSMenuItem(
                title: "\(profile.displayName) (\(profile.bundleIdentifier))",
                action: #selector(toggleProfile(_:)),
                keyEquivalent: ""
            )
            profileItem.target = self
            profileItem.state = profile.isEnabled ? .on : .off
            profileItem.representedObject = profile.id.uuidString
            submenu.addItem(profileItem)
        }

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(actionItem("Add App by Bundle ID...", #selector(addAppProfile)))
        submenu.addItem(actionItem("Reset to Codex Default", #selector(resetProfiles)))
        item.submenu = submenu
        return item
    }

    private func statusImage(for mode: AutoAcceptMode) -> NSImage? {
        let symbolName: String
        let description: String

        switch mode {
        case .dryRun:
            symbolName = "eye.circle.fill"
            description = "Agent AutoAccept monitor"
        case .live:
            symbolName = "checkmark.circle.fill"
            description = "Agent AutoAccept live"
        case .paused:
            symbolName = "pause.circle.fill"
            description = "Agent AutoAccept paused"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    private func modeItem(_ mode: AutoAcceptMode, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: mode.displayName, action: selector, keyEquivalent: "")
        item.target = self
        item.state = settings.mode == mode ? .on : .off
        return item
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

    private func showTextWindow(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let controller = TextWindowController(title: title, text: text)
        recentWindow = controller
        controller.showWindow(nil)
    }

    private func makeControlWindow() -> ControlWindowController {
        let controller = ControlWindowController()
        controller.onModeSelected = { [weak self] mode in
            self?.setMode(mode)
        }
        controller.onRequestAccessibility = { [weak self] in
            self?.requestAccessibility()
        }
        controller.onShowRecent = { [weak self] in
            self?.showRecentDetections()
        }
        controller.onShowAudit = { [weak self] in
            self?.showAuditLog()
        }
        return controller
    }

    private func updateControlWindow() {
        controlWindow?.update(
            mode: settings.mode,
            accessibilityTrusted: AccessibilityPermission.isTrusted,
            profiles: settings.profiles
        )
    }

    private func rawAuditTail(limit: Int = 100) -> String {
        guard
            let content = try? String(contentsOf: auditLogger.fileURL, encoding: .utf8),
            !content.isEmpty
        else {
            return ""
        }

        return content
            .split(separator: "\n")
            .suffix(limit)
            .joined(separator: "\n")
    }

    private func confirmLiveMode() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let first = NSAlert()
        first.alertStyle = .warning
        first.messageText = "Enable Live Mode?"
        first.informativeText = "Live Mode will press matched Run buttons in Codex and Cursor using Accessibility. Monitor mode only records detections."
        first.addButton(withTitle: "Continue")
        first.addButton(withTitle: "Cancel")

        guard first.runModal() == .alertFirstButtonReturn else {
            return false
        }

        let second = NSAlert()
        second.alertStyle = .critical
        second.messageText = "Confirm Live Mode"
        second.informativeText = "This can execute commands shown in agent approval prompts. Only enable it when you are ready for Agent AutoAccept to click Run automatically."
        second.addButton(withTitle: "Enable Live")
        second.addButton(withTitle: "Stay in Monitor")

        return second.runModal() == .alertFirstButtonReturn
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

    private func formatEvent(_ event: AuditEvent) -> String {
        let formatter = ISO8601DateFormatter()
        return """
        \(formatter.string(from: event.timestamp))  \(event.action.rawValue)  \(event.mode.displayName)
        App: \(event.appName) (\(event.bundleIdentifier))
        Window: \(event.windowTitle)
        Rule: \(event.matchedRule)  Confidence: \(String(format: "%.2f", event.confidence))
        Command: \(event.commandPreview)
        """
    }
}

private final class BroadcastingAuditSink: AuditSink {
    var onEvent: ((AuditEvent) -> Void)?

    private let logger: JSONLAuditLogger

    init(logger: JSONLAuditLogger) {
        self.logger = logger
    }

    func append(_ event: AuditEvent) throws {
        try logger.append(event)
        onEvent?(event)
    }
}

private enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func request() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

import AppKit

final class ControlWindowController: NSWindowController, NSTextFieldDelegate {
    struct State {
        var mode: AutomationMode
        var statusText: String
        var regionText: String
        var running: Bool
        var hasAccessibility: Bool
        var hasScreenCapture: Bool
        var targetLabel: String
        var pollingInterval: TimeInterval
        var confidenceThreshold: Double
        var isCursorTabSwitchingEnabled: Bool
        var cursorTabCount: Int
        var cursorTabChangeInterval: TimeInterval
    }

    struct Inputs {
        var targetLabel: String
        var pollingInterval: TimeInterval
        var confidenceThreshold: Double
        var isCursorTabSwitchingEnabled: Bool
        var cursorTabCount: Int
        var cursorTabChangeInterval: TimeInterval
    }

    var onModeSelected: ((AutomationMode) -> Void)?
    var onInputsChanged: ((Inputs) -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onRequestScreenCapture: (() -> Void)?
    var onPickRegion: (() -> Void)?
    var onShowRegion: (() -> Void)?
    var onRunOnce: (() -> Void)?
    var onRunCursorTabs: (() -> Void)?
    var onShowActivity: (() -> Void)?

    private var isProgrammaticUpdate = false

    private let modeControl = NSSegmentedControl(
        labels: ["Live", "Paused"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let versionLabel = NSTextField(labelWithString: AppVersion.current.displayText)
    private let statusLabel = NSTextField(labelWithString: "")
    private let regionLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")

    private let targetField = NSTextField(string: "")
    private let intervalField = NSTextField(string: "2.0")
    private let confidenceField = NSTextField(string: "0.58")
    private let cursorTabSwitchingCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let cursorTabCountField = NSTextField(string: "1")
    private let cursorTabChangeIntervalField = NSTextField(string: "0.35")

    private let accessibilityButton = NSButton(title: "Accessibility", target: nil, action: nil)
    private let screenButton = NSButton(title: "Screen Recording", target: nil, action: nil)
    private let pickRegionButton = NSButton(title: "Pick Region", target: nil, action: nil)
    private let showRegionButton = NSButton(title: "Show Region", target: nil, action: nil)
    private let runOnceButton = NSButton(title: "Run Once", target: nil, action: nil)
    private let runCursorTabsButton = NSButton(title: "Run Tabs", target: nil, action: nil)
    private let activityButton = NSButton(title: "Activity Log", target: nil, action: nil)

    init() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Vision Clicker")
        title.font = .boldSystemFont(ofSize: 24)

        versionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        regionLabel.font = .systemFont(ofSize: 13)
        regionLabel.textColor = .secondaryLabelColor
        permissionLabel.font = .systemFont(ofSize: 13)
        permissionLabel.textColor = .secondaryLabelColor

        modeControl.segmentStyle = .rounded
        modeControl.setWidth(120, forSegment: 0)
        modeControl.setWidth(120, forSegment: 1)

        targetField.placeholderString = "Run, Fetch"
        intervalField.placeholderString = "2.0"
        confidenceField.placeholderString = "0.20"
        cursorTabCountField.placeholderString = "3"
        cursorTabChangeIntervalField.placeholderString = "0.35"

        accessibilityButton.bezelStyle = .rounded
        screenButton.bezelStyle = .rounded
        pickRegionButton.bezelStyle = .rounded
        showRegionButton.bezelStyle = .rounded
        runOnceButton.bezelStyle = .rounded
        runCursorTabsButton.bezelStyle = .rounded
        activityButton.bezelStyle = .rounded

        let grid = NSGridView(views: [
            [Self.makeLabel("Target Labels"), targetField],
            [Self.makeLabel("Scan Interval (s)"), intervalField],
            [Self.makeLabel("Min Confidence"), confidenceField],
            [Self.makeLabel("Change Cursor Tabs"), cursorTabSwitchingCheckbox],
            [Self.makeLabel("Cursor Tabs"), cursorTabCountField],
            [Self.makeLabel("Tab Change Delay (s)"), cursorTabChangeIntervalField]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        content.addArrangedSubview(title)
        content.addArrangedSubview(versionLabel)
        content.addArrangedSubview(statusLabel)
        content.addArrangedSubview(modeControl)
        content.addArrangedSubview(grid)
        content.addArrangedSubview(regionLabel)
        content.addArrangedSubview(permissionLabel)

        let permissionRow = NSStackView(views: [accessibilityButton, screenButton])
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 10
        content.addArrangedSubview(permissionRow)

        let actionRow = NSStackView(views: [pickRegionButton, showRegionButton, runOnceButton, runCursorTabsButton, activityButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        content.addArrangedSubview(actionRow)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vision Clicker"
        window.contentView = content
        window.center()

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 512)
        ])

        super.init(window: window)

        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        targetField.target = self
        targetField.action = #selector(inputsChanged)
        targetField.delegate = self
        intervalField.target = self
        intervalField.action = #selector(inputsChanged)
        intervalField.delegate = self
        confidenceField.target = self
        confidenceField.action = #selector(inputsChanged)
        confidenceField.delegate = self
        cursorTabSwitchingCheckbox.target = self
        cursorTabSwitchingCheckbox.action = #selector(inputsChanged)
        cursorTabCountField.target = self
        cursorTabCountField.action = #selector(inputsChanged)
        cursorTabCountField.delegate = self
        cursorTabChangeIntervalField.target = self
        cursorTabChangeIntervalField.action = #selector(inputsChanged)
        cursorTabChangeIntervalField.delegate = self
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibility)
        screenButton.target = self
        screenButton.action = #selector(requestScreenCapture)
        pickRegionButton.target = self
        pickRegionButton.action = #selector(pickRegion)
        showRegionButton.target = self
        showRegionButton.action = #selector(showRegion)
        runOnceButton.target = self
        runOnceButton.action = #selector(runOnce)
        runCursorTabsButton.target = self
        runCursorTabsButton.action = #selector(runCursorTabs)
        activityButton.target = self
        activityButton.action = #selector(showActivity)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(with state: State) {
        isProgrammaticUpdate = true
        defer { isProgrammaticUpdate = false }

        modeControl.selectedSegment = state.mode == .live ? 0 : 1
        statusLabel.stringValue = "Status: \(state.statusText)"
        regionLabel.stringValue = "Region: \(state.regionText)"
        permissionLabel.stringValue = permissionText(
            hasAccessibility: state.hasAccessibility,
            hasScreenCapture: state.hasScreenCapture
        )

        if targetField.currentEditor() == nil {
            targetField.stringValue = state.targetLabel
        }
        if intervalField.currentEditor() == nil {
            intervalField.stringValue = String(format: "%.2f", state.pollingInterval)
        }
        if confidenceField.currentEditor() == nil {
            confidenceField.stringValue = String(format: "%.2f", state.confidenceThreshold)
        }
        cursorTabSwitchingCheckbox.state = state.isCursorTabSwitchingEnabled ? .on : .off
        if cursorTabCountField.currentEditor() == nil {
            cursorTabCountField.stringValue = "\(state.cursorTabCount)"
        }
        if cursorTabChangeIntervalField.currentEditor() == nil {
            cursorTabChangeIntervalField.stringValue = String(format: "%.2f", state.cursorTabChangeInterval)
        }

        showRegionButton.isEnabled = state.regionText != "Not selected"
        runOnceButton.isEnabled = !state.running
        runCursorTabsButton.isEnabled = state.isCursorTabSwitchingEnabled && !state.running
        cursorTabSwitchingCheckbox.isEnabled = !state.running
        cursorTabCountField.isEnabled = state.isCursorTabSwitchingEnabled && !state.running
        cursorTabChangeIntervalField.isEnabled = state.isCursorTabSwitchingEnabled && !state.running
        modeControl.isEnabled = !state.running
    }

    @objc private func modeChanged() {
        let selectedMode: AutomationMode = modeControl.selectedSegment == 0 ? .live : .paused
        commitPendingInputs()
        onModeSelected?(selectedMode)
    }

    @objc private func inputsChanged() {
        guard !isProgrammaticUpdate else {
            return
        }

        let interval = max(0.75, Double(intervalField.stringValue) ?? 2.0)
        let confidence = min(max(Double(confidenceField.stringValue) ?? 0.58, 0), 1)
        let isCursorTabSwitchingEnabled = cursorTabSwitchingCheckbox.state == .on
        let cursorTabCount = min(max(Int(cursorTabCountField.stringValue) ?? 1, 1), 40)
        let cursorTabChangeInterval = min(max(Double(cursorTabChangeIntervalField.stringValue) ?? 0.35, 0.05), 5.0)

        onInputsChanged?(
            Inputs(
                targetLabel: targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                pollingInterval: interval,
                confidenceThreshold: confidence,
                isCursorTabSwitchingEnabled: isCursorTabSwitchingEnabled,
                cursorTabCount: cursorTabCount,
                cursorTabChangeInterval: cursorTabChangeInterval
            )
        )
    }

    @objc private func requestAccessibility() {
        onRequestAccessibility?()
    }

    @objc private func requestScreenCapture() {
        onRequestScreenCapture?()
    }

    @objc private func pickRegion() {
        onPickRegion?()
    }

    @objc private func showRegion() {
        onShowRegion?()
    }

    @objc private func runOnce() {
        commitPendingInputs()
        onRunOnce?()
    }

    @objc private func runCursorTabs() {
        commitPendingInputs()
        onRunCursorTabs?()
    }

    @objc private func showActivity() {
        onShowActivity?()
    }

    func controlTextDidChange(_ notification: Notification) {
        inputsChanged()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        inputsChanged()
    }

    private func permissionText(hasAccessibility: Bool, hasScreenCapture: Bool) -> String {
        let mouse = hasAccessibility ? "Accessibility: Granted" : "Accessibility: Missing"
        let screen = hasScreenCapture ? "Screen Recording: Granted" : "Screen Recording: Missing"
        return "\(mouse) | \(screen)"
    }

    private func commitPendingInputs() {
        window?.makeFirstResponder(nil)
        inputsChanged()
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = .secondaryLabelColor
        return field
    }

}

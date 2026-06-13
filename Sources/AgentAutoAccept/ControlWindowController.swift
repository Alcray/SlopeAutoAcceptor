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
        var autoRegionModel: String
        var autoRegionURL: String
        var isAutoPickingRegion: Bool
        var isCheckingForUpdates: Bool
        var isInstallingUpdate: Bool
    }

    struct Inputs {
        var targetLabel: String
        var pollingInterval: TimeInterval
        var confidenceThreshold: Double
        var isCursorTabSwitchingEnabled: Bool
        var cursorTabCount: Int
        var cursorTabChangeInterval: TimeInterval
        var autoRegionModel: String
        var autoRegionURL: String
    }

    var onModeSelected: ((AutomationMode) -> Void)?
    var onInputsChanged: ((Inputs) -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onRequestScreenCapture: (() -> Void)?
    var onPickRegion: (() -> Void)?
    var onAutoPickRegion: (() -> Void)?
    var onShowRegion: (() -> Void)?
    var onRunOnce: (() -> Void)?
    var onRunCursorTabs: (() -> Void)?
    var onShowTestingGround: (() -> Void)?
    var onShowOCRDebug: (() -> Void)?
    var onShowActivity: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    private var isProgrammaticUpdate = false

    private let modeControl = NSSegmentedControl(
        labels: ["Live", "Paused"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let versionLabel = NSTextField(labelWithString: AppVersion.current.displayText)
    private let checkUpdatesButton = NSButton(title: "Check for Updates", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let regionLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")

    private let targetField = NSTextField(string: "")
    private let intervalField = NSTextField(string: "2.0")
    private let confidenceField = NSTextField(string: "0.58")
    private let cursorTabSwitchingCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let cursorTabCountField = NSTextField(string: "1")
    private let cursorTabChangeIntervalField = NSTextField(string: "0.35")
    private let autoRegionModelField = NSTextField(string: "moondream")
    private let autoRegionURLField = NSTextField(string: "http://localhost:11434")

    private let accessibilityButton = NSButton(title: "Accessibility", target: nil, action: nil)
    private let screenButton = NSButton(title: "Screen Recording", target: nil, action: nil)
    private let pickRegionButton = NSButton(title: "Pick Region", target: nil, action: nil)
    private let autoPickRegionButton = NSButton(title: "Auto Region (Beta)", target: nil, action: nil)
    private let showRegionButton = NSButton(title: "Show Region", target: nil, action: nil)
    private let testingGroundButton = NSButton(title: "Test Ground", target: nil, action: nil)
    private let ocrDebugButton = NSButton(title: "OCR View", target: nil, action: nil)
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
        targetField.toolTip = "Separate labels with commas, for example: Run, Accept, Retry"
        intervalField.placeholderString = "2.0"
        confidenceField.placeholderString = "0.20"
        cursorTabCountField.placeholderString = "3"
        cursorTabChangeIntervalField.placeholderString = "0.35"
        autoRegionModelField.placeholderString = "moondream"
        autoRegionURLField.placeholderString = "http://localhost:11434"

        accessibilityButton.bezelStyle = .rounded
        screenButton.bezelStyle = .rounded
        checkUpdatesButton.bezelStyle = .rounded
        pickRegionButton.bezelStyle = .rounded
        autoPickRegionButton.bezelStyle = .rounded
        showRegionButton.bezelStyle = .rounded
        testingGroundButton.bezelStyle = .rounded
        ocrDebugButton.bezelStyle = .rounded
        runOnceButton.bezelStyle = .rounded
        runCursorTabsButton.bezelStyle = .rounded
        activityButton.bezelStyle = .rounded

        let grid = NSGridView(views: [
            [Self.makeLabel("Target Labels"), targetField],
            [Self.makeLabel("Scan Interval (s)"), intervalField],
            [Self.makeLabel("Min Confidence"), confidenceField],
            [Self.makeLabel("Change Cursor Tabs"), cursorTabSwitchingCheckbox],
            [Self.makeLabel("Cursor Tabs"), cursorTabCountField],
            [Self.makeLabel("Tab Change Delay (s)"), cursorTabChangeIntervalField],
            [Self.makeLabel("VLM Model"), autoRegionModelField],
            [Self.makeLabel("VLM URL"), autoRegionURLField]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        let versionRow = NSStackView(views: [versionLabel, checkUpdatesButton])
        versionRow.orientation = .horizontal
        versionRow.alignment = .centerY
        versionRow.spacing = 10

        content.addArrangedSubview(title)
        content.addArrangedSubview(versionRow)
        content.addArrangedSubview(statusLabel)
        content.addArrangedSubview(modeControl)
        content.addArrangedSubview(grid)
        content.addArrangedSubview(regionLabel)
        content.addArrangedSubview(permissionLabel)

        let permissionRow = NSStackView(views: [accessibilityButton, screenButton])
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 10
        content.addArrangedSubview(permissionRow)

        let regionRow = NSStackView(views: [pickRegionButton, autoPickRegionButton, showRegionButton, testingGroundButton])
        regionRow.orientation = .horizontal
        regionRow.spacing = 10
        content.addArrangedSubview(regionRow)

        let actionRow = NSStackView(views: [runOnceButton, runCursorTabsButton, ocrDebugButton, activityButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        content.addArrangedSubview(actionRow)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vision Clicker"
        window.contentView = content
        window.center()

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 512),
            targetField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            intervalField.widthAnchor.constraint(equalToConstant: 72),
            confidenceField.widthAnchor.constraint(equalToConstant: 72),
            cursorTabCountField.widthAnchor.constraint(equalToConstant: 72),
            cursorTabChangeIntervalField.widthAnchor.constraint(equalToConstant: 72),
            autoRegionModelField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            autoRegionURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
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
        autoRegionModelField.target = self
        autoRegionModelField.action = #selector(inputsChanged)
        autoRegionModelField.delegate = self
        autoRegionURLField.target = self
        autoRegionURLField.action = #selector(inputsChanged)
        autoRegionURLField.delegate = self
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibility)
        screenButton.target = self
        screenButton.action = #selector(requestScreenCapture)
        checkUpdatesButton.target = self
        checkUpdatesButton.action = #selector(checkForUpdates)
        pickRegionButton.target = self
        pickRegionButton.action = #selector(pickRegion)
        autoPickRegionButton.target = self
        autoPickRegionButton.action = #selector(autoPickRegion)
        showRegionButton.target = self
        showRegionButton.action = #selector(showRegion)
        testingGroundButton.target = self
        testingGroundButton.action = #selector(showTestingGround)
        ocrDebugButton.target = self
        ocrDebugButton.action = #selector(showOCRDebug)
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
        if autoRegionModelField.currentEditor() == nil {
            autoRegionModelField.stringValue = state.autoRegionModel
        }
        if autoRegionURLField.currentEditor() == nil {
            autoRegionURLField.stringValue = state.autoRegionURL
        }

        showRegionButton.isEnabled = state.regionText != "Not selected"
        pickRegionButton.isEnabled = !state.running
        autoPickRegionButton.title = state.isAutoPickingRegion ? "Picking..." : "Auto Region (Beta)"
        autoPickRegionButton.isEnabled = !state.running
        runOnceButton.isEnabled = !state.running
        ocrDebugButton.isEnabled = state.regionText != "Not selected" && !state.running
        runCursorTabsButton.isEnabled = state.isCursorTabSwitchingEnabled && !state.running
        cursorTabSwitchingCheckbox.isEnabled = !state.running
        cursorTabCountField.isEnabled = state.isCursorTabSwitchingEnabled && !state.running
        cursorTabChangeIntervalField.isEnabled = state.isCursorTabSwitchingEnabled && !state.running
        autoRegionModelField.isEnabled = !state.running
        autoRegionURLField.isEnabled = !state.running
        modeControl.isEnabled = true
        if state.isInstallingUpdate {
            checkUpdatesButton.title = "Installing..."
        } else {
            checkUpdatesButton.title = state.isCheckingForUpdates ? "Checking..." : "Check for Updates"
        }
        checkUpdatesButton.isEnabled = !state.isCheckingForUpdates && !state.isInstallingUpdate
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
        let autoRegionModel = autoRegionModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let autoRegionURL = autoRegionURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        onInputsChanged?(
            Inputs(
                targetLabel: targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                pollingInterval: interval,
                confidenceThreshold: confidence,
                isCursorTabSwitchingEnabled: isCursorTabSwitchingEnabled,
                cursorTabCount: cursorTabCount,
                cursorTabChangeInterval: cursorTabChangeInterval,
                autoRegionModel: autoRegionModel.isEmpty ? "moondream" : autoRegionModel,
                autoRegionURL: autoRegionURL.isEmpty ? "http://localhost:11434" : autoRegionURL
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

    @objc private func autoPickRegion() {
        commitPendingInputs()
        onAutoPickRegion?()
    }

    @objc private func showRegion() {
        onShowRegion?()
    }

    @objc private func showTestingGround() {
        onShowTestingGround?()
    }

    @objc private func showOCRDebug() {
        commitPendingInputs()
        onShowOCRDebug?()
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

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
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

import AgentAutoAcceptCore
import AppKit

final class ControlWindowController: NSWindowController {
    var onModeSelected: ((AutoAcceptMode) -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onShowAudit: (() -> Void)?
    var onShowRecent: (() -> Void)?

    private let modeControl = NSSegmentedControl(
        labels: ["Monitor", "Live", "Paused"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let statusLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")
    private let appsLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "Grant Accessibility Permission", target: nil, action: nil)
    private let recentButton = NSButton(title: "Recent Detections", target: nil, action: nil)
    private let auditButton = NSButton(title: "Audit Log", target: nil, action: nil)

    init() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Agent AutoAccept")
        title.font = .boldSystemFont(ofSize: 24)

        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        permissionLabel.font = .systemFont(ofSize: 13)
        appsLabel.font = .systemFont(ofSize: 13)
        appsLabel.textColor = .secondaryLabelColor

        modeControl.segmentStyle = .rounded
        modeControl.setWidth(110, forSegment: 0)
        modeControl.setWidth(90, forSegment: 1)
        modeControl.setWidth(100, forSegment: 2)

        permissionButton.bezelStyle = .rounded
        recentButton.bezelStyle = .rounded
        auditButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [recentButton, auditButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        content.addArrangedSubview(title)
        content.addArrangedSubview(statusLabel)
        content.addArrangedSubview(modeControl)
        content.addArrangedSubview(permissionLabel)
        content.addArrangedSubview(permissionButton)
        content.addArrangedSubview(appsLabel)
        content.addArrangedSubview(buttonRow)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent AutoAccept"
        window.contentView = content
        window.center()

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 412)
        ])

        super.init(window: window)

        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        permissionButton.target = self
        permissionButton.action = #selector(requestAccessibility)
        recentButton.target = self
        recentButton.action = #selector(showRecent)
        auditButton.target = self
        auditButton.action = #selector(showAudit)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(mode: AutoAcceptMode, accessibilityTrusted: Bool, profiles: [AppProfile]) {
        switch mode {
        case .dryRun:
            modeControl.selectedSegment = 0
        case .live:
            modeControl.selectedSegment = 1
        case .paused:
            modeControl.selectedSegment = 2
        }

        statusLabel.stringValue = "Status: \(mode.displayName)"
        permissionLabel.stringValue = accessibilityTrusted
            ? "Accessibility: Granted"
            : "Accessibility: Not granted"

        let enabledProfiles = profiles
            .filter(\.isEnabled)
            .map(\.displayName)
            .joined(separator: ", ")
        appsLabel.stringValue = "Watching: \(enabledProfiles.isEmpty ? "No apps" : enabledProfiles)"
    }

    @objc private func modeChanged() {
        switch modeControl.selectedSegment {
        case 0:
            onModeSelected?(.dryRun)
        case 1:
            onModeSelected?(.live)
        default:
            onModeSelected?(.paused)
        }
    }

    @objc private func requestAccessibility() {
        onRequestAccessibility?()
    }

    @objc private func showRecent() {
        onShowRecent?()
    }

    @objc private func showAudit() {
        onShowAudit?()
    }
}

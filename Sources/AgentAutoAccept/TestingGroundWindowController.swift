import AppKit

final class TestingGroundWindowController: NSWindowController {
    private struct Scenario {
        let title: String
        let prompt: String
        let command: String
        let primaryLabel: String
        let secondaryLabel: String
        let noiseLabels: [String]
        let verticalOffset: CGFloat
        let alignRight: Bool
    }

    private let scenarios: [Scenario] = [
        Scenario(
            title: "Smoke test request",
            prompt: "Please run the final smoke test and tell me if the web app still answers.",
            command: "npm --prefix apps/web run smoke",
            primaryLabel: "Run",
            secondaryLabel: "Skip",
            noiseLabels: ["Running", "Auto-Run", "rerun"],
            verticalOffset: 80,
            alignRight: true
        ),
        Scenario(
            title: "Fetch package metadata",
            prompt: "Fetch the dependency metadata and inspect the changelog before editing.",
            command: "curl -fsS https://registry.npmjs.org/vite/latest",
            primaryLabel: "Fetch",
            secondaryLabel: "Skip",
            noiseLabels: ["Preflight", "Fetching soon", "Runbook"],
            verticalOffset: 180,
            alignRight: true
        ),
        Scenario(
            title: "Retry failing check",
            prompt: "The first check failed after a transient network timeout. Try it once more.",
            command: "pnpm test --filter affected",
            primaryLabel: "Retry",
            secondaryLabel: "Cancel",
            noiseLabels: ["Retrying", "Dry run", "Run cache"],
            verticalOffset: 20,
            alignRight: false
        ),
        Scenario(
            title: "Smoke branch validation",
            prompt: "Run only the smoke branch validation; do not deploy anything.",
            command: "npm run smoke:branch",
            primaryLabel: "Smoke Test",
            secondaryLabel: "Skip",
            noiseLabels: ["smoke test queued", "running tests", "Stop"],
            verticalOffset: 130,
            alignRight: true
        ),
        Scenario(
            title: "Approve local-only edit",
            prompt: "Approve the frontend-only patch so I can update the mock connector cards.",
            command: "git apply /tmp/frontend-only.patch",
            primaryLabel: "Approve",
            secondaryLabel: "Deny",
            noiseLabels: ["Approval required", "Approved earlier", "Run"],
            verticalOffset: 230,
            alignRight: false
        )
    ]

    private let scenarioTitle = NSTextField(labelWithString: "")
    private let promptLabel = NSTextField(wrappingLabelWithString: "")
    private let commandLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let noiseStack = NSStackView()
    private let approvalCard = NSBox()
    private let primaryButton = NSButton(title: "Run", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "Skip", target: nil, action: nil)
    private let spacerTop = NSView()
    private let spacerBottom = NSView()
    private let approvalRow = NSStackView()
    private var scenarioIndex = 0
    private var clickCount = 0
    private var spacerTopHeightConstraint: NSLayoutConstraint?
    private var spacerBottomMinConstraint: NSLayoutConstraint?

    init() {
        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = Self.makeSidebar()
        let workspace = NSStackView()
        workspace.orientation = .vertical
        workspace.alignment = .leading
        workspace.spacing = 14
        workspace.edgeInsets = NSEdgeInsets(top: 20, left: 26, bottom: 20, right: 26)
        workspace.translatesAutoresizingMaskIntoConstraints = false

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10

        scenarioTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        scenarioTitle.textColor = .labelColor
        let shuffleButton = NSButton(title: "Shuffle", target: nil, action: nil)
        shuffleButton.bezelStyle = .rounded
        let nextButton = NSButton(title: "Next Case", target: nil, action: nil)
        nextButton.bezelStyle = .rounded
        headerRow.addArrangedSubview(scenarioTitle)
        headerRow.addArrangedSubview(Self.flexSpacer())
        headerRow.addArrangedSubview(shuffleButton)
        headerRow.addArrangedSubview(nextButton)

        promptLabel.font = .systemFont(ofSize: 15)
        promptLabel.maximumNumberOfLines = 3
        promptLabel.lineBreakMode = .byWordWrapping

        let commandBox = NSBox()
        commandBox.boxType = .custom
        commandBox.cornerRadius = 6
        commandBox.borderColor = .separatorColor
        commandBox.borderWidth = 1
        commandBox.fillColor = .textBackgroundColor
        commandBox.translatesAutoresizingMaskIntoConstraints = false
        commandBox.contentView = commandLabel
        commandLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        commandLabel.textColor = .labelColor

        noiseStack.orientation = .vertical
        noiseStack.alignment = .leading
        noiseStack.spacing = 8

        approvalCard.boxType = .custom
        approvalCard.cornerRadius = 8
        approvalCard.borderColor = .separatorColor
        approvalCard.borderWidth = 1
        approvalCard.fillColor = .controlBackgroundColor
        approvalCard.translatesAutoresizingMaskIntoConstraints = false

        let approvalContent = NSStackView()
        approvalContent.orientation = .vertical
        approvalContent.alignment = .leading
        approvalContent.spacing = 10
        approvalContent.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        approvalContent.translatesAutoresizingMaskIntoConstraints = false
        approvalCard.contentView = approvalContent

        let approvalTitle = NSTextField(labelWithString: "Ask Every Time")
        approvalTitle.font = .systemFont(ofSize: 12, weight: .medium)
        approvalTitle.textColor = .secondaryLabelColor

        approvalRow.orientation = .horizontal
        approvalRow.alignment = .centerY
        approvalRow.spacing = 8

        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = ""
        secondaryButton.bezelStyle = .rounded
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        approvalContent.addArrangedSubview(approvalTitle)
        approvalContent.addArrangedSubview(approvalRow)
        approvalContent.addArrangedSubview(statusLabel)

        workspace.addArrangedSubview(headerRow)
        workspace.addArrangedSubview(promptLabel)
        workspace.addArrangedSubview(commandBox)
        workspace.addArrangedSubview(noiseStack)
        workspace.addArrangedSubview(spacerTop)
        workspace.addArrangedSubview(approvalCard)
        workspace.addArrangedSubview(spacerBottom)

        root.addArrangedSubview(sidebar)
        root.addArrangedSubview(workspace)

        let contentView = NSView()
        contentView.addSubview(root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vision Clicker Testing Ground"
        window.contentView = contentView
        window.center()

        super.init(window: window)

        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryClicked)
        shuffleButton.target = self
        shuffleButton.action = #selector(shuffleScenario)
        nextButton.target = self
        nextButton.action = #selector(nextScenario)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 190),
            workspace.widthAnchor.constraint(greaterThanOrEqualToConstant: 720),
            commandBox.heightAnchor.constraint(equalToConstant: 58),
            approvalCard.widthAnchor.constraint(equalToConstant: 420)
        ])

        applyScenario(at: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func nextScenario() {
        applyScenario(at: (scenarioIndex + 1) % scenarios.count)
    }

    @objc private func shuffleScenario() {
        let next = Int.random(in: 0..<scenarios.count)
        applyScenario(at: next == scenarioIndex ? (next + 1) % scenarios.count : next)
    }

    @objc private func primaryClicked() {
        clickCount += 1
        statusLabel.stringValue = "Clicked \(primaryButton.title) \(clickCount) time\(clickCount == 1 ? "" : "s")."
    }

    @objc private func secondaryClicked() {
        statusLabel.stringValue = "Secondary action clicked: \(secondaryButton.title)."
    }

    private func applyScenario(at index: Int) {
        scenarioIndex = index
        clickCount = 0
        let scenario = scenarios[index]

        scenarioTitle.stringValue = scenario.title
        promptLabel.stringValue = scenario.prompt
        commandLabel.stringValue = "$ \(scenario.command)"
        primaryButton.title = scenario.primaryLabel
        secondaryButton.title = scenario.secondaryLabel
        statusLabel.stringValue = "OCR target candidate: \(scenario.primaryLabel)"

        noiseStack.arrangedSubviews.forEach { view in
            noiseStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for label in scenario.noiseLabels {
            let field = NSTextField(labelWithString: label)
            field.font = .systemFont(ofSize: 13)
            field.textColor = .secondaryLabelColor
            noiseStack.addArrangedSubview(field)
        }

        approvalRow.arrangedSubviews.forEach { view in
            approvalRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if scenario.alignRight {
            approvalRow.addArrangedSubview(Self.flexSpacer())
        }
        approvalRow.addArrangedSubview(secondaryButton)
        approvalRow.addArrangedSubview(primaryButton)
        if !scenario.alignRight {
            approvalRow.addArrangedSubview(Self.flexSpacer())
        }

        spacerTop.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacerBottom.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacerTopHeightConstraint?.isActive = false
        spacerTopHeightConstraint = spacerTop.heightAnchor.constraint(equalToConstant: scenario.verticalOffset)
        spacerTopHeightConstraint?.isActive = true
        if spacerBottomMinConstraint == nil {
            spacerBottomMinConstraint = spacerBottom.heightAnchor.constraint(greaterThanOrEqualToConstant: 20)
            spacerBottomMinConstraint?.isActive = true
        }
    }

    private static func makeSidebar() -> NSView {
        let sidebar = NSStackView()
        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 14
        sidebar.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Mock Agent")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        sidebar.addArrangedSubview(title)

        for item in ["New Agent", "Marketplace", "Project setup", "Review branch", "Smoke tests", "Release notes"] {
            let field = NSTextField(labelWithString: item)
            field.font = .systemFont(ofSize: 13)
            field.textColor = item == "Review branch" ? .labelColor : .secondaryLabelColor
            sidebar.addArrangedSubview(field)
        }

        sidebar.addArrangedSubview(flexSpacer())
        let account = NSTextField(labelWithString: "Testing Ground")
        account.font = .systemFont(ofSize: 12)
        account.textColor = .secondaryLabelColor
        sidebar.addArrangedSubview(account)
        return sidebar
    }

    private static func flexSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }
}

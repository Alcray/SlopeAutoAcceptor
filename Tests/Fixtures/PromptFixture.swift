import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var pressCount = 0
    private let status = NSTextField(labelWithString: "Pressed 0 times")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent AutoAccept Prompt Fixture"
        window.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Run fixture command, 3+")
        title.font = .boldSystemFont(ofSize: 17)

        let command = NSTextField(labelWithString: "$ source .venv/bin/activate && python -m fixture smoke --dry-run")
        command.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        command.lineBreakMode = .byWordWrapping
        command.maximumNumberOfLines = 4
        status.font = .systemFont(ofSize: 13)

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 12

        let mode = NSTextField(labelWithString: "Auto-Run in Sandbox")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let skip = NSButton(title: "Skip", target: nil, action: nil)
        let run = NSButton(title: "Run ↩", target: self, action: #selector(runPressed))
        run.bezelStyle = .rounded

        controls.addArrangedSubview(mode)
        controls.addArrangedSubview(spacer)
        controls.addArrangedSubview(skip)
        controls.addArrangedSubview(run)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(command)
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(NSView())
        stack.addArrangedSubview(controls)

        window.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)
        ])

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func runPressed() {
        pressCount += 1
        status.stringValue = "Pressed \(pressCount) times"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

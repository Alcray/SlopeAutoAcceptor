import AgentAutoAcceptCore

func runPromptDetectorTests(_ suite: TestSuite) {
    let detector = PromptDetector()
    let codexApp = RunningAppInfo(
        name: "Codex",
        bundleIdentifier: "com.openai.codex",
        processIdentifier: 42
    )

    suite.run("Codex prompt matches Run button") {
        let runButton = FakeAccessibilityElement(role: "AXButton", title: "Run ↩")
        let tree = FakeAccessibilityElement(
            role: "AXWindow",
            title: "Codex",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "Run label tests and smoke after fallback source, 3+"),
                FakeAccessibilityElement(role: "AXStaticText", title: "$ source .venv/bin/activate && pytest -q tests/test_labeling.py"),
                FakeAccessibilityElement(role: "AXStaticText", title: "Auto-Run in Sandbox"),
                FakeAccessibilityElement(role: "AXButton", title: "Skip"),
                runButton
            ]
        )

        let candidates = detector.candidates(
            in: tree,
            app: codexApp,
            windowTitle: "Codex",
            profile: .codexDefault
        )

        suite.expect(candidates.count == 1, "expected exactly one prompt candidate")
        suite.expect(candidates.first?.matchedRuleID == "codex-approval-v1", "matched rule should be Codex v1")
        suite.expect(candidates.first?.commandPreview.contains("pytest -q") ?? false, "command preview should include shell text")
        suite.expect(candidates.first?.button === runButton, "candidate should keep the real Run button")
    }

    suite.run("generic Run button is rejected without Codex context") {
        let tree = FakeAccessibilityElement(
            role: "AXWindow",
            title: "Generic",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "Run the selected workflow"),
                FakeAccessibilityElement(role: "AXButton", title: "Run")
            ]
        )

        let candidates = detector.candidates(
            in: tree,
            app: codexApp,
            windowTitle: "Generic",
            profile: .codexDefault
        )

        suite.expect(candidates.isEmpty, "generic Run button should not match")
    }

    suite.run("Run label requires button role") {
        let tree = FakeAccessibilityElement(
            role: "AXWindow",
            title: "Codex",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "$ swift test && git status"),
                FakeAccessibilityElement(role: "AXStaticText", title: "Auto-Run in Sandbox"),
                FakeAccessibilityElement(role: "AXButton", title: "Skip"),
                FakeAccessibilityElement(role: "AXStaticText", title: "Run")
            ]
        )

        let candidates = detector.candidates(
            in: tree,
            app: codexApp,
            windowTitle: "Codex",
            profile: .codexDefault
        )

        suite.expect(candidates.isEmpty, "static text labeled Run should not be actionable")
    }

    suite.run("Run button can expose label through child text") {
        let runButton = FakeAccessibilityElement(
            role: "AXButton",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "Run"),
                FakeAccessibilityElement(role: "AXStaticText", title: "⏎")
            ]
        )
        let tree = FakeAccessibilityElement(
            role: "AXWindow",
            title: "Codex",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "$ swift test && git status"),
                FakeAccessibilityElement(role: "AXStaticText", title: "Auto-Run in Sandbox"),
                FakeAccessibilityElement(role: "AXButton", title: "Skip"),
                runButton
            ]
        )

        let candidates = detector.candidates(
            in: tree,
            app: codexApp,
            windowTitle: "Codex",
            profile: .codexDefault
        )

        suite.expect(candidates.count == 1, "button child text should be enough to identify Run")
        suite.expect(candidates.first?.button === runButton, "candidate should keep the parent button")
    }

    suite.run("Cursor shell command options count as approval context") {
        let runButton = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let tree = FakeAccessibilityElement(
            role: "AXWindow",
            title: "Cursor",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "Run full test suite source, 3+"),
                FakeAccessibilityElement(role: "AXStaticText", title: "$ source .venv/bin/activate && pytest -q"),
                FakeAccessibilityElement(role: "AXPopUpButton", title: "Shell command options"),
                runButton
            ]
        )

        let candidates = detector.candidates(
            in: tree,
            app: codexApp,
            windowTitle: "Cursor",
            profile: .cursorDefault
        )

        suite.expect(candidates.count == 1, "shell command options plus shell text should identify an approval prompt")
        suite.expect(candidates.first?.button === runButton, "candidate should keep the Run button")
    }

    suite.run("Cursor pressable Run control can be generic AX role") {
        let runControl = FakeAccessibilityElement(
            role: "AXGroup",
            canPress: true,
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "Run"),
                FakeAccessibilityElement(role: "AXStaticText", title: "⏎")
            ]
        )
        let tree = FakeAccessibilityElement(
            role: "AXWindow",
            title: "Cursor",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "Stop server, verify clean state and doc size pkill, 4+"),
                FakeAccessibilityElement(role: "AXStaticText", title: "$ pkill -f 'trainforgegen label-server' 2>/dev/null; sleep 0.4"),
                FakeAccessibilityElement(role: "AXStaticText", title: "Auto-Run in Sandbox"),
                FakeAccessibilityElement(role: "AXButton", title: "Skip"),
                runControl
            ]
        )

        let candidates = detector.candidates(
            in: tree,
            app: codexApp,
            windowTitle: "Cursor",
            profile: .cursorDefault
        )

        suite.expect(candidates.count == 1, "pressable generic controls labeled Run should match Cursor prompts")
        suite.expect(candidates.first?.button === runControl, "candidate should press the generic Run control")
    }

    suite.run("flat sampled detection matches Cursor prompt without traversing children") {
        let runButton = FakeAccessibilityElement(
            role: "AXButton",
            title: "Run⏎",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "Run"),
                FakeAccessibilityElement(role: "AXStaticText", title: "⏎")
            ]
        )
        let container = FakeAccessibilityElement(
            role: "AXGroup",
            title: "Start Gemini chunked smoke test in background source, 9+",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "This child should not be read")
            ]
        )
        let nodes: [any AccessibilityElement] = [
            container,
            FakeAccessibilityElement(role: "AXStaticText", title: "$ source .venv/bin/activate && python -m trainforgegen label"),
            FakeAccessibilityElement(role: "AXStaticText", title: "Auto-Run in Sandbox"),
            FakeAccessibilityElement(role: "AXButton", title: "Skip"),
            runButton
        ]

        let candidates = detector.candidates(
            inFlat: nodes,
            app: codexApp,
            windowTitle: "Cursor",
            profile: .cursorDefault
        )
        let snapshot = detector.debugSnapshot(inFlat: nodes, profile: .cursorDefault)

        suite.expect(candidates.count == 1, "flat sampled prompt should match")
        suite.expect(candidates.first?.button === runButton, "flat sampled prompt should keep the Run button")
        suite.expect(container.childrenReadCount == 0, "flat sampled detection must not traverse container children")
        suite.expect(runButton.childrenReadCount == 0, "flat sampled detection must not traverse Run button children")
        suite.expect(snapshot.runButtonLabels == ["Run⏎"], "flat snapshot should use direct button labels")
    }

    suite.run("flat sampled detection rejects Run label hidden only in child text") {
        let runButton = FakeAccessibilityElement(
            role: "AXButton",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "Run")
            ]
        )
        let nodes: [any AccessibilityElement] = [
            FakeAccessibilityElement(role: "AXStaticText", title: "$ swift test && git status"),
            FakeAccessibilityElement(role: "AXStaticText", title: "Auto-Run in Sandbox"),
            FakeAccessibilityElement(role: "AXButton", title: "Skip"),
            runButton
        ]

        let candidates = detector.candidates(
            inFlat: nodes,
            app: codexApp,
            windowTitle: "Cursor",
            profile: .cursorDefault
        )

        suite.expect(candidates.isEmpty, "flat sampled detection should require a direct Run label")
        suite.expect(runButton.childrenReadCount == 0, "flat sampled rejection must not traverse children")
    }

    suite.run("cyclic accessibility relationships are traversed once") {
        let cyclicContainer = FakeAccessibilityElement(role: "AXGroup")
        let runButton = FakeAccessibilityElement(role: "AXButton", title: "Run")
        let tree = FakeAccessibilityElement(
            role: "AXWindow",
            title: "Codex",
            children: [
                FakeAccessibilityElement(role: "AXStaticText", title: "$ swift test && git status"),
                FakeAccessibilityElement(role: "AXStaticText", title: "Auto-Run in Sandbox"),
                FakeAccessibilityElement(role: "AXButton", title: "Skip"),
                runButton,
                cyclicContainer
            ]
        )
        cyclicContainer.children = [tree, runButton]

        let snapshot = detector.debugSnapshot(in: tree, profile: .codexDefault)
        let candidates = detector.candidates(
            in: tree,
            app: codexApp,
            windowTitle: "Codex",
            profile: .codexDefault
        )

        suite.expect(snapshot.nodeCount == 6, "cyclic tree should flatten to unique nodes")
        suite.expect(candidates.count == 1, "valid prompt inside cyclic tree should still match once")
        suite.expect(candidates.first?.button === runButton, "candidate should keep the unique Run button")
    }
}

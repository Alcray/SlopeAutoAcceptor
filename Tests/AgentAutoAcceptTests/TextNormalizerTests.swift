import AgentAutoAcceptCore

func runTextNormalizerTests(_ suite: TestSuite) {
    suite.run("Run button label normalization") {
        suite.expect(TextNormalizer.isRunButtonLabel("Run"), "Run should match")
        suite.expect(TextNormalizer.isRunButtonLabel(" Run "), "trimmed Run should match")
        suite.expect(TextNormalizer.isRunButtonLabel("Run ↩"), "return glyph should be ignored")
        suite.expect(TextNormalizer.isRunButtonLabel("RUN ⏎"), "case and return symbol should be ignored")
        suite.expect(TextNormalizer.isRunButtonLabel("Run Return"), "Return hint should be ignored")
    }

    suite.run("non-Run labels are rejected") {
        suite.expect(!TextNormalizer.isRunButtonLabel("Rerun"), "Rerun should not match")
        suite.expect(!TextNormalizer.isRunButtonLabel("Run tests"), "Run tests should not match")
        suite.expect(!TextNormalizer.isRunButtonLabel("Run command"), "Run command should not match")
        suite.expect(!TextNormalizer.isRunButtonLabel("Skip"), "Skip should not match")
    }

    suite.run("command preview normalizes whitespace and truncates") {
        let preview = TextNormalizer.commandPreview(
            from: ["  $ swift   test\n\n&&", "echo done  "],
            limit: 18
        )

        suite.expect(preview == "$ swift test && ec...", "preview should normalize whitespace before truncating")
    }

    suite.run("prompt dedupe signature ignores transient fixture status") {
        let first = TextNormalizer.promptDedupeSignature(from: [
            "Run fixture command, 3+ $ source .venv/bin/activate && python -m fixture smoke --dry-run Pressed 0 times Auto-Run in Sandbox",
            "Skip",
            "Run ↩"
        ])
        let second = TextNormalizer.promptDedupeSignature(from: [
            "Run fixture command, 3+ $ source .venv/bin/activate && python -m fixture smoke --dry-run Pressed 1 time Auto-Run in Sandbox",
            "Skip",
            "Run ↩"
        ])

        suite.expect(first == second, "transient press counters should not produce a new prompt signature")
        suite.expect(first.contains("python -m fixture"), "signature should keep the command text")
    }
}

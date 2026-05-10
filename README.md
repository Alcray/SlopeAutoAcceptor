# Agent AutoAccept

Agent AutoAccept is a local-only macOS menu bar app for people running coding agents in parallel. It watches allowlisted apps for known GUI approval prompts and can press the real approval button with macOS Accessibility APIs.

V1 is intentionally narrow:

- Starts in **Monitor** mode and only logs detections.
- Targets Codex-style GUI prompts in Codex and Cursor.
- Uses Accessibility button presses, not global Enter keystrokes.
- Does not use OCR, Screen Recording, terminal automation, telemetry, or network access.

## Build

```bash
swift run AgentAutoAcceptSelfTest
sh scripts/build_app.sh
open "dist/Agent AutoAccept.app"
```

The self-test target is a dependency-free Swift executable so the test suite works on Command Line Tools installs that do not expose `XCTest`.
It covers label normalization, Codex/Cursor prompt matching, flat sampled Accessibility traversal, false-positive rejection, Monitor/Live/Paused controller behavior, Cursor's targeted click fallback, dedupe cooldowns, settings persistence, and JSONL audit logging.

For a normal local install:

```bash
sh scripts/install_app.sh
```

That installs `/Applications/Agent AutoAccept.app`. Grant Accessibility to that app path, not SwiftPM's hidden `.build` directory and not an older copy in `~/Applications`.

`scripts/build_app.sh` uses a stable local signing identity when one exists. Create it once with:

```bash
sh scripts/create_local_signing_identity.sh
```

This creates a local-only code-signing keychain and signs future local builds as `Agent AutoAccept Local Signing`, so macOS Accessibility trust survives rebuilt installs. You can also sign with an Apple identity:

```bash
AGENT_AUTOACCEPT_SIGN_IDENTITY="Developer ID Application: Your Name" sh scripts/build_app.sh
```

If an older ad-hoc build is already listed in System Settings, remove `Agent AutoAccept` from Privacy & Security -> Accessibility, add `/Applications/Agent AutoAccept.app` again, and restart the app.

## Use

The menu bar item shows one of three states:

- `AA Monitor`: detects and logs prompts without clicking.
- `AA Live`: presses matched `Run` buttons in allowlisted app windows.
- `AA Off`: scanning is paused.

Use **Allowed Apps** to enable/disable the built-in Codex/Cursor profiles or add another app by bundle identifier. Added apps use the same Codex-style prompt rule.

Audit logs are written as JSONL to:

```text
~/Library/Application Support/AgentAutoAccept/audit.jsonl
```

## Safety Model

Agent AutoAccept only scans apps on the allowlist. A prompt candidate must contain a real Accessibility button labeled like `Run`, plus Codex-style context such as `Skip`, `Auto-Run in Sandbox`, or shell command text. The scanner samples visible app windows to collect Accessibility anchors, expands nearby controls, then presses the matched button element; it does not send a blind click to a fixed screen coordinate. In live mode it calls the matched button directly; Cursor uses a targeted click on the matched button frame first because Electron can report successful Accessibility presses without executing the button. Monitor mode dedupes repeated detections for five minutes; Live mode retries the same visible prompt after a short cooldown so one ignored Electron click does not block execution for minutes.

There is no fallback path that sends keyboard events to the system.

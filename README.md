# Warning

Vision Clicker can approve actions in other applications by clicking buttons automatically. You use it entirely at your own risk. AI agents can make mistakes, and company approval prompts usually exist for real safety, privacy, compliance, and operational reasons.

Read the full [Disclaimer](docs/DISCLAIMER.md) before using this app.

# Intro

Sometimes admins in the companies don't allow auto-running mode for AI agents, argumenting it that "it can delete files" or "not safe for privacy", but in reality they simply don't understand the glory of AI and that the future is after unrestricted, autonomous AI SLOP! 

This simple app allows you to work with truly autonomous AI agents by automatically clicking on the "run" button, that your AI agent prompts because of some restrictions. 

The current setup does not work with AI agent in the background and requires the Agent window to be opened for clicking. Though the setup is tested and working with double monitor setup. 

# Formally 
Vision Clicker is a local macOS menu bar app that watches a user-selected screen region, finds a visible text button with Apple Vision OCR, clicks it, and then restores the cursor to its original position.

It is designed for small approval controls such as `Run`, `Fetch`, or `Retry` in coding-agent UIs.


## Install by asking your AI agent:

```text
Clone git@github.com:Alcray/SlopeAutoAcceptor.git,
then run ./install.sh from the repository root.
```

Or install manually from Terminal:

```bash
git clone git@github.com:Alcray/SlopeAutoAcceptor.git
cd SlopeAutoAcceptor
./install.sh
```

The installer builds the app, copies it to `/Applications/Vision Clicker.app`, reveals it in Finder, and launches it. If you only run `scripts/build_app.sh`, the app stays in `dist/` and is not installed into Applications.

## Features

- Draw a capture rectangle, similar to `cmd + shift + 4`.
- Experimentally auto-pick a capture region with a local Ollama VLM, while keeping OCR as the click detector.
- Highlight the saved region before running.
- Detect exact target labels with on-device Apple OCR.
- Support multiple labels, for example `Run, Fetch, Retry`.
- Click the detected label and restore the cursor.
- Run once manually or keep scanning in Live mode.
- Optionally sweep across Cursor tabs with `cmd + shift + ]`, click each visible target, then return with `cmd + shift + [`.
- Open a Testing Ground window with mock coding-agent prompts and changing approval buttons.
- Work with multi-monitor layouts, including displays above or beside the main display.

## Privacy

Normal Vision Clicker scans use Apple Vision OCR on your Mac. They do not require an API key, do not download a model, and do not send selected-region captures to a server.

The experimental **Auto Region** picker can send one full-desktop screenshot to a local Ollama VLM endpoint, defaulting to `http://localhost:11434` and model `moondream`. OCR still performs the actual target detection and click after the region is selected.

The app stores settings locally in `UserDefaults`, including the selected region, target labels, scan interval, and confidence threshold.

See [Privacy](docs/PRIVACY.md) for details.

## Requirements

- macOS 13 or newer.
- Accessibility permission, used to perform the synthetic mouse click.
- Screen Recording permission, used to capture the selected region.

## Build

```bash
swift build --product VisionClicker
swift run AgentAutoAcceptSelfTest
sh scripts/build_app.sh
```

The built app is written to:

```text
dist/Vision Clicker.app
```

For a local install:

```bash
./install.sh
```

That installs and launches:

```text
/Applications/Vision Clicker.app
```

## Usage

1. Launch Vision Clicker.
2. Grant Accessibility and Screen Recording permissions.
3. Enter target labels, such as `Run` or `Run, Fetch`.
4. Set a minimum confidence. `0.20` is a practical starting point for small buttons.
5. Click **Pick Region** and drag around the UI area that contains the target button.
6. Use **Show Region** to verify the saved rectangle.
7. Click **Run Once** to test.
8. For the VLM experiment, run `ollama serve`, pull a vision model such as `moondream`, then click **Auto Region**.
9. Use **Test Ground** to open a mock coding-agent window with changing approval controls.
10. For Cursor, turn on **Change Cursor Tabs**, set **Cursor Tabs** and **Tab Change Delay**, then click **Run Tabs**.
11. Switch to **Live** when the single run behaves correctly.

OCR matching is intentionally fuzzy after light normalization, so `Run` can match OCR text such as `Running` or `Auto-Run`. Keep the selected region tight around the approval controls to avoid nearby log text.

More detail is in the [User Guide](docs/USER_GUIDE.md).

## Release

Use [Release Checklist](docs/RELEASE_CHECKLIST.md) before publishing a build.

To publish a GitHub-backed version that Vision Clicker can detect from **Check for Updates**:

```bash
scripts/release.sh
```

The release script uses `gh` to read the latest GitHub Release, builds the app with the next patch version, pushes a `vX.Y.Z` tag, creates a GitHub Release, and uploads a zipped macOS app. The default policy is always the smallest bump, such as `v0.1.1` to `v0.1.2`. Use `minor`, `major`, or an explicit version only when that larger bump is deliberately requested:

```bash
ALLOW_NON_PATCH_BUMP=1 scripts/release.sh minor
```

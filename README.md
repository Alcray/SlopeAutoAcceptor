# Vision Clicker

Vision Clicker is a local macOS menu bar app that watches a user-selected screen region, finds a visible text button with Apple Vision OCR, clicks it, and then restores the cursor to its original position.

It is designed for small approval controls such as `Run`, `Fetch`, or `Retry` in coding-agent UIs.

## Features

- Draw a capture rectangle, similar to `cmd + shift + 4`.
- Highlight the saved region before running.
- Detect exact target labels with on-device Apple OCR.
- Support multiple labels, for example `Run, Fetch, Retry`.
- Click the detected label and restore the cursor.
- Run once manually or keep scanning in Live mode.
- Work with multi-monitor layouts, including displays above or beside the main display.

## Privacy

Vision Clicker uses Apple Vision OCR on your Mac. It does not require an API key, does not download a model, and does not send captured images to a server.

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
sh scripts/install_app.sh
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
8. Switch to **Live** when the single run behaves correctly.

OCR matching is exact after light normalization. A target label `Run` matches a `Run` button, but not `Running`, `rerun`, or `Auto-Run`.

More detail is in the [User Guide](docs/USER_GUIDE.md).

## Release

Use [Release Checklist](docs/RELEASE_CHECKLIST.md) before publishing a build.

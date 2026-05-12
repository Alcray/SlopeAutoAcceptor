# User Guide

## What Vision Clicker Does

Vision Clicker watches a screen region that you choose. When it sees one of your target labels, it clicks the center of the recognized text and returns the cursor to where it was.

The app is intentionally OCR-only. It uses Apple Vision locally on your Mac.

## First Run

1. Open `Vision Clicker.app`.
2. Click **Accessibility** and grant permission in System Settings.
3. Click **Screen Recording** and grant permission in System Settings.
4. Restart the app if macOS asks for it after Screen Recording permission changes.

## Picking a Region

Click **Pick Region**, then drag around the smallest practical area that contains the target button.

Smaller regions are faster and reduce false matches. For a coding-agent approval prompt, include the button row and a little context, but avoid long logs above it when possible.

Use **Show Region** to flash the saved rectangle on screen.

## Target Labels

Use the **Target Labels** field for one or more exact labels:

```text
Run
```

or:

```text
Run, Fetch, Retry
```

Labels are split by commas, semicolons, pipes, or new lines.

OCR matching is exact after light normalization, so `Run` does not match `Running`, `rerun`, or `Auto-Run`.

## Confidence

The default confidence is `0.20`, which works well for small macOS UI text.

Raise it if the app clicks too eagerly. Lower it only if the OCR result is visible in the Activity Log but gets rejected as too low-confidence.

## Running

- **Run Once** performs one scan and click attempt.
- **Live** scans repeatedly at the configured interval.
- **Paused** stops scanning.

Always test with **Run Once** before switching to **Live**.

## Local Click Samples

When **Save local click samples** is enabled, each successful click creates a training sample under:

```text
~/Library/Application Support/VisionClicker/Telemetry
```

Each sample folder contains:

- `before.png`: the selected region before the click.
- `after.png`: the same region shortly after the click.
- `metadata.json`: target labels, OCR text, click coordinates, region coordinates, confidence, mouse trace, and an automatic classification.

The top-level `samples.jsonl` file contains one compact metadata record per sample.

Classification is heuristic:

- `correct` means the after-click OCR text changed and the target was not still visible near the clicked location.
- `incorrect` means the after-click OCR text stayed the same or the target still appeared near the clicked location.

## Activity Log

The Activity Log records captures, OCR decisions, computed screen coordinates, and the mouse trace. If a click lands wrong, the log should make the coordinate path visible enough to debug.

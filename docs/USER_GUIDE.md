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

## Activity Log

The Activity Log records captures, OCR decisions, computed screen coordinates, and the mouse trace. If a click lands wrong, the log should make the coordinate path visible enough to debug.

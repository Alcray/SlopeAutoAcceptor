# User Guide

## What Vision Clicker Does

Vision Clicker watches a screen region that you choose. When it sees one of your target labels, it clicks the center of the recognized text and returns the cursor to where it was.

The click path is intentionally OCR-only and uses Apple Vision locally on your Mac. The experimental **Auto Region** feature can use a local VLM only to choose the capture region.

## First Run

1. Open `Vision Clicker.app`.
2. Click **Accessibility** and grant permission in System Settings.
3. Click **Screen Recording** and grant permission in System Settings.
4. Restart the app if macOS asks for it after Screen Recording permission changes.

## Picking a Region

Click **Pick Region**, then drag around the smallest practical area that contains the target button.

Smaller regions are faster and reduce false matches. For a coding-agent approval prompt, include the button row and a little context, but avoid long logs above it when possible.

Use **Show Region** to flash the saved rectangle on screen.

## Auto Region

**Auto Region** is experimental. It captures the full desktop, sends that screenshot to a local Ollama vision model, asks for a rectangle around the likely approval button, and saves that rectangle as the normal OCR region. It does not click anything.

The default VLM URL is:

```text
http://localhost:11434
```

The default model is:

```text
moondream
```

Start Ollama before using it:

```bash
ollama pull moondream
ollama serve
```

Vision Clicker temporarily hides its own control and Activity Log windows during the full-screen capture so the VLM is less likely to choose Vision Clicker’s own buttons.

## Testing Ground

Use **Test Ground** to open a mock coding-agent window. It shows command cards, noisy nearby labels such as `Running` or `Auto-Run`, and changing action buttons such as `Run`, `Fetch`, `Retry`, `Smoke Test`, and `Approve`.

Use it to test:

- whether OCR clicks the correct label at different confidence thresholds
- whether **Auto Region** finds a useful region before OCR starts clicking
- whether nearby false-positive text is inside or outside the selected region

## Target Labels

Use the **Target Labels** field for one or more labels:

```text
Run
```

or:

```text
Run, Fetch, Retry
```

Labels are split by commas, semicolons, pipes, or new lines.

OCR matching is fuzzy after light normalization, so `Run` can match OCR text such as `Running`, `rerun`, or `Auto-Run`. Keep the selected region tight around the approval controls and away from logs when possible.

## Confidence

The default confidence is `0.20`, which works well for small macOS UI text.

Raise it if the app clicks too eagerly. Lower it only if the OCR result is visible in the Activity Log but gets rejected as too low-confidence.

## Running

- **Run Once** performs one scan and click attempt.
- **Run Tabs** is Cursor-specific and stays disabled until **Change Cursor Tabs** is enabled. It scans and clicks the current tab, presses `cmd + shift + ]` for each additional tab, scans and clicks each one, then presses `cmd + shift + [` the same number of times to return to the starting tab.
- **Live** scans repeatedly at the configured interval. When **Change Cursor Tabs** is enabled and **Cursor Tabs** is greater than `1`, each Live cycle performs the same tab sweep as **Run Tabs**.
- **Paused** stops scanning.

Always test with **Run Once** before switching to **Live**.

## Cursor Tab Sweep

Turn on **Change Cursor Tabs** first. It is off by default so the app cannot unexpectedly move through Cursor tabs.

Set **Cursor Tabs** to the number of Cursor tabs you want to process. For example, `3` scans the current tab, moves right twice, scans each tab, then moves left twice to return.

Set **Tab Change Delay** to control how long the app waits after each Cursor tab shortcut before scanning. The default is `0.35` seconds; raise it if Cursor needs longer to render the next tab.

The sweep activates Cursor when it can find the running app. Accessibility permission is required for the tab keyboard shortcuts and the click.

## Activity Log

The Activity Log records captures, OCR decisions, computed screen coordinates, and the mouse trace. If a click lands wrong, the log should make the coordinate path visible enough to debug.

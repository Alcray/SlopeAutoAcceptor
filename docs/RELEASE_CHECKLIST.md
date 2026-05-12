# Release Checklist

## Product Surface

- App name is `Vision Clicker`.
- The UI is OCR-only.
- No OpenAI, Ollama, model, API key, or setup controls are visible.
- Activity Log remains available for debugging.
- README, User Guide, and Privacy docs describe the OCR-only product.
- Local click sample collection is described clearly because it saves screenshots.

## Local Verification

Run:

```bash
swift build --product VisionClicker
swift run AgentAutoAcceptSelfTest
sh scripts/build_app.sh
```

Then test:

1. Open `dist/Vision Clicker.app`.
2. Grant Accessibility and Screen Recording permissions if needed.
3. Pick a small region containing a `Run` button.
4. Set Target Labels to `Run`.
5. Set Min Confidence to `0.20`.
6. Run **Show Region**.
7. Enable **Save local click samples**.
8. Run **Run Once**.
9. Confirm the app clicks the button and restores the cursor.
10. Confirm a sample folder appears under `~/Library/Application Support/VisionClicker/Telemetry`.
11. Review `metadata.json` and the before/after screenshots.

## Packaging Notes

- Local builds use `scripts/build_app.sh`.
- Local installs use `scripts/install_app.sh`.
- The internal executable is `VisionClicker`; the app bundle is `Vision Clicker.app`.
- The bundle identifier is `dev.visionclicker.app`.

## Before Public Distribution

- Replace the placeholder bundle identifier with the final publisher identifier.
- Sign with a Developer ID certificate.
- Notarize the app with Apple.
- Decide whether to keep the current icon or create a Vision Clicker-specific icon.
- Smoke-test on a clean macOS account so first-run permissions are verified.

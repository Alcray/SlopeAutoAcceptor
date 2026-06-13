# Release Checklist

## Product Surface

- App name is `Vision Clicker`.
- OCR remains the only click detector.
- Experimental Auto Region controls are clearly separate from OCR clicking.
- Activity Log remains available for debugging.
- README, User Guide, and Privacy docs describe the OCR-only product.

## Local Verification

Run:

```bash
swift build --product VisionClicker
swift run AgentAutoAcceptSelfTest
sh scripts/build_app.sh
```

For a dry run of the GitHub release flow:

```bash
scripts/release.sh --dry-run
```

Release version policy:

- Default to the next patch version: `0.x.(y+1)`.
- Do not create `0.(x+1).0`, `1.0.0`, or any skipped version unless explicitly requested.
- Use `scripts/release.sh` or `scripts/release.sh patch` for normal releases.
- Use `ALLOW_NON_PATCH_BUMP=1` only when a non-patch version was explicitly requested.

Then test:

1. Open `dist/Vision Clicker.app`.
2. Grant Accessibility and Screen Recording permissions if needed.
3. Pick a small region containing a `Run` button.
4. Set Target Labels to `Run`.
5. Set Min Confidence to `0.20`.
6. Run **Show Region**.
7. Run **Run Once**.
8. Confirm the app clicks the button and restores the cursor.
9. Open **Test Ground** and verify the mock agent window cycles through different button labels.
10. With Ollama running and `moondream` pulled, run **Auto Region** against the Testing Ground window.
11. Confirm **Auto Region** saves and highlights a small region around the approval control.
12. Confirm OCR still handles the actual click with **Run Once** after Auto Region selects the region.
13. Confirm **Run Tabs** is disabled while **Change Cursor Tabs** is off.
14. In Cursor, open at least two tabs, turn on **Change Cursor Tabs**, set **Cursor Tabs** to `2`, and run **Run Tabs**.
15. Confirm the app clicks the visible button on each tab and returns to the starting tab.
16. Switch to **Live** and confirm the Activity Log says Live is using Cursor tab sweep, then logs keyboard-event creation for each tab change.
17. Raise **Tab Change Delay** and confirm the Activity Log reports the configured delay.
18. Confirm the selected region avoids nearby log text such as `Running` or `Auto-Run` when using fuzzy OCR.

## Packaging Notes

- Local builds use `scripts/build_app.sh`.
- Local installs use `scripts/install_app.sh`.
- Merging a PR into `main` automatically runs the GitHub Actions release workflow, which publishes the next patch release.
- Manual GitHub releases use `scripts/release.sh`, which creates the next patch release.
- `scripts/release.sh` requires an authenticated GitHub CLI session and publishes a `vX.Y.Z` GitHub Release with a zipped macOS app asset.
- The internal executable is `VisionClicker`; the app bundle is `Vision Clicker.app`.
- The bundle identifier is `dev.visionclicker.app`.

## Before Public Distribution

- Replace the placeholder bundle identifier with the final publisher identifier.
- Sign with a Developer ID certificate.
- Notarize the app with Apple.
- Decide whether to keep the current icon or create a Vision Clicker-specific icon.
- Smoke-test on a clean macOS account so first-run permissions are verified.

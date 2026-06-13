# Privacy

Vision Clicker is designed as a local utility.

## Data Processing

- Normal OCR screen captures are limited to the selected region.
- **Auto Region** captures the full desktop once so a local VLM can suggest a region.
- OCR is performed on-device with Apple Vision.
- Normal OCR captures are not sent to OpenAI, Ollama, or any other server.
- **Auto Region** sends the full-desktop screenshot to the configured Ollama-compatible URL. The default is the local machine at `http://localhost:11434`.
- The app does not require an API key or downloaded model.

## Local Storage

Vision Clicker stores settings in macOS `UserDefaults`, including:

- mode, such as Live or Paused
- selected screen region
- target labels
- scan interval
- confidence threshold
- whether Cursor tab switching is enabled
- Cursor tab count
- Cursor tab change delay
- Auto Region VLM model
- Auto Region VLM URL

The Activity Log is stored locally in `~/Library/Application Support/VisionClicker/activity.log`.

## Permissions

Vision Clicker asks for two macOS permissions:

- **Screen Recording**: required to capture the selected region.
- **Screen Recording**: also required for Auto Region full-desktop capture.
- **Accessibility**: required to move and click the mouse, restore the cursor, and press Cursor tab keyboard shortcuts.

## Network

Normal OCR operation does not need network access. **Auto Region** uses the configured VLM URL and is intended for local Ollama experiments.

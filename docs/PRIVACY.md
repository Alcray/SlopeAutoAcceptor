# Privacy

Vision Clicker is designed as a local utility.

## Data Processing

- Screen captures are limited to the selected region.
- OCR is performed on-device with Apple Vision.
- Captured images are not sent to OpenAI, Ollama, or any other server.
- The app does not require an API key or downloaded model.

## Local Storage

Vision Clicker stores settings in macOS `UserDefaults`, including:

- mode, such as Live or Paused
- selected screen region
- target labels
- scan interval
- confidence threshold

The Activity Log is in memory for the current app session.

## Permissions

Vision Clicker asks for two macOS permissions:

- **Screen Recording**: required to capture the selected region.
- **Accessibility**: required to move and click the mouse, then restore the cursor.

## Network

The published OCR-only app has no user-facing network configuration and does not need network access for its normal operation.

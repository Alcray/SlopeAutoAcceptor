#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Vision Clicker"
EXECUTABLE_NAME="VisionClicker"
CONFIGURATION="${CONFIGURATION:-release}"
DEFAULT_LOCAL_SIGN_IDENTITY="Agent AutoAccept Local Signing"
LOCAL_SIGN_IDENTITY="${AGENT_AUTOACCEPT_LOCAL_SIGN_IDENTITY:-$DEFAULT_LOCAL_SIGN_IDENTITY}"
LOCAL_SIGN_KEYCHAIN="${AGENT_AUTOACCEPT_SIGN_KEYCHAIN:-$HOME/Library/Keychains/AgentAutoAcceptSigning.keychain-db}"
LOCAL_SIGN_PASSWORD_FILE="${AGENT_AUTOACCEPT_SIGN_PASSWORD_FILE:-$HOME/Library/Application Support/AgentAutoAccept/signing-keychain-password}"
SIGN_IDENTITY="${AGENT_AUTOACCEPT_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$ROOT_DIR/Packaging/AgentAutoAccept.icns" ]]; then
    cp "$ROOT_DIR/Packaging/AgentAutoAccept.icns" "$APP_DIR/Contents/Resources/AgentAutoAccept.icns"
fi
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

CODE_SIGN_ARGS=()

if [[ -z "$SIGN_IDENTITY" && -f "$LOCAL_SIGN_KEYCHAIN" ]]; then
    if [[ -f "$LOCAL_SIGN_PASSWORD_FILE" ]]; then
        security unlock-keychain -p "$(cat "$LOCAL_SIGN_PASSWORD_FILE")" "$LOCAL_SIGN_KEYCHAIN" >/dev/null 2>&1 || true
    fi

    if security find-certificate -c "$LOCAL_SIGN_IDENTITY" "$LOCAL_SIGN_KEYCHAIN" >/dev/null 2>&1; then
        SIGN_IDENTITY="$LOCAL_SIGN_IDENTITY"
        CODE_SIGN_ARGS+=(--keychain "$LOCAL_SIGN_KEYCHAIN")
    fi
fi

if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_IDENTITY="-"
    echo "Signing with an ad-hoc identity. macOS may ask for Accessibility again after rebuilt installs." >&2
else
    echo "Signing with identity: $SIGN_IDENTITY" >&2
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "${CODE_SIGN_ARGS[@]}" "$APP_DIR" >/dev/null

echo "Built $APP_DIR"

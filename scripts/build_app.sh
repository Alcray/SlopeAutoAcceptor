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
if [[ -n "${VISION_CLICKER_VERSION:-}" ]]; then
    APP_VERSION="$VISION_CLICKER_VERSION"
else
    LATEST_VERSION_TAG="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)"
    if [[ -n "$LATEST_VERSION_TAG" ]]; then
        APP_VERSION="${LATEST_VERSION_TAG#v}"
    else
        APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Packaging/Info.plist" 2>/dev/null || echo 0.1.2)"
    fi
fi
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
GIT_BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
if [[ "$GIT_COMMIT" != "unknown" && -n "$(git status --porcelain 2>/dev/null)" ]]; then
    GIT_COMMIT="$GIT_COMMIT-dirty"
fi

set_plist_string() {
    local key="$1"
    local value="$2"
    local plist="$3"

    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" >/dev/null 2>&1 \
        || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist" >/dev/null
}

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
set_plist_string "CFBundleShortVersionString" "$APP_VERSION" "$APP_DIR/Contents/Info.plist"
set_plist_string "CFBundleVersion" "$GIT_BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
set_plist_string "VisionClickerBuildBranch" "$GIT_BRANCH" "$APP_DIR/Contents/Info.plist"
set_plist_string "VisionClickerBuildCommit" "$GIT_COMMIT" "$APP_DIR/Contents/Info.plist"
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

codesign --force --deep --sign "$SIGN_IDENTITY" ${CODE_SIGN_ARGS[@]+"${CODE_SIGN_ARGS[@]}"} "$APP_DIR" >/dev/null

echo "Built $APP_DIR ($APP_VERSION, $GIT_COMMIT, $GIT_BRANCH)"

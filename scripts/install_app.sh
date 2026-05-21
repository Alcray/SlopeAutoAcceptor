#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vision Clicker.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
DEST_DIR="${DEST_DIR:-/Applications}"
DEST_APP="$DEST_DIR/$APP_NAME"
OPEN_APP="${OPEN_APP:-1}"
REVEAL_IN_FINDER="${REVEAL_IN_FINDER:-1}"

"$ROOT_DIR/scripts/build_app.sh"
killall VisionClicker >/dev/null 2>&1 || true
killall AgentAutoAccept >/dev/null 2>&1 || true
mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
rm -rf "$DEST_DIR/Agent AutoAccept.app"
ditto "$SOURCE_APP" "$DEST_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST_APP" >/dev/null 2>&1 || true
if [[ "$REVEAL_IN_FINDER" == "1" ]]; then
    open -R "$DEST_APP"
fi
if [[ "$OPEN_APP" == "1" ]]; then
    open "$DEST_APP"
fi

echo "Installed Vision Clicker to $DEST_APP"
if [[ "$OPEN_APP" == "1" ]]; then
    echo "Launched $DEST_APP"
fi

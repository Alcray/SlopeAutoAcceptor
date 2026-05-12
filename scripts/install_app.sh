#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vision Clicker.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
DEST_DIR="${DEST_DIR:-/Applications}"
DEST_APP="$DEST_DIR/$APP_NAME"

"$ROOT_DIR/scripts/build_app.sh"
killall VisionClicker >/dev/null 2>&1 || true
killall AgentAutoAccept >/dev/null 2>&1 || true
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/Agent AutoAccept.app"
ditto "$SOURCE_APP" "$DEST_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST_APP" >/dev/null 2>&1 || true
open "$DEST_APP"

echo "Installed and launched $DEST_APP"

#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST_DIR=${DEST_DIR:-/Applications}
export DEST_DIR

exec "$ROOT_DIR/scripts/install_app.sh"

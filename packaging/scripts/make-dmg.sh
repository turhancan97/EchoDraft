#!/usr/bin/env bash
# Build a polished DMG for EchoDraft.app using create-dmg (brew install create-dmg).
# Usage: make-dmg.sh <version> <path-to-EchoDraft.app> <output-directory>
set -euo pipefail

VERSION="${1:?version required (e.g. 1.0.0)}"
APP_SRC="${2:?path to EchoDraft.app required}"
OUT_DIR="${3:?output directory required}"

if [[ ! -d "$APP_SRC" ]]; then
  echo "error: not a bundle: $APP_SRC" >&2
  exit 1
fi

command -v create-dmg >/dev/null 2>&1 || {
  echo "error: create-dmg not found. Install: brew install create-dmg" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP_SRC" "$STAGE/EchoDraft.app"
DMG_NAME="EchoDraft-${VERSION}.dmg"
DMG_PATH="${OUT_DIR}/${DMG_NAME}"
mkdir -p "$OUT_DIR"

BG="${ROOT}/packaging/assets/dmg-background.png"
CREATE_ARGS=(
  --volname "EchoDraft ${VERSION}"
  --window-pos 200 120
  --window-size 660 440
  --icon-size 88
  --icon "EchoDraft.app" 180 210
  --hide-extension "EchoDraft.app"
  --app-drop-link 480 210
)

if [[ -f "$BG" ]]; then
  CREATE_ARGS+=(--background "$BG")
fi

rm -f "$DMG_PATH"
create-dmg "${CREATE_ARGS[@]}" "$DMG_PATH" "$STAGE"

echo "Wrote: $DMG_PATH"
ls -lh "$DMG_PATH"

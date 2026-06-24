#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ModernWidget"
REPO="theBucky/modern-widget"
DMG_PATH="${DMG_PATH:-dist/$APP_NAME.dmg}"
APPCAST_PATH="${APPCAST_PATH:-dist/appcast.xml}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"

cd "$ROOT_DIR"

if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  echo "SPARKLE_PRIVATE_ED_KEY is required to sign the appcast" >&2
  exit 1
fi

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  swift build -c release
fi

archive_dir="$(mktemp -d)"
trap 'rm -rf "$archive_dir"' EXIT

cp "$DMG_PATH" "$archive_dir/$APP_NAME.dmg"
cat >"$archive_dir/$APP_NAME.md" <<NOTES
Rolling release built from ${GITHUB_SHA:-local}.
NOTES

printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$GENERATE_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/$REPO/releases/download/latest/" \
  --maximum-versions 1 \
  --embed-release-notes \
  "$archive_dir"

cp "$archive_dir/appcast.xml" "$APPCAST_PATH"

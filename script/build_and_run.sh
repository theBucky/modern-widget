#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ModernWidget"
BUNDLE_ID="com.m5pbook.ModernWidget"
MIN_SYSTEM_VERSION="26.0"
CONFIGURATION="${CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/theBucky/modern-widget/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

cd "$ROOT_DIR"

make_bundle() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true

  if [[ "$CONFIGURATION" == "release" && -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "SPARKLE_PUBLIC_ED_KEY is required for release bundles" >&2
    exit 1
  fi

  BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
  RESOURCE_BUNDLE="$BUILD_DIR/modern-widget_ModernWidget.bundle"
  rm -rf "$RESOURCE_BUNDLE"
  swift build -c "$CONFIGURATION"
  BUILD_BINARY="$BUILD_DIR/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"

  if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE"/. "$APP_RESOURCES/"
  fi

  SPARKLE_FRAMEWORK="$(find "$BUILD_DIR" -path "*/Sparkle.framework" -type d | head -1)"
  cp -R "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableInstallerLauncherService</key>
  <true/>
</dict>
</plist>
PLIST

  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

make_bundle

case "$MODE" in
  run)
    open_app
    ;;
  bundle)
    : # build and self-sign only; nothing to launch
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|bundle|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

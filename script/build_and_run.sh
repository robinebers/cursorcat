#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CursorCat"
BUNDLE_ID="com.sunstory.cursorcat"
MIN_SYSTEM_VERSION="26.0"
APP_VERSION="0.1.0"
APP_BUILD="1"
DEFAULT_SPARKLE_FEED_URL="https://robinebers.github.io/cursorcat/appcast.xml"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"
ICON_ICNS="$ROOT_DIR/Resources/AppIcon/AppIcon.icns"
ICON_ASSET_CAR="$ROOT_DIR/Resources/AppIcon/Assets.car"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_PUBLIC_ED_KEY_FILE="${SPARKLE_PUBLIC_ED_KEY_FILE:-$HOME/.cursorcat/sparkle/public_ed_key.txt}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-$DEFAULT_SPARKLE_FEED_URL}"
SPARKLE_FRAMEWORK_SOURCE=""

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BUILD_DIR/$RESOURCE_BUNDLE_NAME"

if [ ! -x "$BUILD_BINARY" ]; then
  echo "missing built binary: $BUILD_BINARY" >&2
  exit 1
fi

if [ ! -d "$RESOURCE_BUNDLE" ]; then
  echo "missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi

load_sparkle_public_key() {
  if [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
    return
  fi
  if [ -f "$SPARKLE_PUBLIC_ED_KEY_FILE" ]; then
    SPARKLE_PUBLIC_ED_KEY="$(tr -d '\n\r' < "$SPARKLE_PUBLIC_ED_KEY_FILE")"
  fi
}

sparkle_is_configured() {
  [ -n "$SPARKLE_FEED_URL" ] && [ -n "$SPARKLE_PUBLIC_ED_KEY" ]
}

find_sparkle_framework() {
  if [ -n "$SPARKLE_FRAMEWORK_SOURCE" ]; then
    return
  fi

  SPARKLE_FRAMEWORK_SOURCE="$(find "$ROOT_DIR/.build" -path '*/Sparkle.framework' -type d -print | head -n 1)"
  if [ -z "$SPARKLE_FRAMEWORK_SOURCE" ]; then
    echo "missing Sparkle.framework in build products" >&2
    exit 1
  fi
}

embed_sparkle_framework() {
  find_sparkle_framework

  rm -rf "$APP_FRAMEWORKS/Sparkle.framework"
  mkdir -p "$APP_FRAMEWORKS"
  cp -R "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS/"
}

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
if [ ! -f "$ICON_ICNS" ] || [ ! -f "$ICON_ASSET_CAR" ]; then
  echo "missing required icon artifacts in Resources/AppIcon" >&2
  exit 1
fi
cp "$ICON_ICNS" "$APP_RESOURCES/AppIcon.icns"
cp "$ICON_ASSET_CAR" "$APP_RESOURCES/Assets.car"
chmod +x "$APP_BINARY"
load_sparkle_public_key
embed_sparkle_framework

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if sparkle_is_configured; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool YES" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUAllowsAutomaticUpdates bool NO" "$INFO_PLIST"
fi

# Codesign the bundle with a stable identity so the keychain ACL sticks
# across rebuilds. Without this, every rebuild has a different cdhash and
# macOS re-prompts for access to `cursor-access-token` / `cursor-refresh-token`
# on every launch.
#
# Priority order:
#   1. $CODESIGN_IDENTITY env override (exact name or hash)
#   2. First Apple Development identity in the login keychain (stable across
#      rebuilds → keychain "Always Allow" sticks forever)
#   3. Fall back to ad-hoc (`-`) if no real identity is available, with a
#      warning that keychain prompts will keep returning.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$CODESIGN_IDENTITY" ]; then
  CODESIGN_IDENTITY=$(/usr/bin/security find-identity -p codesigning -v 2>/dev/null \
    | /usr/bin/awk -F\" '/Apple Development:/ { print $2; exit }')
fi

ENTITLEMENTS="$ROOT_DIR/script/CursorCat.dev.entitlements.plist"

sign_embedded_frameworks() {
  local identity="$1"

  /usr/bin/codesign \
    --force \
    --sign "$identity" \
    "$APP_FRAMEWORKS/Sparkle.framework" >/dev/null
}

if [ -n "$CODESIGN_IDENTITY" ]; then
  sign_embedded_frameworks "$CODESIGN_IDENTITY"
  /usr/bin/codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE" >/dev/null
  echo "signed with: $CODESIGN_IDENTITY"
else
  sign_embedded_frameworks "-"
  /usr/bin/codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" >/dev/null
  echo "WARNING: no Apple Development identity found; ad-hoc signed." >&2
  echo "         Keychain will re-prompt on every launch until you sign with a real identity." >&2
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
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
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --build|build)
    : # build-only
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

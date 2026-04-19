#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-app}"
APP_NAME="CursorCat"
BUNDLE_ID="${BUNDLE_ID:-com.sunstory.cursorcat}"
MIN_SYSTEM_VERSION="26.0"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-$APP_VERSION}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"
DEFAULT_SPARKLE_FEED_URL="https://github.com/robinebers/cursorcat/releases/latest/download/appcast.xml"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_ICNS="$ROOT_DIR/Resources/AppIcon/AppIcon.icns"
ICON_ASSET_CAR="$ROOT_DIR/Resources/AppIcon/Assets.car"
DIST_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ZIP="$DIST_DIR/$APP_NAME-notarize.zip"
DMG_STAGING_DIR="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_PUBLIC_ED_KEY_FILE="${SPARKLE_PUBLIC_ED_KEY_FILE:-$HOME/.cursorcat/sparkle/public_ed_key.txt}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-$DEFAULT_SPARKLE_FEED_URL}"

BUILD_DIR=""
BUILD_BINARY=""
RESOURCE_BUNDLE=""
RELEASE_IDENTITY=""
SPARKLE_FRAMEWORK_SOURCE=""
SETFILE_BIN=""
REZ_BIN=""

usage() {
  echo "usage: $0 [app|notarize-app|dmg|release]" >&2
}

ensure_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

ensure_prerequisites() {
  ensure_tool swift
  ensure_tool xcrun
  ensure_tool hdiutil
  ensure_tool /usr/libexec/PlistBuddy
}

locate_icon_tools() {
  if [ -n "$SETFILE_BIN" ] && [ -n "$REZ_BIN" ]; then
    return
  fi

  SETFILE_BIN="$(/usr/bin/xcrun --find SetFile 2>/dev/null || true)"
  REZ_BIN="$(/usr/bin/xcrun --find Rez 2>/dev/null || true)"

  if [ -z "$SETFILE_BIN" ] || [ -z "$REZ_BIN" ]; then
    echo "missing DMG icon tools; install Xcode command line support for SetFile and Rez" >&2
    exit 1
  fi
}

ensure_release_identity() {
  if [ -n "${RELEASE_IDENTITY:-}" ]; then
    return
  fi

  RELEASE_IDENTITY="${CODESIGN_IDENTITY:-}"
  if [ -z "$RELEASE_IDENTITY" ]; then
    RELEASE_IDENTITY=$(/usr/bin/security find-identity -p codesigning -v 2>/dev/null \
      | /usr/bin/awk -F\" '/Developer ID Application:/ { print $2; exit }')
  fi

  if [ -z "$RELEASE_IDENTITY" ]; then
    echo "missing Developer ID Application signing identity; install one or set CODESIGN_IDENTITY" >&2
    exit 1
  fi
}

load_sparkle_public_key() {
  if [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
    return
  fi

  if [ -f "$SPARKLE_PUBLIC_ED_KEY_FILE" ]; then
    SPARKLE_PUBLIC_ED_KEY="$(tr -d '\n\r' < "$SPARKLE_PUBLIC_ED_KEY_FILE")"
  fi
}

ensure_updater_metadata() {
  load_sparkle_public_key

  if [ -z "$SPARKLE_FEED_URL" ]; then
    echo "missing Sparkle feed URL; set SPARKLE_FEED_URL" >&2
    exit 1
  fi

  if [ -z "$SPARKLE_PUBLIC_ED_KEY" ]; then
    echo "missing Sparkle public Ed25519 key; set SPARKLE_PUBLIC_ED_KEY or SPARKLE_PUBLIC_ED_KEY_FILE" >&2
    exit 1
  fi
}

ensure_build_outputs() {
  if [ -n "$BUILD_DIR" ]; then
    return
  fi

  swift build -c release
  BUILD_DIR="$(swift build -c release --show-bin-path)"
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

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>3600</integer>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>SUAllowsAutomaticUpdates</key>
  <true/>
</dict>
</plist>
PLIST
}

assemble_app() {
  ensure_build_outputs
  ensure_updater_metadata
  find_sparkle_framework

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
  cp -R "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS/"
  if [ ! -f "$ICON_ICNS" ] || [ ! -f "$ICON_ASSET_CAR" ]; then
    echo "missing required icon artifacts in Resources/AppIcon" >&2
    exit 1
  fi
  cp "$ICON_ICNS" "$APP_RESOURCES/AppIcon.icns"
  cp "$ICON_ASSET_CAR" "$APP_RESOURCES/Assets.car"
  write_info_plist
}

sign_app() {
  ensure_release_identity

  /usr/bin/codesign \
    --force \
    --sign "$RELEASE_IDENTITY" \
    --options runtime \
    --timestamp \
    --deep \
    "$APP_FRAMEWORKS/Sparkle.framework" >/dev/null

  /usr/bin/codesign \
    --force \
    --sign "$RELEASE_IDENTITY" \
    --options runtime \
    --timestamp \
    "$APP_BUNDLE" >/dev/null
}

build_app() {
  assemble_app
  sign_app
}

notarize_app() {
  if [ ! -d "$APP_BUNDLE" ]; then
    echo "missing app bundle: $APP_BUNDLE" >&2
    echo "run '$0 app' first or use '$0 release'" >&2
    exit 1
  fi

  rm -f "$APP_ZIP"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
  /usr/bin/xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple -v "$APP_BUNDLE"
  /usr/bin/xcrun stapler validate "$APP_BUNDLE"
  /usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
}

build_dmg() {
  if [ ! -d "$APP_BUNDLE" ]; then
    echo "missing app bundle: $APP_BUNDLE" >&2
    echo "run '$0 app' first or use '$0 release'" >&2
    exit 1
  fi

  ensure_release_identity
  locate_icon_tools

  rm -rf "$DMG_STAGING_DIR"
  rm -f "$DMG_PATH"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$APP_BUNDLE" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"
  cp "$ICON_ICNS" "$DMG_STAGING_DIR/.VolumeIcon.icns"
  "$SETFILE_BIN" -a C "$DMG_STAGING_DIR"
  "$SETFILE_BIN" -a V "$DMG_STAGING_DIR/.VolumeIcon.icns"

  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  local icon_resource_script
  icon_resource_script="$(mktemp "$DIST_DIR/dmg-icon.XXXXXX.r")"
  cat >"$icon_resource_script" <<EOF
read 'icns' (-16455) "$ICON_ICNS";
EOF
  "$REZ_BIN" -append "$icon_resource_script" -o "$DMG_PATH" >/dev/null
  "$SETFILE_BIN" -a C "$DMG_PATH"
  rm -f "$icon_resource_script"

  /usr/bin/codesign \
    --force \
    --sign "$RELEASE_IDENTITY" \
    --timestamp \
    "$DMG_PATH" >/dev/null

  /usr/bin/xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple -v "$DMG_PATH"
  /usr/bin/xcrun stapler validate "$DMG_PATH"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
}

case "$MODE" in
  app)
    ensure_prerequisites
    build_app
    ;;
  notarize-app)
    ensure_prerequisites
    notarize_app
    ;;
  dmg)
    ensure_prerequisites
    build_dmg
    ;;
  release)
    ensure_prerequisites
    build_app
    notarize_app
    build_dmg
    ;;
  *)
    usage
    exit 2
    ;;
esac

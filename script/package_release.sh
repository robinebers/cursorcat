#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-release}"
APP_NAME="Cursorcat"
BUNDLE_ID="${BUNDLE_ID:-com.sunstory.cursorcat}"
MIN_SYSTEM_VERSION="26.0"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ZIP="$DIST_DIR/$APP_NAME-notarize.zip"
DMG_STAGING_DIR="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

BUILD_DIR=""
BUILD_BINARY=""
RESOURCE_BUNDLE=""
RELEASE_IDENTITY=""

usage() {
  echo "usage: $0 [app|notarize-app|dmg|release]" >&2
}

ensure_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
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
    echo "missing Developer ID Application signing identity; set CODESIGN_IDENTITY" >&2
    exit 1
  fi
}

ensure_build_outputs() {
  if [ -n "$BUILD_DIR" ]; then
    return
  fi

  ensure_tool swift
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
</dict>
</plist>
PLIST
}

assemble_app() {
  ensure_build_outputs

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
  write_info_plist
}

sign_app() {
  ensure_release_identity

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

  rm -rf "$DMG_STAGING_DIR"
  rm -f "$DMG_PATH"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$APP_BUNDLE" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"

  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

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
    build_app
    ;;
  notarize-app)
    notarize_app
    ;;
  dmg)
    build_dmg
    ;;
  release)
    build_app
    notarize_app
    build_dmg
    ;;
  *)
    usage
    exit 2
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_release.sh"
DIST_DIR="$ROOT_DIR/dist/release"
DMG_PATH="$DIST_DIR/CursorCat.dmg"
APPCAST_FILENAME="appcast.xml"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
DEFAULT_SPARKLE_PUBLIC_ED_KEY_FILE="${HOME}/.cursorcat/sparkle/public_ed_key.txt"
DEFAULT_SPARKLE_PRIVATE_KEY_FILE="${HOME}/.cursorcat/sparkle/private_ed25519.pem"

DRY_RUN=0
SKIP_PACKAGE=0
ALLOW_DIRTY=0
EXPLICIT_VERSION=""

TAG_CREATED=0
TAG_PUSHED=0
RELEASE_CREATED=0
APPCAST_PUBLISHED=0

REPO_OWNER=""
REPO_NAME=""
RELEASE_DOWNLOAD_URL=""
RELEASE_PAGE_URL=""
SPARKLE_FEED_URL=""
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_PUBLIC_ED_KEY_FILE="${SPARKLE_PUBLIC_ED_KEY_FILE:-$DEFAULT_SPARKLE_PUBLIC_ED_KEY_FILE}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$DEFAULT_SPARKLE_PRIVATE_KEY_FILE}"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-}"
SPARKLE_SIGN_UPDATE=""
APPCAST_WORKTREE=""

usage() {
  cat <<'EOF' >&2
usage: ./script/publish_release.sh [version] [--dry-run] [--skip-package] [--allow-dirty]

Examples:
  ./script/publish_release.sh
  ./script/publish_release.sh v0.1.4
  ./script/publish_release.sh --dry-run --allow-dirty
EOF
}

note_failure() {
  local exit_code="$1"

  if [ "$exit_code" -eq 0 ]; then
    return
  fi

  echo >&2
  echo "release publish failed." >&2
  if [ "$APPCAST_PUBLISHED" -eq 1 ]; then
    echo "cleanup: remove the latest appcast entry from gh-pages and push a correction" >&2
  fi
  if [ "$RELEASE_CREATED" -eq 1 ]; then
    echo "cleanup: gh release delete \"$VERSION\" --yes" >&2
  fi
  if [ "$TAG_PUSHED" -eq 1 ]; then
    echo "cleanup: git push origin \":refs/tags/$VERSION\"" >&2
  fi
  if [ "$TAG_CREATED" -eq 1 ]; then
    echo "cleanup: git tag -d \"$VERSION\"" >&2
  fi
}

cleanup_worktree() {
  if [ -n "$APPCAST_WORKTREE" ] && [ -d "$APPCAST_WORKTREE" ]; then
    git worktree remove --force "$APPCAST_WORKTREE" >/dev/null 2>&1 || true
  fi
}

trap 'exit_code=$?; trap - EXIT; note_failure "$exit_code"; cleanup_worktree' EXIT

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return
  fi

  "$@"
}

ensure_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 1
  fi
}

ensure_clean_worktree() {
  if [ "$ALLOW_DIRTY" -eq 1 ]; then
    return
  fi

  if [ -n "$(git status --porcelain)" ]; then
    echo "refusing to publish from a dirty worktree; commit/stash changes or pass --allow-dirty" >&2
    exit 1
  fi
}

ensure_gh_auth() {
  gh auth status >/dev/null
}

ensure_release_identity() {
  local identity="${CODESIGN_IDENTITY:-}"

  if [ -z "$identity" ]; then
    echo "missing Developer ID Application signing identity; set CODESIGN_IDENTITY" >&2
    exit 1
  fi

  if ! /usr/bin/security find-identity -p codesigning -v 2>/dev/null | grep -F "$identity" >/dev/null; then
    echo "CODESIGN_IDENTITY does not match an available signing identity: $identity" >&2
    exit 1
  fi
}

ensure_notary_profile() {
  if ! /usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "failed to access notary profile: $NOTARY_PROFILE" >&2
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

ensure_sparkle_keys() {
  load_sparkle_public_key

  if [ -z "$SPARKLE_PUBLIC_ED_KEY" ]; then
    echo "missing Sparkle public Ed25519 key; set SPARKLE_PUBLIC_ED_KEY or SPARKLE_PUBLIC_ED_KEY_FILE" >&2
    exit 1
  fi

  if [ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]; then
    echo "missing Sparkle private key file: $SPARKLE_PRIVATE_KEY_FILE" >&2
    exit 1
  fi
}

latest_version_tag() {
  git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1
}

validate_version() {
  if [[ ! "$1" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "invalid version: $1 (expected vX.Y.Z)" >&2
    exit 1
  fi
}

suggest_next_patch() {
  local latest_tag="$1"

  if [ -z "$latest_tag" ]; then
    echo "v0.1.0"
    return
  fi

  if [[ ! "$latest_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "latest tag is not semver: $latest_tag" >&2
    exit 1
  fi

  local major="${BASH_REMATCH[1]}"
  local minor="${BASH_REMATCH[2]}"
  local patch="${BASH_REMATCH[3]}"
  echo "v${major}.${minor}.$((patch + 1))"
}

resolve_version() {
  local latest_tag suggested input

  if [ -n "$EXPLICIT_VERSION" ]; then
    validate_version "$EXPLICIT_VERSION"
    echo "$EXPLICIT_VERSION"
    return
  fi

  latest_tag="$(latest_version_tag)"
  suggested="$(suggest_next_patch "$latest_tag")"

  if [ -n "$latest_tag" ]; then
    echo "latest version tag: $latest_tag" >&2
  else
    echo "no existing version tags found; defaulting to initial release suggestion" >&2
  fi
  echo "suggested release version: $suggested" >&2

  if [ ! -t 0 ] || [ "$DRY_RUN" -eq 1 ]; then
    echo "$suggested"
    return
  fi

  read -r -p "Release version [$suggested]: " input
  if [ -z "$input" ]; then
    input="$suggested"
  fi
  validate_version "$input"
  echo "$input"
}

ensure_version_available() {
  if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "git tag already exists: $VERSION" >&2
    exit 1
  fi

  if gh release view "$VERSION" >/dev/null 2>&1; then
    echo "GitHub release already exists: $VERSION" >&2
    exit 1
  fi
}

parse_origin_remote() {
  local remote

  remote="$(git remote get-url origin)"
  case "$remote" in
    https://github.com/*)
      remote="${remote#https://github.com/}"
      ;;
    git@github.com:*)
      remote="${remote#git@github.com:}"
      ;;
    *)
      echo "unsupported origin remote: $remote" >&2
      exit 1
      ;;
  esac

  remote="${remote%.git}"
  REPO_OWNER="${remote%%/*}"
  REPO_NAME="${remote##*/}"
  SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://${REPO_OWNER}.github.io/${REPO_NAME}/${APPCAST_FILENAME}}"
}

locate_sparkle_sign_update() {
  if [ -n "$SPARKLE_SIGN_UPDATE" ]; then
    return
  fi

  if [ -n "$SPARKLE_BIN_DIR" ] && [ -x "$SPARKLE_BIN_DIR/sign_update" ]; then
    SPARKLE_SIGN_UPDATE="$SPARKLE_BIN_DIR/sign_update"
    return
  fi

  local candidate
  candidate="$(find "$ROOT_DIR/.build" -path '*/Sparkle/bin/sign_update' -type f -perm -111 2>/dev/null | head -n 1)"
  if [ -n "$candidate" ]; then
    SPARKLE_SIGN_UPDATE="$candidate"
    return
  fi

  candidate="$(find "$ROOT_DIR/.build" -path '*/Sparkle/bin/sign_update' -type f 2>/dev/null | head -n 1)"
  if [ -n "$candidate" ]; then
    SPARKLE_SIGN_UPDATE="$candidate"
    return
  fi

  echo "missing Sparkle sign_update tool; set SPARKLE_BIN_DIR or resolve the Sparkle package first" >&2
  exit 1
}

sign_release_asset() {
  local signature_output

  if [ "$DRY_RUN" -eq 1 ]; then
    ASSET_SIGNATURE="DRY_RUN_SIGNATURE"
    ASSET_LENGTH="0"
    return
  fi

  signature_output="$("$SPARKLE_SIGN_UPDATE" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$DMG_PATH" 2>&1)"
  ASSET_SIGNATURE="$(printf '%s\n' "$signature_output" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')"
  ASSET_LENGTH="$(printf '%s\n' "$signature_output" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"

  if [ -z "${ASSET_SIGNATURE:-}" ] || [ -z "${ASSET_LENGTH:-}" ]; then
    echo "failed to parse Sparkle signature output" >&2
    echo "$signature_output" >&2
    exit 1
  fi
}

setup_appcast_worktree() {
  APPCAST_WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/cursorcat-gh-pages.XXXXXX")"

  if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
    run git worktree add -B gh-pages "$APPCAST_WORKTREE" origin/gh-pages
    return
  fi

  run git worktree add --detach "$APPCAST_WORKTREE" HEAD
  if [ "$DRY_RUN" -eq 0 ]; then
    git -C "$APPCAST_WORKTREE" checkout --orphan gh-pages >/dev/null 2>&1
    git -C "$APPCAST_WORKTREE" rm -rf --ignore-unmatch . >/dev/null 2>&1 || true
  fi
}

write_appcast() {
  local appcast_path="$APPCAST_WORKTREE/$APPCAST_FILENAME"
  local version_without_prefix="${VERSION#v}"
  local pub_date

  pub_date="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would write appcast to $appcast_path"
    return
  fi

  touch "$APPCAST_WORKTREE/.nojekyll"

  cat >"$appcast_path" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>CursorCat Updates</title>
    <link>$SPARKLE_FEED_URL</link>
    <description>Stable releases for CursorCat</description>
    <language>en</language>
    <item>
      <title>Version $version_without_prefix</title>
      <sparkle:version>$version_without_prefix</sparkle:version>
      <sparkle:shortVersionString>$version_without_prefix</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>$RELEASE_PAGE_URL</sparkle:releaseNotesLink>
      <pubDate>$pub_date</pubDate>
      <enclosure url="$RELEASE_DOWNLOAD_URL"
                 sparkle:edSignature="$ASSET_SIGNATURE"
                 length="$ASSET_LENGTH"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF
}

publish_appcast() {
  setup_appcast_worktree
  write_appcast

  run git -C "$APPCAST_WORKTREE" add "$APPCAST_FILENAME" .nojekyll
  run git -C "$APPCAST_WORKTREE" commit -m "Publish $VERSION appcast"
  run git -C "$APPCAST_WORKTREE" push origin gh-pages

  if [ "$DRY_RUN" -eq 0 ]; then
    APPCAST_PUBLISHED=1
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --skip-package)
        SKIP_PACKAGE=1
        ;;
      --allow-dirty)
        ALLOW_DIRTY=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      v*)
        if [ -n "$EXPLICIT_VERSION" ]; then
          echo "only one version may be provided" >&2
          exit 1
        fi
        EXPLICIT_VERSION="$1"
        ;;
      *)
        echo "unknown argument: $1" >&2
        usage
        exit 2
        ;;
    esac
    shift
  done
}

parse_args "$@"

ensure_tool git
ensure_tool gh
ensure_tool swift
ensure_tool xcrun
ensure_clean_worktree
ensure_gh_auth
ensure_release_identity
ensure_notary_profile
ensure_sparkle_keys

VERSION="$(resolve_version)"
APP_VERSION="${VERSION#v}"
APP_BUILD="$APP_VERSION"

parse_origin_remote
ensure_version_available

RELEASE_DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${VERSION}/CursorCat.dmg"
RELEASE_PAGE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/${VERSION}"

echo "release version: $VERSION"
echo "app version: $APP_VERSION"
echo "app build: $APP_BUILD"
echo "notary profile: $NOTARY_PROFILE"
echo "sparkle feed url: $SPARKLE_FEED_URL"

if [ "$SKIP_PACKAGE" -eq 0 ]; then
  run env \
    APP_VERSION="$APP_VERSION" \
    APP_BUILD="$APP_BUILD" \
    NOTARY_PROFILE="$NOTARY_PROFILE" \
    SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
    SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
    "$PACKAGE_SCRIPT" release
fi

locate_sparkle_sign_update

if [ "$DRY_RUN" -eq 0 ] && [ ! -f "$DMG_PATH" ]; then
  echo "missing packaged asset: $DMG_PATH" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ] && [ "$SKIP_PACKAGE" -eq 1 ]; then
  echo "skipping asset existence check in dry-run mode because packaging is skipped"
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "expected packaged asset after release build: $DMG_PATH"
fi

sign_release_asset

run git tag -a "$VERSION" -m "Release $VERSION"
if [ "$DRY_RUN" -eq 0 ]; then
  TAG_CREATED=1
fi

run git push origin "$VERSION"
if [ "$DRY_RUN" -eq 0 ]; then
  TAG_PUSHED=1
fi

run gh release create "$VERSION" "$DMG_PATH" --title "$VERSION" --generate-notes
if [ "$DRY_RUN" -eq 0 ]; then
  RELEASE_CREATED=1
fi

publish_appcast

echo "release published: $VERSION"

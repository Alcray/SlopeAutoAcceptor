#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Vision Clicker"
EXECUTABLE_NAME="VisionClicker"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

usage() {
    cat <<'USAGE'
Usage:
  scripts/release.sh [patch|minor|major|VERSION] [--dry-run]

Examples:
  scripts/release.sh
  scripts/release.sh patch
  ALLOW_NON_PATCH_BUMP=1 scripts/release.sh minor
  ALLOW_NON_PATCH_BUMP=1 scripts/release.sh 0.2.0
  DRAFT=1 scripts/release.sh patch

Environment:
  DRAFT=1                 Create the GitHub Release as a draft.
  PRERELEASE=1            Mark the GitHub Release as a prerelease.
  ALLOW_DIRTY=1           Allow releasing from a dirty working tree.
  ALLOW_NON_PATCH_BUMP=1  Allow minor, major, or skipped-version releases.

The script reads the latest GitHub Release with gh, falls back to local v* tags,
defaults to the next patch release, builds the app with that version, pushes the
git tag, creates a GitHub Release, and uploads dist/VisionClicker-vX.Y.Z-macOS.zip.
USAGE
}

DRY_RUN=0
BUMP_KIND="patch"
EXPLICIT_VERSION=""

for argument in "$@"; do
    case "$argument" in
        --dry-run)
            DRY_RUN=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        major|minor|patch)
            BUMP_KIND="$argument"
            ;;
        v[0-9]*|[0-9]*)
            EXPLICIT_VERSION="${argument#v}"
            ;;
        *)
            echo "Unknown argument: $argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

run() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'

    if [[ "$DRY_RUN" != "1" ]]; then
        "$@"
    fi
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

plist_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Packaging/Info.plist" 2>/dev/null \
        || echo "0.1.2"
}

normalize_version() {
    local raw="${1#v}"
    raw="${raw%%-*}"
    raw="${raw%%+*}"

    if [[ ! "$raw" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
        echo "Unsupported version: $1" >&2
        exit 1
    fi

    local major minor patch
    IFS=. read -r major minor patch <<<"$raw"
    echo "${major:-0}.${minor:-0}.${patch:-0}"
}

bump_version() {
    local version="$1"
    local kind="$2"
    local major minor patch

    IFS=. read -r major minor patch <<<"$(normalize_version "$version")"

    case "$kind" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
    esac

    echo "$major.$minor.$patch"
}

latest_published_tag() {
    local release_tag
    release_tag="$(gh release list \
        --exclude-drafts \
        --exclude-pre-releases \
        --limit 1 \
        --json tagName \
        --jq '.[0].tagName // ""' 2>/dev/null || true)"

    if [[ -n "$release_tag" ]]; then
        echo "$release_tag"
        return
    fi

    git tag --list 'v[0-9]*' --sort=-v:refname | head -1
}

require_command git
require_command gh
require_command swift
require_command ditto

gh auth status >/dev/null

BRANCH="$(git branch --show-current)"
if [[ -z "$BRANCH" ]]; then
    echo "Cannot release from detached HEAD." >&2
    exit 1
fi

if [[ "$DRY_RUN" != "1" && "${ALLOW_DIRTY:-0}" != "1" && -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty. Commit or stash changes before releasing, or set ALLOW_DIRTY=1." >&2
    exit 1
fi

run git fetch --tags origin

LATEST_TAG="$(latest_published_tag)"
if [[ -n "$LATEST_TAG" ]]; then
    BASE_VERSION="$(normalize_version "$LATEST_TAG")"
    NEXT_PATCH_VERSION="$(bump_version "$BASE_VERSION" patch)"
else
    BASE_VERSION="$(normalize_version "$(plist_version)")"
    NEXT_PATCH_VERSION="$BASE_VERSION"
fi

if [[ -n "$EXPLICIT_VERSION" ]]; then
    VERSION="$(normalize_version "$EXPLICIT_VERSION")"
elif [[ -n "$LATEST_TAG" ]]; then
    VERSION="$(bump_version "$LATEST_TAG" "$BUMP_KIND")"
else
    if [[ "$BUMP_KIND" == "patch" ]]; then
        VERSION="$BASE_VERSION"
    else
        VERSION="$(bump_version "$BASE_VERSION" "$BUMP_KIND")"
    fi
fi

if [[ "$VERSION" != "$NEXT_PATCH_VERSION" && "${ALLOW_NON_PATCH_BUMP:-0}" != "1" ]]; then
    echo "Release policy allows only the next patch version by default: v$NEXT_PATCH_VERSION." >&2
    echo "Requested v$VERSION. Use ALLOW_NON_PATCH_BUMP=1 only when a minor/major/skipped version was explicitly requested." >&2
    exit 1
fi

TAG="v$VERSION"
ASSET="$ROOT_DIR/dist/VisionClicker-$TAG-macOS.zip"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Tag already exists locally: $TAG" >&2
    exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Tag already exists on origin: $TAG" >&2
    exit 1
fi

echo "Latest published version: ${LATEST_TAG:-none}"
echo "Next version: $TAG"

run swift build --product "$EXECUTABLE_NAME"
run swift run AgentAutoAcceptSelfTest
run env VISION_CLICKER_VERSION="$VERSION" "$ROOT_DIR/scripts/build_app.sh"
run rm -f "$ASSET"
run ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ASSET"
run git push origin "$BRANCH"
run git tag -a "$TAG" -m "Vision Clicker $TAG"
run git push origin "$TAG"

RELEASE_ARGS=(
    release create "$TAG"
    "$ASSET#Vision Clicker $TAG for macOS"
    --verify-tag
    --title "Vision Clicker $TAG"
    --generate-notes
    --fail-on-no-commits
)

if [[ "${DRAFT:-0}" == "1" ]]; then
    RELEASE_ARGS+=(--draft)
fi

if [[ "${PRERELEASE:-0}" == "1" ]]; then
    RELEASE_ARGS+=(--prerelease)
fi

run gh "${RELEASE_ARGS[@]}"

if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run complete for Vision Clicker $TAG"
else
    echo "Released Vision Clicker $TAG"
fi

#!/usr/bin/env bash
set -euo pipefail

log() {
  printf "[publish-release] %s\n" "$*"
}

die() {
  printf "[publish-release][error] %s\n" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage:
  bash scripts/publish-github-release.sh --tag vX.Y.Z [--artifact-dir path] [--notes file] [--repo owner/repo]

Environment:
  BUILD_DIR                (default: <repo>/build)
  GITHUB_REPOSITORY        (optional if --repo provided or origin remote is GitHub)
  GH_RELEASE_NOTES_FILE    (default: docs/release-notes-template.md)
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
TAG=""
ARTIFACT_DIR=""
NOTES_FILE="${GH_RELEASE_NOTES_FILE:-$ROOT_DIR/docs/release-notes-template.md}"
REPO="${GITHUB_REPOSITORY:-}"
TITLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      TAG="$2"
      shift 2
      ;;
    --artifact-dir)
      [[ $# -ge 2 ]] || die "--artifact-dir requires a value"
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --notes)
      [[ $# -ge 2 ]] || die "--notes requires a value"
      NOTES_FILE="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      REPO="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || die "--title requires a value"
      TITLE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$TAG" ]] || die "--tag vX.Y.Z is required"
[[ "$TAG" =~ ^v[0-9]+(\.[0-9]+){2}([.-][0-9A-Za-z]+)*$ ]] || die "Tag must look like vX.Y.Z"

require_cmd git
require_cmd gh
require_cmd find

[[ -f "$NOTES_FILE" ]] || die "Notes file not found: $NOTES_FILE"

if [[ -z "$REPO" ]]; then
  remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ "$remote_url" =~ github.com[:/]([^/]+/[^/]+)(\.git)?$ ]]; then
    REPO="${BASH_REMATCH[1]}"
  fi
fi
[[ -n "$REPO" ]] || die "Set GITHUB_REPOSITORY or pass --repo owner/repo"

gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login"

if [[ -z "$ARTIFACT_DIR" ]]; then
  pointer="$BUILD_DIR/latest-release-dir.txt"
  if [[ -f "$pointer" ]]; then
    ARTIFACT_DIR="$(cat "$pointer")"
  fi
fi

if [[ -z "$ARTIFACT_DIR" ]]; then
  latest_dmg="$(find "$BUILD_DIR" -type f -name '*.dmg' 2>/dev/null | sort | tail -n 1 || true)"
  [[ -n "$latest_dmg" ]] || die "No DMG found under $BUILD_DIR. Run release script first."
  ARTIFACT_DIR="$(cd "$(dirname "$latest_dmg")" && pwd)"
fi
[[ -d "$ARTIFACT_DIR" ]] || die "Artifact directory not found: $ARTIFACT_DIR"

dmg_files=()
while IFS= read -r file; do
  dmg_files+=("$file")
done < <(find "$ARTIFACT_DIR" -maxdepth 1 -type f -name '*.dmg' | sort)
[[ "${#dmg_files[@]}" -gt 0 ]] || die "No .dmg file found in $ARTIFACT_DIR"

sha_files=()
while IFS= read -r file; do
  sha_files+=("$file")
done < <(find "$ARTIFACT_DIR" -maxdepth 1 -type f -name '*.dmg.sha256' | sort)
[[ "${#sha_files[@]}" -gt 0 ]] || die "No .dmg.sha256 file found in $ARTIFACT_DIR"

assets=()
assets+=("${dmg_files[@]}")
assets+=("${sha_files[@]}")
if [[ -f "$ARTIFACT_DIR/metadata.txt" ]]; then
  assets+=("$ARTIFACT_DIR/metadata.txt")
fi

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "This script requires a Git working tree"
fi

if ! git -C "$ROOT_DIR" show-ref --tags --verify --quiet "refs/tags/$TAG"; then
  log "Creating git tag: $TAG"
  git -C "$ROOT_DIR" tag "$TAG"
fi

log "Pushing tag to origin"
git -C "$ROOT_DIR" push origin "refs/tags/$TAG"

if [[ -z "$TITLE" ]]; then
  TITLE="$TAG"
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  log "Updating existing GitHub release: $TAG"
  gh release edit "$TAG" --repo "$REPO" --title "$TITLE" --notes-file "$NOTES_FILE"
else
  log "Creating GitHub release: $TAG"
  if [[ "$TAG" == *-* ]]; then
    gh release create "$TAG" --repo "$REPO" --title "$TITLE" --notes-file "$NOTES_FILE" --prerelease
  else
    gh release create "$TAG" --repo "$REPO" --title "$TITLE" --notes-file "$NOTES_FILE"
  fi
fi

log "Uploading artifacts from: $ARTIFACT_DIR"
gh release upload "$TAG" "${assets[@]}" --repo "$REPO" --clobber

release_url="$(gh release view "$TAG" --repo "$REPO" --json url --jq '.url')"
log "Done"
log "Release URL: $release_url"

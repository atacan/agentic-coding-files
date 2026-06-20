#!/bin/bash

# Creates a GitHub release for a Swift package from the current git HEAD.
# Usage:
#   release_swift_package.sh 1.2.3
#   release_swift_package.sh --version 1.2.3
#   release_swift_package.sh bump patch
#   release_swift_package.sh --bump minor

set -euo pipefail

show_usage() {
  cat >&2 <<'EOF'
Usage:
  release_swift_package.sh <version>
  release_swift_package.sh --version <version>
  release_swift_package.sh bump <patch|minor|major>
  release_swift_package.sh --bump <patch|minor|major>

Examples:
  release_swift_package.sh 1.2.3
  release_swift_package.sh v1.2.3
  release_swift_package.sh bump patch
  release_swift_package.sh --bump minor

The script must be run inside a git repository whose root contains Package.swift.
It creates an annotated git tag, pushes it to origin, then creates a GitHub
release with generated release notes using the gh CLI.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required command '$1' was not found."
  fi
}

normalize_version() {
  local candidate="${1#v}"

  if [[ "$candidate" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

version_gt() {
  local left="$1"
  local right="$2"
  local left_major left_minor left_patch
  local right_major right_minor right_patch

  IFS=. read -r left_major left_minor left_patch <<< "$left"
  IFS=. read -r right_major right_minor right_patch <<< "$right"

  if (( 10#$left_major != 10#$right_major )); then
    (( 10#$left_major > 10#$right_major ))
    return
  fi

  if (( 10#$left_minor != 10#$right_minor )); then
    (( 10#$left_minor > 10#$right_minor ))
    return
  fi

  (( 10#$left_patch > 10#$right_patch ))
}

latest_semver_tag() {
  local best_tag=""
  local best_version=""
  local tag
  local normalized

  while IFS= read -r tag; do
    if normalized=$(normalize_version "$tag"); then
      if [ -z "$best_version" ] || version_gt "$normalized" "$best_version"; then
        best_tag="$tag"
        best_version="$normalized"
      fi
    fi
  done < <(
    {
      gh release list --limit 100 --exclude-drafts --exclude-pre-releases --json tagName --jq '.[].tagName' 2>/dev/null || true
      git ls-remote --tags --refs origin 'refs/tags/*' 2>/dev/null | sed 's#.*refs/tags/##' || true
    } | awk 'NF && !seen[$0]++'
  )

  if [ -z "$best_version" ]; then
    return 1
  fi

  printf '%s %s\n' "$best_tag" "$best_version"
}

bump_version() {
  local version="$1"
  local bump_kind="$2"
  local major minor patch

  IFS=. read -r major minor patch <<< "$version"

  case "$bump_kind" in
    patch)
      patch=$((10#$patch + 1))
      ;;
    minor)
      minor=$((10#$minor + 1))
      patch=0
      ;;
    major)
      major=$((10#$major + 1))
      minor=0
      patch=0
      ;;
    *)
      die "Bump must be one of: patch, minor, major."
      ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

VERSION=""
BUMP=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      show_usage
      exit 0
      ;;
    --version)
      [ "$#" -ge 2 ] || die "--version requires a value."
      [ -z "$VERSION" ] || die "Version was provided more than once."
      VERSION="$2"
      shift 2
      ;;
    bump)
      [ "$#" -ge 2 ] || die "bump requires one of: patch, minor, major."
      [ -z "$BUMP" ] || die "Bump was provided more than once."
      BUMP="$2"
      shift 2
      ;;
    --bump)
      [ "$#" -ge 2 ] || die "--bump requires one of: patch, minor, major."
      [ -z "$BUMP" ] || die "Bump was provided more than once."
      BUMP="$2"
      shift 2
      ;;
    -*)
      show_usage
      die "Unknown option: $1"
      ;;
    *)
      [ -z "$VERSION" ] || die "Version was provided more than once."
      VERSION="$1"
      shift
      ;;
  esac
done

if [ -n "$VERSION" ] && [ -n "$BUMP" ]; then
  die "Provide either a version or a bump, not both."
fi

if [ -z "$VERSION" ] && [ -z "$BUMP" ]; then
  show_usage
  die "A version or bump is required."
fi

if [ -n "$VERSION" ]; then
  normalize_version "$VERSION" >/dev/null || die "Version must be SemVer in the form 1.2.3, optionally prefixed with v."
fi

if [ -n "$BUMP" ] && [[ "$BUMP" != "patch" && "$BUMP" != "minor" && "$BUMP" != "major" ]]; then
  die "Bump must be one of: patch, minor, major."
fi

require_command git
require_command gh
require_command awk
require_command sed

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "Not inside a git repository."
cd "$REPO_ROOT"

if [ ! -f "Package.swift" ]; then
  die "Not a Swift package repository. Expected Package.swift at git root: $REPO_ROOT"
fi

git remote get-url origin >/dev/null 2>&1 || die "No git remote named 'origin' was found."
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run 'gh auth login' first."
gh repo view >/dev/null 2>&1 || die "gh could not resolve a GitHub repository from this checkout."

if [ -n "$(git status --porcelain)" ]; then
  die "Working tree is not clean. Commit, stash, or remove local changes before releasing."
fi

git fetch --tags origin >/dev/null 2>&1 || die "Could not fetch tags from origin."

if [ -n "$BUMP" ]; then
  LATEST_INFO=$(latest_semver_tag) || die "No existing SemVer release or tag found. Create the first release with an explicit version."
  LATEST_TAG="${LATEST_INFO%% *}"
  LATEST_VERSION="${LATEST_INFO##* }"
  NEXT_VERSION=$(bump_version "$LATEST_VERSION" "$BUMP")

  if [[ "$LATEST_TAG" == v* ]]; then
    VERSION="v$NEXT_VERSION"
  else
    VERSION="$NEXT_VERSION"
  fi
fi

VERSION_NUMBER=$(normalize_version "$VERSION")
TAG_NAME="$VERSION"

if git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null; then
  die "Tag '$TAG_NAME' already exists locally."
fi

if git ls-remote --exit-code --tags origin "refs/tags/$TAG_NAME" >/dev/null 2>&1; then
  die "Tag '$TAG_NAME' already exists on origin."
fi

if gh release view "$TAG_NAME" >/dev/null 2>&1; then
  die "GitHub release '$TAG_NAME' already exists."
fi

echo "Creating annotated tag $TAG_NAME at $(git rev-parse --short HEAD)..."
git tag -a "$TAG_NAME" -m "Release $VERSION_NUMBER"

echo "Pushing tag $TAG_NAME to origin..."
git push origin "refs/tags/$TAG_NAME"

echo "Creating GitHub release $TAG_NAME..."
if ! gh release create "$TAG_NAME" --verify-tag --generate-notes --fail-on-no-commits --title "$TAG_NAME"; then
  echo "Tag '$TAG_NAME' was pushed, but GitHub release creation failed." >&2
  echo "Fix the error above, then run: gh release create '$TAG_NAME' --verify-tag --generate-notes --title '$TAG_NAME'" >&2
  exit 1
fi

RELEASE_URL=$(gh release view "$TAG_NAME" --json url --jq .url)

echo "Released $TAG_NAME"
echo "$RELEASE_URL"

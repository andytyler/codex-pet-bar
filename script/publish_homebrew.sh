#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
REPO="andytyler/codex-pet-bar"
TAP_DIR="/opt/homebrew/Library/Taps/andytyler/homebrew-tap"
TAP_REPO=""
TAP_BRANCH="main"
OUTPUT_DIR="/private/tmp/codexpet-release"
RUN_TESTS=1
RUN_BREW_AUDIT=1
ALLOW_DIRTY=0
PUBLISH_RELEASE=0
PUSH_TAP=0

usage() {
  cat <<USAGE
Usage: script/publish_homebrew.sh [options]

Builds the CodexPetBar cask zip, updates the cask SHA, and can publish the
GitHub release plus push the Homebrew tap.

Safe default: build + update local cask files only. It does not create a GitHub
release or push the tap unless you pass the explicit flags below.

Options:
      --version <version>       Release version. Default: 0.1.0
      --repo <owner/repo>       GitHub repo for release URLs. Default: andytyler/codex-pet-bar
      --tap-dir <path>          Local Homebrew tap checkout. Default: /opt/homebrew/Library/Taps/andytyler/homebrew-tap
      --tap-repo <owner/repo>   GitHub tap repo. Default: <release-owner>/homebrew-tap
      --tap-branch <branch>     Branch to push in the tap checkout. Default: main
      --output-dir <path>       Build output directory. Default: /private/tmp/codexpet-release
      --publish-release         Create or reuse GitHub release v<version> with the zip
      --push-tap                Commit and push Casks/codex-pet-bar.rb in the tap
      --allow-dirty             Allow publishing from a dirty source checkout
      --skip-tests              Skip Swift and Python tests
      --skip-brew-audit         Skip brew audit after brew style
  -h, --help                    Show this help

Examples:
  script/publish_homebrew.sh --version 0.1.0
  script/publish_homebrew.sh --version 0.1.0 --publish-release --push-tap
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?missing value for $1}"
      shift 2
      ;;
    --repo)
      REPO="${2:?missing value for $1}"
      shift 2
      ;;
    --tap-dir)
      TAP_DIR="${2:?missing value for $1}"
      shift 2
      ;;
    --tap-repo)
      TAP_REPO="${2:?missing value for $1}"
      shift 2
      ;;
    --tap-branch)
      TAP_BRANCH="${2:?missing value for $1}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:?missing value for $1}"
      shift 2
      ;;
    --publish-release)
      PUBLISH_RELEASE=1
      shift
      ;;
    --push-tap)
      PUSH_TAP=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --skip-brew-audit)
      RUN_BREW_AUDIT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_CASK="$ROOT_DIR/Casks/codex-pet-bar.rb"
TAP_CASK="$TAP_DIR/Casks/codex-pet-bar.rb"
TAP_CASK_REL="Casks/codex-pet-bar.rb"
TAG="v$VERSION"
ZIP_NAME="CodexPetBar-$VERSION-macos.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

log_step() {
  printf "\n==> %s\n" "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command git
require_command swift
require_command shasum
require_command ruby
require_command brew
require_command codesign
require_command mktemp
if [[ "$PUBLISH_RELEASE" -eq 1 ]]; then
  require_command gh
fi

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+)*([-+][A-Za-z0-9._-]+)?$ ]]; then
  echo "Version looks invalid: $VERSION" >&2
  exit 2
fi

if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "--repo must look like owner/repo, got: $REPO" >&2
  exit 2
fi

if [[ -z "$TAP_REPO" ]]; then
  TAP_REPO="${REPO%%/*}/homebrew-tap"
fi

if [[ ! "$TAP_REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "--tap-repo must look like owner/repo, got: $TAP_REPO" >&2
  exit 2
fi

TAP_OWNER="${TAP_REPO%%/*}"
TAP_REPO_NAME="${TAP_REPO#*/}"
if [[ "$TAP_REPO_NAME" == homebrew-* ]]; then
  TAP_TOKEN="$TAP_OWNER/${TAP_REPO_NAME#homebrew-}"
else
  TAP_TOKEN="$TAP_REPO"
fi

if [[ "$ALLOW_DIRTY" -eq 1 && ( "$PUBLISH_RELEASE" -eq 1 || "$PUSH_TAP" -eq 1 ) ]]; then
  cat >&2 <<MESSAGE
--allow-dirty is only for local rehearsals.

Commit the source repo before using --publish-release or --push-tap so the
release tag, uploaded zip, and tap cask describe the same code.
MESSAGE
  exit 2
fi

if [[ "$PUSH_TAP" -eq 1 && "$PUBLISH_RELEASE" -eq 0 ]]; then
  cat >&2 <<MESSAGE
--push-tap requires --publish-release.

That prevents pushing a cask before the matching GitHub release asset exists.
MESSAGE
  exit 2
fi

if [[ "$OUTPUT_DIR" != /* ]]; then
  echo "--output-dir must be an absolute path because it is deleted and rebuilt: $OUTPUT_DIR" >&2
  exit 2
fi

case "$OUTPUT_DIR" in
  /|"$ROOT_DIR"|"$ROOT_DIR/"|"$TAP_DIR"|"$TAP_DIR/")
    echo "Refusing unsafe --output-dir: $OUTPUT_DIR" >&2
    exit 2
    ;;
  /tmp/*|/private/tmp/*|"$ROOT_DIR"/dist/*)
    ;;
  *)
    cat >&2 <<MESSAGE
Refusing --output-dir outside /tmp, /private/tmp, or $ROOT_DIR/dist.

The publish script deletes and rebuilds the output directory.
MESSAGE
    exit 2
    ;;
esac

if [[ ! -f "$SOURCE_CASK" ]]; then
  echo "Missing source cask: $SOURCE_CASK" >&2
  exit 1
fi

if [[ ! -d "$TAP_DIR/.git" ]]; then
  echo "Tap checkout not found: $TAP_DIR" >&2
  exit 1
fi

github_remote_matches() {
  local url="$1"
  local repo="$2"
  case "$url" in
    "https://github.com/$repo"|"https://github.com/$repo.git"|"git@github.com:$repo"|"git@github.com:$repo.git"|"ssh://git@github.com/$repo"|"ssh://git@github.com/$repo.git")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

remote_tag_commit_sha() {
  local object_type
  local object_sha

  object_type="$(gh api "repos/$REPO/git/ref/tags/$TAG" --jq '.object.type')" || return 1
  object_sha="$(gh api "repos/$REPO/git/ref/tags/$TAG" --jq '.object.sha')" || return 1

  if [[ "$object_type" == "tag" ]]; then
    gh api "repos/$REPO/git/tags/$object_sha" --jq '.object.sha'
  else
    printf "%s\n" "$object_sha"
  fi
}

log_step "1. Checking source checkout"
cd "$ROOT_DIR"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Source directory is not a git repo: $ROOT_DIR" >&2
  exit 1
fi

if [[ "$ALLOW_DIRTY" -eq 0 && -n "$(git status --porcelain)" ]]; then
  cat >&2 <<MESSAGE
Source checkout has uncommitted changes.

Commit the repo first so the GitHub release tag matches the zip users install.
For a local rehearsal only, rerun with --allow-dirty.
MESSAGE
  exit 1
fi

log_step "1b. Checking Homebrew tap checkout"
(
  cd "$TAP_DIR"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Tap directory is not a git repo: $TAP_DIR" >&2
    exit 1
  fi

  if [[ "$PUSH_TAP" -eq 1 ]]; then
    tap_remote="$(git remote get-url origin)"
    if ! github_remote_matches "$tap_remote" "$TAP_REPO"; then
      cat >&2 <<MESSAGE
Tap checkout origin does not match the expected tap repo.

Expected: github.com/$TAP_REPO
Actual:   $tap_remote
MESSAGE
      exit 1
    fi

    tap_branch="$(git branch --show-current)"
    if [[ "$tap_branch" != "$TAP_BRANCH" ]]; then
      echo "Tap checkout is on '$tap_branch', expected '$TAP_BRANCH'." >&2
      exit 1
    fi

    git fetch origin "$TAP_BRANCH"
    remote_head="$(git rev-parse "origin/$TAP_BRANCH")"
    merge_base="$(git merge-base HEAD "origin/$TAP_BRANCH")"
    if [[ "$merge_base" != "$remote_head" ]]; then
      cat >&2 <<MESSAGE
Tap checkout is not up to date with origin/$TAP_BRANCH.

Pull or rebase the tap checkout before publishing.
MESSAGE
      exit 1
    fi
  fi

  dirty_paths="$(git status --porcelain | awk '{print $2}')"
  if [[ -n "$dirty_paths" ]]; then
    unexpected_dirty="$(
      printf "%s\n" "$dirty_paths" \
        | grep -v -E '^Casks/?$|^Casks/codex-pet-bar\.rb$' \
        || true
    )"
    if [[ -n "$unexpected_dirty" ]]; then
      cat >&2 <<MESSAGE
Tap checkout has unrelated uncommitted changes:
$unexpected_dirty

Commit, stash, or remove those changes before publishing.
MESSAGE
      exit 1
    fi
  fi
)

if [[ "$RUN_TESTS" -eq 1 ]]; then
  log_step "2. Running tests"
  swift test
  python3 -m unittest discover -s Tests/InstallHooksTests -p 'test_*.py'
else
  log_step "2. Skipping tests"
fi

log_step "3. Building Homebrew cask zip"
rm -rf -- "$OUTPUT_DIR"
VERSION="$VERSION" "$ROOT_DIR/script/package_app.sh" \
  --configuration release \
  --zip \
  --output "$OUTPUT_DIR"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Expected zip was not created: $ZIP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict "$OUTPUT_DIR/CodexPetBar.app"

SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "Zip: $ZIP_PATH"
echo "SHA: $SHA"

log_step "4. Updating cask version, URL, and sha256"
python3 - "$SOURCE_CASK" "$VERSION" "$SHA" "$REPO" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
sha = sys.argv[3]
repo = sys.argv[4]

text = path.read_text(encoding="utf-8")

def replace_once(pattern, replacement, description):
    global text
    text, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        raise SystemExit(f"Could not update {description} in {path}")

replace_once(r'version "[^"]+"', f'version "{version}"', "version")
replace_once(r'sha256 "[^"]+"', f'sha256 "{sha}"', "sha256")
replace_once(
    r'url "https://github.com/[^/]+/[^/]+/releases/download/v#\{version\}/CodexPetBar-#\{version\}-macos\.zip",',
    f'url "https://github.com/{repo}/releases/download/v#{{version}}/CodexPetBar-#{{version}}-macos.zip",',
    "url",
)
replace_once(
    r'verified: "github.com/[^/]+/[^/]+/"',
    f'verified: "github.com/{repo}/"',
    "verified URL",
)
replace_once(
    r'homepage "https://github.com/[^/]+/[^"]+"',
    f'homepage "https://github.com/{repo}"',
    "homepage",
)
path.write_text(text, encoding="utf-8")
PY

ruby -c "$SOURCE_CASK" >/dev/null
mkdir -p "$(dirname "$TAP_CASK")"
cp "$SOURCE_CASK" "$TAP_CASK"

log_step "5. Running Homebrew checks in tap"
(
  cd "$TAP_DIR"
  HOMEBREW_CACHE="${HOMEBREW_CACHE:-/private/tmp/homebrew-cache}" \
    brew style --cask "$TAP_CASK_REL"

  if [[ "$RUN_BREW_AUDIT" -eq 1 ]]; then
    HOMEBREW_CACHE="${HOMEBREW_CACHE:-/private/tmp/homebrew-cache}" \
      brew audit --cask --new "$TAP_CASK_REL"
  else
    echo "Skipping brew audit because --skip-brew-audit was passed."
  fi
)

if [[ "$PUBLISH_RELEASE" -eq 1 ]]; then
  log_step "6. Publishing GitHub release asset"
  TARGET_COMMIT="$(git rev-parse HEAD)"
  if ! gh api "repos/$REPO/commits/$TARGET_COMMIT" >/dev/null; then
    cat >&2 <<MESSAGE
Commit $TARGET_COMMIT is not available on GitHub repo $REPO.

Push the source branch first, then rerun this script.
MESSAGE
    exit 1
  fi

  REMOTE_TAG_SHA=""
  if REMOTE_TAG_SHA="$(remote_tag_commit_sha 2>/dev/null)"; then
    if [[ "$REMOTE_TAG_SHA" != "$TARGET_COMMIT" ]]; then
      cat >&2 <<MESSAGE
Remote tag $TAG points at $REMOTE_TAG_SHA, but this checkout is $TARGET_COMMIT.

Use a new version or move the tag deliberately before publishing.
MESSAGE
      exit 1
    fi
  fi

  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    if [[ -z "$REMOTE_TAG_SHA" ]]; then
      echo "Release $TAG exists, but the remote tag could not be resolved." >&2
      exit 1
    fi

    asset_name="$(
      gh release view "$TAG" \
        --repo "$REPO" \
        --json assets \
        --jq ".assets[] | select(.name == \"$ZIP_NAME\") | .name"
    )"
    if [[ -n "$asset_name" ]]; then
      release_tmp="$(mktemp -d)"
      gh release download "$TAG" \
        --repo "$REPO" \
        --pattern "$ZIP_NAME" \
        --dir "$release_tmp"
      REMOTE_SHA="$(shasum -a 256 "$release_tmp/$ZIP_NAME" | awk '{print $1}')"
      rm -rf -- "$release_tmp"
      if [[ "$REMOTE_SHA" != "$SHA" ]]; then
        cat >&2 <<MESSAGE
Release asset already exists but has a different SHA.

Local SHA:  $SHA
Remote SHA: $REMOTE_SHA

Use a new version instead of replacing bytes behind an existing cask URL.
MESSAGE
        exit 1
      fi
      echo "Release asset already exists and matches SHA; leaving it unchanged."
    else
      gh release upload "$TAG" "$ZIP_PATH" --repo "$REPO"
    fi
  else
    if [[ -n "$REMOTE_TAG_SHA" ]]; then
      gh release create "$TAG" "$ZIP_PATH" \
        --repo "$REPO" \
        --verify-tag \
        --title "CodexPetBar $VERSION" \
        --notes "Homebrew cask release for CodexPetBar $VERSION."
    else
      gh release create "$TAG" "$ZIP_PATH" \
        --repo "$REPO" \
        --target "$TARGET_COMMIT" \
        --title "CodexPetBar $VERSION" \
        --notes "Homebrew cask release for CodexPetBar $VERSION."
    fi
  fi
else
  log_step "6. Skipping GitHub release upload"
  echo "To publish the release asset, rerun with --publish-release."
fi

if [[ "$PUSH_TAP" -eq 1 ]]; then
  log_step "7. Committing and pushing tap cask"
  (
    cd "$TAP_DIR"
    echo "Tap diff:"
    git diff -- "$TAP_CASK_REL"
    git add "$TAP_CASK_REL"
    if git diff --cached --quiet; then
      echo "No tap cask changes to commit."
    else
      git commit -m "Update codex-pet-bar $VERSION"
      git push origin "$TAP_BRANCH"
    fi
  )
else
  log_step "7. Skipping tap push"
  echo "Tap cask updated locally at: $TAP_CASK"
  echo "To push the tap, rerun with --push-tap."
fi

cat <<SUMMARY

Ready artifacts:
  Zip:        $ZIP_PATH
  SHA:        $SHA
  Source cask:$SOURCE_CASK
  Tap cask:   $TAP_CASK

Install command after release + tap push:
  brew tap $TAP_TOKEN
  brew install --cask codex-pet-bar
  codex-pet-bar --add-codex-hooks
SUMMARY

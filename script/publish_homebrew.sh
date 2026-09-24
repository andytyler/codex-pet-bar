#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="/opt/homebrew/Library/Taps/andytyler/homebrew-tap"
REPO="andytyler/codex-pet-bar"
OUTPUT_DIR="/private/tmp/codexpet-release"
BUMP="patch"
VERSION=""
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-codex-pet-bar-notary}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"
DRY_RUN=0
ASSUME_YES=0

usage() {
  cat <<USAGE
Usage: script/publish_homebrew.sh [options]

Build, publish, and push a CodexPetBar Homebrew cask release. The script prints
each command before running it, prints OK after success, and stops on the first
failure.

Options:
      --dry-run                  Test and prepare artifacts/cask; do not commit, push, or publish
                                  Signing/notarization still run when requested.
      --yes                      Skip the interactive publication confirmation
      --version <x.y.z>          Use an explicit version
      --bump <patch|minor|major> Auto-bump latest vX.Y.Z git tag. Default: patch
      --tap-dir <path>           Local tap checkout. Default: $TAP_DIR
      --repo <owner/repo>        GitHub repo. Default: $REPO
      --output-dir <path>        Release output dir. Default: $OUTPUT_DIR
      --sign <identity>          Developer ID Application signing identity
      --notarize                 Submit the signed app to Apple's notary service and staple the ticket
      --notary-profile <profile> notarytool keychain profile. Default: codex-pet-bar-notary
      --notary-timeout <duration>
                                  notarytool wait timeout. Default: 30m
  -h, --help                     Show this help

Examples:
  script/publish_homebrew.sh
  script/publish_homebrew.sh --bump minor
  script/publish_homebrew.sh --version 0.1.1
  script/publish_homebrew.sh --sign "Developer ID Application: Example (TEAMID)" --notarize
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --version)
      VERSION="${2:?missing value for $1}"
      shift 2
      ;;
    --bump)
      BUMP="${2:?missing value for $1}"
      shift 2
      ;;
    --tap-dir)
      TAP_DIR="${2:?missing value for $1}"
      shift 2
      ;;
    --repo)
      REPO="${2:?missing value for $1}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:?missing value for $1}"
      shift 2
      ;;
    --sign)
      SIGN_IDENTITY="${2:?missing value for $1}"
      shift 2
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --notary-profile)
      NOTARY_KEYCHAIN_PROFILE="${2:?missing value for $1}"
      shift 2
      ;;
    --notary-timeout)
      NOTARY_TIMEOUT="${2:?missing value for $1}"
      shift 2
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

fail() {
  local status="$1"
  local command="$2"
  echo "FAIL ($status): $command" >&2
  exit "$status"
}

run() {
  local display="$*"
  echo
  echo "+ $display"
  "$@"
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    fail "$status" "$display"
  fi
  echo "OK: $display"
}

run_shell() {
  local command="$1"
  echo
  echo "+ $command"
  bash -o pipefail -c "$command"
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    fail "$status" "$command"
  fi
  echo "OK: $command"
}

next_version() {
  local latest="$1"
  local bump="$2"
  local major minor patch

  IFS=. read -r major minor patch <<< "$latest"
  case "$bump" in
    patch)
      patch=$((patch + 1))
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    *)
      echo "--bump must be patch, minor, or major" >&2
      exit 2
      ;;
  esac

  printf "%s.%s.%s\n" "$major" "$minor" "$patch"
}

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$ ]]; then
    echo "VERSION must be strict semver x.y.z without leading zeroes: $version" >&2
    exit 2
  fi
}

cd "$ROOT_DIR" || exit 1

if [[ "$NOTARIZE" != "0" && "$NOTARIZE" != "1" ]]; then
  echo "NOTARIZE must be 0 or 1." >&2
  exit 2
fi
case "$BUMP" in patch|minor|major) ;; *) echo "--bump must be patch, minor, or major" >&2; exit 2 ;; esac
if [[ -n "$VERSION" ]]; then
  validate_version "$VERSION"
fi
if [[ "$DRY_RUN" -eq 0 && ( -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" || "$NOTARIZE" -ne 1 ) ]]; then
  echo "Publishing requires a Developer ID identity and --notarize. Use --dry-run to prepare an unsigned test build." >&2
  exit 2
fi

run git fetch origin main --tags
[[ "$(git branch --show-current)" == "main" ]] || fail 1 "Release from main"
[[ -z "$(git status --porcelain)" ]] || fail 1 "Commit all intended source changes before releasing"
SOURCE_SHA="$(git rev-parse HEAD)" || exit 1
[[ "$SOURCE_SHA" == "$(git rev-parse origin/main)" ]] || fail 1 "Source HEAD must match fetched origin/main"
ORIGIN_URL="$(git remote get-url origin)" || exit 1
case "$ORIGIN_URL" in
  "https://github.com/$REPO"|"https://github.com/$REPO.git"|"git@github.com:$REPO"|"git@github.com:$REPO.git") ;;
  *) fail 1 "Source remote does not match GitHub repository $REPO" ;;
esac

# Refresh remote tags before deriving a new version.
if [[ -z "$VERSION" ]]; then
  LATEST="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | sed 's/^v//' | grep -E '^[0-9]+[.][0-9]+[.][0-9]+$' | head -n 1)"
  VERSION="$(next_version "${LATEST:-0.0.0}" "$BUMP")"
fi
validate_version "$VERSION"
if git show-ref --verify --quiet "refs/tags/v$VERSION"; then
  fail 1 "Tag v$VERSION already exists"
fi
REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/v$VERSION")" || exit 1
[[ -z "$REMOTE_TAG" ]] || fail 1 "Remote tag v$VERSION already exists"

if [[ "$DRY_RUN" -eq 0 ]]; then
  run gh auth status
  run git -C "$TAP_DIR" fetch origin main
  [[ "$(git -C "$TAP_DIR" branch --show-current)" == "main" ]] || fail 1 "Tap must be on main"
  [[ -z "$(git -C "$TAP_DIR" status --porcelain)" ]] || fail 1 "Tap must be clean"
  [[ "$(git -C "$TAP_DIR" rev-parse HEAD)" == "$(git -C "$TAP_DIR" rev-parse origin/main)" ]] || fail 1 "Tap must match fetched origin/main"
fi

run mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)" || exit 1
ZIP="$OUTPUT_DIR/CodexPetBar-$VERSION-macos.zip"
LATEST_ZIP="$OUTPUT_DIR/CodexPetBar-macos.zip"
STAGED_CASK="$OUTPUT_DIR/codex-pet-bar.rb"
echo "Preparing CodexPetBar $VERSION from $SOURCE_SHA"
echo "Artifacts: $OUTPUT_DIR"

TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/codexpet-release-tests.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_HOME"' EXIT
TEST_ENV=(env HOME="$TEST_HOME" CODEX_HOME="$TEST_HOME/.codex" CLAUDE_CONFIG_DIR="$TEST_HOME/.claude" CURSOR_CONFIG_DIR="$TEST_HOME/.cursor" CODEX_PET_EVENT_LOG="$TEST_HOME/pet-events.jsonl" CODEX_PET_EVENT_ROOT="$TEST_HOME" PYTHONDONTWRITEBYTECODE=1)
run swift test --build-system native
run "${TEST_ENV[@]}" python3 -m unittest discover -s Tests/InstallHooksTests -p 'test_*.py'
run "${TEST_ENV[@]}" python3 -m unittest discover -s Tests/HomebrewReleaseTests -p 'test_*.py'
package_args=(env VERSION="$VERSION" ./script/package_app.sh --configuration release --zip --output "$OUTPUT_DIR")
if [[ -n "$SIGN_IDENTITY" ]]; then
  package_args+=(--sign "$SIGN_IDENTITY")
fi
if [[ "$NOTARIZE" -eq 1 ]]; then
  package_args+=(--notarize --notary-profile "$NOTARY_KEYCHAIN_PROFILE" --notary-timeout "$NOTARY_TIMEOUT")
fi
run "${package_args[@]}"
PACKAGED_APP="$(cat "$OUTPUT_DIR/CodexPetBar-app-path.txt")" || exit 1
run python3 ./script/smoke_package.py "$PACKAGED_APP"
run test -f "$ZIP"
run test -f "$LATEST_ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')" || exit 1
run cp Casks/codex-pet-bar.rb "$STAGED_CASK"
run env VERSION="$VERSION" SHA="$SHA" ruby -pi -e 'gsub(/version "[^"]+"/, "version \"#{ENV.fetch("VERSION")}\""); gsub(/sha256 "[^"]+"/, "sha256 \"#{ENV.fetch("SHA")}\"")' "$STAGED_CASK"
run ruby -c "$STAGED_CASK"
run brew style --cask "$STAGED_CASK"
run env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 brew ruby "$ROOT_DIR/script/audit_cask.rb" "$STAGED_CASK"
printf 'Source: %s\nVersion: %s\nSHA256: %s\n' "$SOURCE_SHA" "$VERSION" "$SHA" >"$OUTPUT_DIR/release-manifest.txt"
[[ "$(git rev-parse HEAD)" == "$SOURCE_SHA" && -z "$(git status --porcelain)" ]] || fail 1 "Source changed during release preparation"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Release preparation complete. No commits, pushes, or GitHub release were created."
  echo "Cask: $STAGED_CASK"
  exit 0
fi

# Confirm only once complete artifacts exist for review.
echo "Ready to publish CodexPetBar $VERSION ($SHA)."
if [[ "$ASSUME_YES" -eq 0 ]]; then
  read -r -p "Publish these prepared artifacts? [y/N] " CONFIRM
  case "$CONFIRM" in y|Y|yes|YES) ;; *) echo "Cancelled; prepared artifacts remain in $OUTPUT_DIR."; exit 1 ;; esac
fi
REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/v$VERSION")" || exit 1
[[ -z "$REMOTE_TAG" ]] || fail 1 "Remote tag v$VERSION appeared during release preparation"
run cp "$STAGED_CASK" Casks/codex-pet-bar.rb
run git add Casks/codex-pet-bar.rb
run git commit -m "Release codex-pet-bar $VERSION"
RELEASE_SHA="$(git rev-parse HEAD)" || exit 1
run git push origin main
run gh release create "v$VERSION" "$ZIP" "$LATEST_ZIP" --repo "$REPO" --target "$RELEASE_SHA" --title "CodexPetBar $VERSION" --notes "Homebrew cask release for CodexPetBar $VERSION. Source: $SOURCE_SHA."

run cd "$TAP_DIR"
run git pull --ff-only
run mkdir -p Casks
run cp "$STAGED_CASK" Casks/codex-pet-bar.rb
run cmp "$STAGED_CASK" Casks/codex-pet-bar.rb
run git add Casks/codex-pet-bar.rb
run git commit -m "Update codex-pet-bar $VERSION"
run git push origin main

echo "Release complete. Install with: brew install --cask andytyler/tap/codex-pet-bar"

#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="/opt/homebrew/Library/Taps/andytyler/homebrew-tap"
REPO="andytyler/codex-pet-bar"
OUTPUT_DIR="/private/tmp/codexpet-release"
BUMP="patch"
VERSION=""

usage() {
  cat <<USAGE
Usage: script/release_homebrew.sh [options]

Thin release wrapper. It runs the same commands from docs/releasing.md, prints
each command before running it, prints OK after success, and stops on the first
failure.

Options:
      --version <x.y.z>          Use an explicit version
      --bump <patch|minor|major> Auto-bump latest vX.Y.Z git tag. Default: patch
      --tap-dir <path>           Local tap checkout. Default: $TAP_DIR
      --repo <owner/repo>        GitHub repo. Default: $REPO
      --output-dir <path>        Release output dir. Default: $OUTPUT_DIR
  -h, --help                     Show this help

Examples:
  script/release_homebrew.sh
  script/release_homebrew.sh --bump minor
  script/release_homebrew.sh --version 0.1.1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

cd "$ROOT_DIR" || exit 1

if [[ -z "$VERSION" ]]; then
  LATEST="$(
    git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname \
      | sed 's/^v//' \
      | grep -E '^[0-9]+[.][0-9]+[.][0-9]+$' \
      | head -n 1
  )"
  LATEST="${LATEST:-0.0.0}"
  VERSION="$(next_version "$LATEST" "$BUMP")"
fi

ZIP="$OUTPUT_DIR/CodexPetBar-$VERSION-macos.zip"

echo "Releasing CodexPetBar $VERSION"
echo "Source repo: $ROOT_DIR"
echo "Tap repo:    $TAP_DIR"
echo "Zip:         $ZIP"

read -r -p "Continue? [y/N] " CONFIRM
case "$CONFIRM" in
  y|Y|yes|YES) ;;
  *) echo "Cancelled."; exit 1 ;;
esac

run git status --short
run git fetch origin main --tags
run_shell 'test "$(git branch --show-current)" = "main"'
run_shell 'test -z "$(git status --porcelain)"'
run swift test
run python3 -m unittest discover -s Tests/InstallHooksTests -p 'test_*.py'
run swift build -c release
run rm -rf "$OUTPUT_DIR"
run env VERSION="$VERSION" ./script/package_app.sh --configuration release --zip --output "$OUTPUT_DIR"
run test -f "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "SHA: $SHA"

run_shell "VERSION='$VERSION' SHA='$SHA' ruby -pi -e 'gsub(/version \"[^\"]+\"/, \"version \\\"#{ENV[\"VERSION\"]}\\\"\"); gsub(/sha256 \"[^\"]+\"/, \"sha256 \\\"#{ENV[\"SHA\"]}\\\"\")' Casks/codex-pet-bar.rb"
run ruby -c Casks/codex-pet-bar.rb
run git diff -- Casks/codex-pet-bar.rb
run git add Casks/codex-pet-bar.rb
run git commit -m "Release codex-pet-bar $VERSION"
run git push origin main
run gh release create "v$VERSION" "$ZIP" --repo "$REPO" --target main --title "CodexPetBar $VERSION" --notes "Homebrew cask release for CodexPetBar $VERSION."

run cd "$TAP_DIR"
run git pull --ff-only
run mkdir -p Casks
run cp "$ROOT_DIR/Casks/codex-pet-bar.rb" Casks/codex-pet-bar.rb
run brew style --cask Casks/codex-pet-bar.rb
run brew audit --cask --new Casks/codex-pet-bar.rb
run git add Casks/codex-pet-bar.rb
run git commit -m "Update codex-pet-bar $VERSION"
run git push origin main

echo
echo "Release complete."
echo "Install with:"
echo "  brew install --cask andytyler/tap/codex-pet-bar"

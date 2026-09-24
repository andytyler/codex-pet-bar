#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPetBar"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
OPEN_AFTER_INSTALL=0
INSTALL_HOOKS=0
HOOK_ARGS=()

usage() {
  cat <<USAGE
Usage: script/install.sh [options]

Builds CodexPetBar and installs it into ~/Applications by default.

Options:
  --install-dir <directory>    Destination directory. Default: ~/Applications
  --with-hooks [workspace]     Also install Codex pet hooks. Defaults to global hooks.
  --with-all-hooks             Install global Codex, Claude Code, and Cursor pet hooks.
  --with-workspace-hooks <dir> Also install workspace-local Codex pet hooks
  --open                       Open the app after installing
  -h, --help                   Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:?missing value for $1}"
      shift 2
      ;;
    --with-hooks)
      INSTALL_HOOKS=1
      if [[ $# -ge 2 && "$2" != --* ]]; then
        HOOK_ARGS=("$2")
        shift 2
      else
        HOOK_ARGS=()
        shift
      fi
      ;;
    --with-workspace-hooks)
      INSTALL_HOOKS=1
      HOOK_ARGS=("--workspace" "${2:?missing value for $1}")
      shift 2
      ;;
    --with-all-hooks)
      INSTALL_HOOKS=1
      HOOK_ARGS=("--provider" "all")
      shift
      ;;
    --open)
      OPEN_AFTER_INSTALL=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codexpetbar-install.XXXXXX")"
STAGING_DIR=""
cleanup() {
  rm -rf "$PACKAGE_DIR"
  if [[ -n "$STAGING_DIR" ]]; then
    if [[ ( -e "$STAGING_DIR/previous.app" || -L "$STAGING_DIR/previous.app" ) && ! -e "$INSTALLED_APP" && ! -L "$INSTALLED_APP" ]]; then
      echo "Previous app preserved for recovery: $STAGING_DIR/previous.app" >&2
    else
      rm -rf "$STAGING_DIR"
    fi
  fi
}
trap cleanup EXIT
APP_BUNDLE="$PACKAGE_DIR/$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"

"$SCRIPT_DIR/package_app.sh" --configuration release --output "$PACKAGE_DIR"

mkdir -p "$INSTALL_DIR"
STAGING_DIR="$(mktemp -d "$INSTALL_DIR/.codexpetbar-install.XXXXXX")"
ditto "$APP_BUNDLE" "$STAGING_DIR/new.app"
if [[ -e "$INSTALLED_APP" || -L "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$STAGING_DIR/previous.app"
fi
if ! mv "$STAGING_DIR/new.app" "$INSTALLED_APP"; then
  if [[ -e "$STAGING_DIR/previous.app" || -L "$STAGING_DIR/previous.app" ]]; then
    mv "$STAGING_DIR/previous.app" "$INSTALLED_APP"
  fi
  exit 1
fi
CODEX_PETS_DIR="$(/usr/bin/python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from install_hooks import codex_home; print(codex_home() / "pets")' "$SCRIPT_DIR")"
mkdir -p "$CODEX_PETS_DIR"

if [[ "$INSTALL_HOOKS" -eq 1 ]]; then
  "$SCRIPT_DIR/install_hooks.py" "${HOOK_ARGS[@]}"
fi

if [[ "$OPEN_AFTER_INSTALL" -eq 1 ]]; then
  /usr/bin/open "$INSTALLED_APP"
fi

cat <<MESSAGE
Installed: $INSTALLED_APP
Pets folder: $CODEX_PETS_DIR

To enable richer Codex activity events globally:
  $SCRIPT_DIR/install_hooks.py

To enable Codex, Claude Code, and Cursor together:
  $SCRIPT_DIR/install_hooks.py --provider all
MESSAGE

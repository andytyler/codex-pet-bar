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
PACKAGE_DIR="${TMPDIR:-/tmp}/codexpetbar-install"
APP_BUNDLE="$PACKAGE_DIR/$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"

rm -rf "$PACKAGE_DIR"
"$SCRIPT_DIR/package_app.sh" --configuration release --output "$PACKAGE_DIR"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
ditto "$APP_BUNDLE" "$INSTALLED_APP"
mkdir -p "$HOME/.codex/pets"

if [[ "$INSTALL_HOOKS" -eq 1 ]]; then
  "$SCRIPT_DIR/install_hooks.py" "${HOOK_ARGS[@]}"
fi

if [[ "$OPEN_AFTER_INSTALL" -eq 1 ]]; then
  /usr/bin/open -n "$INSTALLED_APP"
fi

cat <<MESSAGE
Installed: $INSTALLED_APP
Pets folder: $HOME/.codex/pets

To enable richer Codex activity events globally:
  $SCRIPT_DIR/install_hooks.py
MESSAGE

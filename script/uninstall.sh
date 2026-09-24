#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPetBar"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "$INSTALLED_APP" ]]; then
  rm -rf "$INSTALLED_APP"
  echo "Removed: $INSTALLED_APP"
else
  echo "No installed app found at: $INSTALLED_APP"
fi

if [[ -f "$SCRIPT_DIR/install_hooks.py" ]]; then
  if "$SCRIPT_DIR/install_hooks.py" --provider all --remove-global; then
    echo "Removed CodexPetBar global hook entries for all supported providers where present."
  else
    echo "Could not remove CodexPetBar global hook entries. You can retry with:" >&2
    echo "  $SCRIPT_DIR/install_hooks.py --provider all --remove-global" >&2
  fi
fi

CODEX_CONFIG_DIR="$(/usr/bin/python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from install_hooks import codex_home; print(codex_home())' "$SCRIPT_DIR")"
CLAUDE_SETTINGS="$(/usr/bin/python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from install_hooks import claude_settings_path; print(claude_settings_path())' "$SCRIPT_DIR")"
CURSOR_HOOKS="$(/usr/bin/python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from install_hooks import cursor_hooks_path; print(cursor_hooks_path())' "$SCRIPT_DIR")"

cat <<MESSAGE
Custom pets were left in place.

Pets folder:
  $CODEX_CONFIG_DIR/pets

Global CodexPetBar hook entries are removed from:
  $CODEX_CONFIG_DIR/hooks.json
  $CLAUDE_SETTINGS
  $CURSOR_HOOKS

The copied hook script and empty event log are removed only when safe.

Workspace-local hook files, if installed:
  <workspace>/.codex/hooks.json
  <workspace>/.codex/hooks/codex_pet_event.py

Remove workspace-local hooks with:
  $SCRIPT_DIR/install_hooks.py --remove-workspace <workspace>
MESSAGE

#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPetBar"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"

if [[ -d "$INSTALLED_APP" ]]; then
  rm -rf "$INSTALLED_APP"
  echo "Removed: $INSTALLED_APP"
else
  echo "No installed app found at: $INSTALLED_APP"
fi

cat <<MESSAGE
Custom pets and Codex hook files were left in place.

Pets folder:
  $HOME/.codex/pets

Global hook files, if installed:
  $HOME/.codex/hooks.json
  $HOME/.codex/hooks/codex_pet_event.py
  $HOME/.codex/pet-events.jsonl

Workspace-local hook files, if installed:
  <workspace>/.codex/hooks.json
  <workspace>/.codex/hooks/codex_pet_event.py
MESSAGE

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: script/install_pet.sh <pet-directory>

Installs a validated pet package into ~/.codex/pets/<pet-id>.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PET_DIR="$1"

"$SCRIPT_DIR/validate_pet.py" "$PET_DIR"
PET_ID="$("$SCRIPT_DIR/validate_pet.py" --print-id "$PET_DIR")"
DEST_DIR="$HOME/.codex/pets/$PET_ID"

mkdir -p "$(dirname "$DEST_DIR")"
rm -rf "$DEST_DIR"
ditto "$PET_DIR" "$DEST_DIR"

echo "Installed pet: $DEST_DIR"
echo "Use the CodexPetBar menu to Refresh Pets, then select $PET_ID."

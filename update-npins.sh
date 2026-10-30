#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [npins-update-flags/names...]"
  echo "Updates every npins lock under dot-base. Arguments are passed to 'npins update'."
  exit 0
fi

run_npins() {
  if command -v npins >/dev/null 2>&1; then
    npins "$@"
  elif command -v nix >/dev/null 2>&1; then
    nix shell nixpkgs#npins -c npins "$@"
  else
    echo "Error: neither npins nor nix command was found." >&2
    exit 1
  fi
}

mapfile -d '' NPINS_DIRS < <(
  find "$SCRIPT_DIR" \
    -path "$SCRIPT_DIR/.git" -prune -o \
    -path "$SCRIPT_DIR/docs" -prune -o \
    -type d -name npins -print0
)

if [[ ${#NPINS_DIRS[@]} -eq 0 ]]; then
  echo "No npins directories found under $SCRIPT_DIR."
  exit 0
fi

for npins_dir in "${NPINS_DIRS[@]}"; do
  work_dir="$(dirname "$npins_dir")"
  echo "=========================================="
  echo "Updating npins in: ${work_dir#"$SCRIPT_DIR"/}"
  echo "=========================================="
  (
    cd "$work_dir"
    run_npins upgrade
    run_npins update "$@"
  )
done

echo "Updated npins dependencies under $SCRIPT_DIR."

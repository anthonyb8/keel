#!/usr/bin/env bash
# Point every live path keel owns at its file in this repository, so editing
# the live path edits the repository. Idempotent: safe to re-run, and
# re-running repairs a link an application replaced with a regular file.
#
#   install.sh            link everything
#   install.sh --check    report drift without changing anything
#
# keel owns ~/.keel/claude and ~/.local/bin/keel, and writes nothing else:
# harness's paths stay exactly as they are. A displaced regular file is kept
# next to its live path as <name>.bak.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$HOME/.keel/claude"
MODE="link"
DRIFT=0

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"
  exit "${1:-0}"
}

PAIRS=(
  "$ROOT/rules/CLAUDE.md|$CONFIG/CLAUDE.md"
  "$ROOT/rules/OPINIONS.md|$CONFIG/OPINIONS.md"
  "$ROOT/rules/VOICE.md|$CONFIG/VOICE.md"
  "$ROOT/rails/settings.json|$CONFIG/settings.json"
  "$ROOT/rails/bin/keel|$HOME/.local/bin/keel"
)

link_one() {
  local repo="$1" live="$2"
  if [[ -L "$live" && "$(readlink "$live")" == "$repo" ]]; then
    return
  fi
  if [[ "$MODE" == check ]]; then
    if [[ -L "$live" ]]; then
      echo "WRONG LINK: $live -> $(readlink "$live")"
    elif [[ -e "$live" ]]; then
      echo "NOT LINKED: $live is a regular file"
    else
      echo "MISSING: $live"
    fi
    DRIFT=$((DRIFT + 1))
    return
  fi
  mkdir -p "$(dirname "$live")"
  if [[ -L "$live" ]]; then
    echo "relinked $live (was -> $(readlink "$live"))"
    rm "$live"
  elif [[ -e "$live" ]]; then
    rm -rf "$live.bak"
    mv "$live" "$live.bak"
    echo "linked   $live (previous copy at $live.bak)"
  else
    echo "linked   $live"
  fi
  ln -s "$repo" "$live"
}

case "${1:-}" in
-h | --help) usage 0 ;;
--check) MODE=check ;;
"") ;;
*) usage 1 ;;
esac

for pair in "${PAIRS[@]}"; do
  link_one "${pair%%|*}" "${pair##*|}"
done

if [[ "$MODE" == check ]]; then
  echo "$DRIFT item(s) need attention."
  [[ "$DRIFT" -eq 0 ]]
fi

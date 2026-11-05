#!/usr/bin/env bash
# Point every live path keel owns at its file in this repository, so editing
# the live path edits the repository. Idempotent: safe to re-run, and
# re-running repairs a link an application replaced with a regular file.
#
#   install.sh            link everything
#   install.sh --check    report drift without changing anything
#
# keel owns ~/.keel and ~/.local/bin/keel, and writes nothing else:
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
  "$ROOT/method|$HOME/.keel/method"
  "$ROOT/trust|$HOME/.keel/trust"
)

# Each skill and agent is linked on its own into real directories, so what
# Claude Code installs there never lands in the repository.
method_pairs() {
  local s a
  for s in "$ROOT"/method/skills/*/ "$ROOT"/trust/skills/*/; do
    [[ -f "$s/SKILL.md" ]] || continue
    s="${s%/}"
    echo "$s|$CONFIG/skills/$(basename "$s")"
  done
  for a in "$ROOT"/method/agents/*.md; do
    [[ -f "$a" ]] || continue
    echo "$a|$CONFIG/agents/$(basename "$a")"
  done
}

# A skill or agent dropped from the repository leaves a dangling link behind.
prune() {
  local l
  for l in "$CONFIG"/skills/* "$CONFIG"/agents/*; do
    [[ -L "$l" && ! -e "$l" ]] || continue
    if [[ "$MODE" == check ]]; then
      echo "DANGLING: $l"
      DRIFT=$((DRIFT + 1))
    else
      rm "$l"
      echo "removed  $l (it is gone from the repository)"
    fi
  done
}

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
while IFS= read -r pair; do
  link_one "${pair%%|*}" "${pair##*|}"
done < <(method_pairs)
prune

if [[ "$MODE" == check ]]; then
  echo "$DRIFT item(s) need attention."
  [[ "$DRIFT" -eq 0 ]]
fi

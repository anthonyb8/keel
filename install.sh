#!/usr/bin/env bash
# Make this copy of keel the one every session runs: point ~/.keel/current at
# it, and every live path keel owns at its file through ~/.keel/current, so
# the next switch is that one link. The personal paths point at ~/.keel/you.
# Idempotent: safe to re-run, and re-running repairs a link an application
# replaced with a regular file. `keel update`, `keel rollback` and `keel use`
# all switch by running the target copy's install.sh.
#
#   install.sh            link everything
#   install.sh --check    report drift without changing anything
#
# keel owns ~/.keel and ~/.local/bin/keel, and writes nothing else:
# harness's paths stay exactly as they are. A displaced regular file is kept
# next to its live path as <name>.bak.
#
# ~/.keel/you holds the user's own rules, voice, opinions and settings, made by
# `keel init` when it is missing and never overwritten. keel's settings are
# merged into ~/.keel/you/settings.json rather than linked, since Claude Code
# writes to that file itself.
set -uo pipefail

# The real path, so running ~/.keel/current/install.sh never points current at itself.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG="$HOME/.keel/claude"
YOU="$HOME/.keel/you"
# The keel settings last merged into the user's, so the next merge knows which
# entries are keel's to take out.
MERGED="$HOME/.keel/rails.json"
# The copy of keel sessions run, and the one it replaced, for `keel rollback`.
CURRENT="$HOME/.keel/current"
PREVIOUS="$HOME/.keel/previous"
MODE="link"
DRIFT=0

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"
  exit "${1:-0}"
}

PAIRS=(
  "$CURRENT/rules/keel.md|$CONFIG/CLAUDE.md"
  "$YOU/OPINIONS.md|$CONFIG/OPINIONS.md"
  "$YOU/VOICE.md|$CONFIG/VOICE.md"
  "$YOU/settings.json|$CONFIG/settings.json"
  "$CURRENT/rails/bin/keel|$HOME/.local/bin/keel"
  "$CURRENT/method|$HOME/.keel/method"
  "$CURRENT/trust|$HOME/.keel/trust"
)

# Each skill and agent is linked on its own into real directories, so what
# Claude Code installs there never lands in the repository.
method_pairs() {
  local s a
  for s in "$ROOT"/method/skills/*/ "$ROOT"/trust/skills/*/ "$ROOT"/learning/skills/*/; do
    [[ -f "$s/SKILL.md" ]] || continue
    s="${s%/}"
    echo "$CURRENT/${s#"$ROOT"/}|$CONFIG/skills/$(basename "$s")"
  done
  for a in "$ROOT"/method/agents/*.md; do
    [[ -f "$a" ]] || continue
    echo "$CURRENT/${a#"$ROOT"/}|$CONFIG/agents/$(basename "$a")"
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

# Merges keel's settings into the user's in three steps: take out what the
# previous keel settings added, keep everything else, add the new ones. Lists
# are sets: an entry keel no longer has goes, and the user's own entries and
# Claude Code's writes stay. A value keel sets is the user's once they change
# it. Running with the settings of an older keel undoes a newer one's.
# shellcheck disable=SC2016 # a jq program, its $names are jq's
MERGE_JQ='
def has_entry($x): any(.[]; . == $x);
def strip($o):
  if type == "object" and ($o | type) == "object" then
    with_entries(.key as $k | if $o | has($k) then .value |= strip($o[$k]) else . end)
    | with_entries(select(.value != null))
  elif type == "array" and ($o | type) == "array" then
    map(select(. as $x | $o | has_entry($x) | not))
  elif . == $o then null
  else . end;
def add($n):
  if type == "object" and ($n | type) == "object" then
    reduce ($n | keys_unsorted[]) as $k (.; if has($k) then .[$k] |= add($n[$k]) else .[$k] = $n[$k] end)
  elif type == "array" and ($n | type) == "array" then
    . as $l | . + [$n[] | select(. as $x | $l | has_entry($x) | not)]
  else . end;
strip($old) | add($new[0])
'

merge_settings() {
  local live="$YOU/settings.json" old='{}' want tmp
  [[ -f "$MERGED" ]] && old=$(cat "$MERGED")
  if ! want=$(jq --argjson old "$old" --slurpfile new "$ROOT/rails/settings.json" "$MERGE_JQ" "$live"); then
    echo "BROKEN: $live is not valid JSON; fix it and run install.sh again" >&2
    DRIFT=$((DRIFT + 1))
    return
  fi
  if [[ "$(jq -S . <<<"$want")" == "$(jq -S . "$live")" ]] &&
    cmp -s "$ROOT/rails/settings.json" "$MERGED"; then
    return
  fi
  if [[ "$MODE" == check ]]; then
    echo "NOT MERGED: keel's settings into $live"
    DRIFT=$((DRIFT + 1))
    return
  fi
  tmp=$(mktemp "$live.XXXXXX")
  echo "$want" >"$tmp" && mv "$tmp" "$live"
  cp "$ROOT/rails/settings.json" "$MERGED"
  echo "merged   keel's settings into $live"
}

# Swaps ~/.keel/current to this copy in one rename, so no session ever sees it
# missing, and keeps the copy it replaced as ~/.keel/previous.
switch_current() {
  local was tmp
  was=$(readlink "$CURRENT" 2>/dev/null) || was=""
  [[ "$was" == "$ROOT" ]] && return
  if [[ "$MODE" == check ]]; then
    echo "NOT CURRENT: $CURRENT -> ${was:-nothing}, not $ROOT"
    DRIFT=$((DRIFT + 1))
    return
  fi
  mkdir -p "$(dirname "$CURRENT")"
  if [[ -n "$was" ]]; then
    tmp="$PREVIOUS.$$"
    ln -sfn "$was" "$tmp" && mv -T "$tmp" "$PREVIOUS"
  fi
  tmp="$CURRENT.$$"
  ln -sfn "$ROOT" "$tmp" && mv -T "$tmp" "$CURRENT"
  echo "current  $CURRENT -> $ROOT"
}

case "${1:-}" in
-h | --help) usage 0 ;;
--check) MODE=check ;;
"") ;;
*) usage 1 ;;
esac

if [[ "$MODE" == check ]]; then
  for f in "$ROOT"/templates/you/*; do
    [[ -e "$YOU/${f##*/}" ]] && continue
    echo "MISSING: $YOU/${f##*/}, which \`keel init\` makes"
    DRIFT=$((DRIFT + 1))
  done
else
  "$ROOT/rails/bin/keel" init
fi
[[ -f "$YOU/settings.json" ]] && merge_settings
switch_current

for pair in "${PAIRS[@]}"; do
  link_one "${pair%%|*}" "${pair##*|}"
done
while IFS= read -r pair; do
  link_one "${pair%%|*}" "${pair##*|}"
done < <(method_pairs)
prune

[[ "$MODE" == check ]] && echo "$DRIFT item(s) need attention."
[[ "$DRIFT" -eq 0 ]]

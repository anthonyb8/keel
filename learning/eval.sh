#!/usr/bin/env bash
# Blind evals of a playbook: runs its canned task on the installed keel and on
# a variant checkout, n sessions each, scores every result with the
# playbook's scripted checks and one judge, and writes a result file into the
# variant's learning/evals/results/. Real model calls: run by hand, never in CI.
#
#   keel eval <playbook> [--variant <keel checkout>] [-n <runs>]
#
# Each session runs in its own fixture under a throwaway HOME with that side's
# keel installed, logged in with a copy of ~/.keel/claude/.credentials.json
# that is deleted when the run ends. Sides are labelled by neutral names, so
# nothing a session or the judge sees says which is which, or that it is
# being measured.
set -uo pipefail

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"
  exit "${1:-0}"
}
die() {
  echo "keel eval: $*" >&2
  exit 1
}

INSTALLED="$(dirname "$(dirname "$(dirname "$(readlink -f "$HOME/.local/bin/keel")")")")"
playbook="${1:-}"
[[ -n "$playbook" && "$playbook" != -* ]] || usage 1
shift
variant="$INSTALLED" n=2
while (($#)); do
  case "$1" in
  --variant) variant="$(cd "${2:-}" && pwd)" || die "no such checkout: ${2:-}" && shift 2 ;;
  -n) n="${2:-}" && shift 2 ;;
  -h | --help) usage 0 ;;
  *) usage 1 ;;
  esac
done
[[ "$n" =~ ^[1-9][0-9]*$ ]] || die "-n takes a positive number"
CASE="$variant/learning/evals/$playbook"
[[ -x "$CASE/fixture.sh" && -f "$CASE/prompt.md" && -x "$CASE/checks.sh" && -f "$CASE/rubric.md" ]] ||
  die "no eval for $playbook in $variant/learning/evals"
CREDS="$HOME/.keel/claude/.credentials.json"
[[ -f "$CREDS" ]] || die "keel's login is missing: run \`keel claude\` once and /login there"
CLAUDE_BIN=$(command -v claude) || die "claude is not on PATH"
REAL_HOME="$HOME"

# A work dir whose name says nothing about what it holds.
W=$(mktemp -d "${TMPDIR:-/tmp}/shop.XXXXXX")
# The work dir holds every transcript; it goes when the eval ends, with the
# copied logins, and only the result file is kept.
trap 'rm -rf "$W"' EXIT

# run_one <side checkout> <label>: one session, from fixture to checks.
run_one() {
  local side="$1" label="$2" dir="$W/$2" home sid turn work reply
  home="$dir/home"
  mkdir -p "$home"
  HOME="$home" "$side/install.sh" >/dev/null
  printf '[user]\n\tname = Sam Okafor\n\temail = sam@shop.example\n' >"$home/.gitconfig"
  cp "$CREDS" "$home/.keel/claude/.credentials.json"
  [[ -f "$REAL_HOME/.keel/claude/.claude.json" ]] && cp "$REAL_HOME/.keel/claude/.claude.json" "$home/.keel/claude/.claude.json"
  work=$(HOME="$home" KEEL_BIN="$home/.local/bin/keel" "$side/learning/evals/$playbook/fixture.sh" "$dir") || {
    echo "fixture failed" >"$dir/checks.txt"
    return
  }
  echo "$work" >"$dir/work"
  sid=$(cat /proc/sys/kernel/random/uuid)
  local first=1
  : >"$dir/reply.md"
  # The turns of prompt.md, split on lines holding only ---.
  while IFS= read -r -d '' turn; do
    # No --permission-mode: the session runs under the side's own settings,
    # as a real keel session would, so it can run the specs and the verifier
    # can run things; an override here would measure a different keel.
    local args=(--output-format json)
    if [[ "$first" == 1 ]]; then args+=(--session-id "$sid"); else args+=(--resume "$sid"); fi
    first=0
    reply=$(cd "$work" && HOME="$home" CLAUDE_CONFIG_DIR="$home/.keel/claude" \
      PATH="$dir/bin:$home/.local/bin:$(dirname "$CLAUDE_BIN"):$PATH" \
      "$CLAUDE_BIN" -p "$turn" "${args[@]}" </dev/null 2>"$dir/stderr" | jq -r '.result // empty')
    printf '%s\n\n' "$reply" >>"$dir/reply.md"
  done < <(awk 'BEGIN{RS="\n---\n"} {sub(/\n+$/, ""); printf "%s\0", $0}' "$CASE/prompt.md")
  rm -f "$home/.keel/claude/.credentials.json"
  # keel's rules send a session into a worktree of its own, so the checks and
  # the judge follow it there: the tree it leased last, else where it started.
  local leased
  leased=$(cd "$work" && HOME="$home" treehouse status --json 2>/dev/null |
    jq -r '[.[] | select(.status == "leased")] | last | .path // empty')
  if [[ -n "$leased" ]]; then
    work="$leased"
    echo "$work" >"$dir/work"
  fi
  "$side/learning/evals/$playbook/checks.sh" "$work" "$dir/reply.md" "$home" >"$dir/checks.txt" 2>&1
  echo $? >"$dir/checks.code"
  # The files the session actually opened, from its transcript rather than
  # from what it says it did.
  find "$home/.keel/claude/projects" -name '*.jsonl' -exec cat {} + 2>/dev/null |
    jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
      | (.input.file_path // .input.path // empty)' 2>/dev/null |
    sed "s|^$work/||" | sort -u >"$dir/opened.txt"
}

# Neutral labels, assigned at random, so neither the order nor the name says
# which side a result came from.
labels=(north south east west amber cedar delta ember fjord grove harbor indigo)
mapfile -t order < <(printf '%s\n' "${labels[@]:0:$((2 * n))}" | shuf)
declare -A SIDE
for ((i = 0; i < n; i++)); do
  SIDE[${order[$i]}]=installed
  SIDE[${order[$((n + i))]}]=variant
done
for label in "${order[@]}"; do
  if [[ "${SIDE[$label]}" == installed ]]; then side="$INSTALLED"; else side="$variant"; fi
  echo "running $label" >&2
  run_one "$side" "$label"
done

# One judge, one pass, one scale, over every result under its label.
{
  echo "Score each result below against the rubric, on one scale from 0 to 10, in a single pass."
  echo "Read the replies, the scripted checks and the files each one opened."
  echo "Reply with only a JSON array: [{\"label\": ..., \"score\": ..., \"notes\": \"one or two sentences\"}]."
  echo
  echo "## Rubric"
  cat "$CASE/rubric.md"
  echo
  echo "## Task"
  cat "$CASE/prompt.md"
  for label in $(printf '%s\n' "${order[@]}" | sort); do
    echo
    echo "## Result $label"
    echo "### Reply"
    cat "$W/$label/reply.md"
    echo "### Scripted checks"
    cat "$W/$label/checks.txt"
    echo "### Files opened"
    cat "$W/$label/opened.txt" 2>/dev/null
    echo "### Diff"
    # New files count: intent-to-add puts them in the diff without staging them.
    (cd "$(cat "$W/$label/work" 2>/dev/null || echo /nonexistent)" 2>/dev/null && git add -A -N && git diff "$(git rev-list --max-parents=0 HEAD)" | head -c 6000)
  done
} >"$W/judge.md"
JH="$W/judge-home"
mkdir -p "$JH"
HOME="$JH" "$INSTALLED/install.sh" >/dev/null
cp "$CREDS" "$JH/.keel/claude/.credentials.json"
scores=$(cd "$W" && HOME="$JH" CLAUDE_CONFIG_DIR="$JH/.keel/claude" "$CLAUDE_BIN" -p "$(cat "$W/judge.md")" --output-format json </dev/null 2>/dev/null |
  jq -r '.result // empty' | sed -n '/^\[/,/^\]/p')
rm -f "$JH/.keel/claude/.credentials.json"

# The result file, in the variant, naming the method and trust content it ran
# against so CI can tell it belongs to this change.
hash=$("$variant/learning/evals/content-hash.sh" "$variant")
slug=$(basename "$variant" | tr -c 'a-z0-9\n' '-')
out="$variant/learning/evals/results/$(date -u +%Y-%m-%d-%H%M%S)-$playbook-$slug.md"
mkdir -p "$(dirname "$out")"
{
  echo "# $playbook: installed keel vs $(basename "$variant")"
  echo
  echo "method-trust: $hash"
  echo "playbook: $playbook"
  echo "runs: $n per side"
  echo "installed: $INSTALLED"
  echo "variant: $variant"
  echo
  echo "| Label | Side | Checks | Score | Notes |"
  echo "|---|---|---|---|---|"
  for label in $(printf '%s\n' "${order[@]}" | sort); do
    s=$(jq -r --arg l "$label" '.[] | select(.label == $l) | "\(.score) | \(.notes)"' <<<"$scores" 2>/dev/null)
    echo "| $label | ${SIDE[$label]} | $(if [[ "$(cat "$W/$label/checks.code" 2>/dev/null)" == 0 ]]; then echo pass; else echo fail; fi) | ${s:-no score | the judge gave none} |"
  done
  for label in $(printf '%s\n' "${order[@]}" | sort); do
    echo
    echo "## $label (${SIDE[$label]})"
    echo
    echo '```'
    cat "$W/$label/checks.txt"
    echo '```'
    echo
    echo "Opened: $(paste -sd' ' "$W/$label/opened.txt" 2>/dev/null)"
  done
} >"$out"
echo "$out"

#!/usr/bin/env bash
# Drives real Claude Code sessions through keel's hooks and router, against the
# same throwaway fixture as tests/run.sh. keel is installed into a throwaway
# HOME, so the sessions run on this checkout's settings, rules, skills and
# method, never on the installed ones. Uses the login of the real keel config
# dir and a few short Haiku calls, so it costs a little and takes a few
# minutes. Run by hand, not in CI.
#
#   tests/sessions.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/keel-sessions.XXXXXX")"
trap 'rm -rf "$T"' EXIT
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

REAL_CONFIG="$HOME/.keel/claude"
CLAUDE_BIN="$(command -v claude)" || {
  echo "tests/sessions.sh needs claude on PATH" >&2
  exit 2
}
[[ -f "$REAL_CONFIG/.credentials.json" ]] || {
  echo "tests/sessions.sh needs keel's login: run \`keel claude\` once and /login there" >&2
  exit 2
}

export HOME="$T/home"
mkdir -p "$HOME"
"$ROOT/install.sh" >/dev/null
CONFIG="$HOME/.keel/claude"
# The login is linked, not copied, so a token the test session refreshes is
# the one the real keel session keeps using.
ln -s "$REAL_CONFIG/.credentials.json" "$CONFIG/.credentials.json"
[[ -f "$REAL_CONFIG/.claude.json" ]] && cp "$REAL_CONFIG/.claude.json" "$CONFIG/.claude.json"
export CLAUDE_CONFIG_DIR="$CONFIG" KEEL_PACKS="$T/packs"
PATH="$HOME/.local/bin:$(dirname "$CLAUDE_BIN"):$PATH"
export PATH

make_fixture
echo 'ACME RULE: the acme word is PELICAN.' >>"$PACK/rules.md"
LOG="$T/hooks.log"
# The installed settings, with each context call logged so the test can see
# which events fired and where.
jq --arg log "$LOG" '.hooks |= with_entries(.value[0].hooks[0].command |= (
    if test(" context$") then "tee -a " + $log + " | " + . else . end))' \
  "$ROOT/rails/settings.json" >"$T/settings.json"
rm "$CONFIG/settings.json"
cp "$T/settings.json" "$CONFIG/settings.json"

ask() { # ask <dir> <prompt> [claude args...] -> the final reply
  local dir="$1" prompt="$2"
  shift 2
  (cd "$dir" && claude -p "$prompt" --model haiku --output-format json "$@" </dev/null 2>/dev/null) |
    jq -r '.result // empty'
}
logged() { # logged <jq filter> -> matching hook log entries, one per line
  jq -c "select($1)" "$LOG" 2>/dev/null
}
keel_leases() { # keel_leases <repo> -> leased trees held by keel
  (cd "$1" && treehouse status --json) |
    jq -r '.[] | select(.status == "leased" and (.lease_holder // "" | startswith("keel:"))) | .path'
}

WORD="What is the acme word given in your context? Reply with only the word, or NONE if there is none."

section "main session"
reply=$(ask "$ACME" "$WORD")
check "a session in an owned repo has the pack's rules" grep -q PELICAN <<<"$reply"
reply=$(ask "$OTHER" "$WORD")
check "a session in an unowned repo has none" test -z "$(grep PELICAN <<<"$reply")"

SID=$(uuidgen)
ask "$ACME" "Reply with OK." --session-id "$SID" >/dev/null
ask "$ACME" "/compact" --resume "$SID" >/dev/null
reply=$(ask "$ACME" "$WORD" --resume "$SID")
check "the rules are there after compaction and resume" grep -q PELICAN <<<"$reply"
check "SessionStart fired on resume" test -n "$(logged ".session_id == \"$SID\" and .source == \"resume\"")"
check "SessionStart fired after compaction" test -n "$(logged ".session_id == \"$SID\" and .source == \"compact\"")"

section "subagent with worktree isolation"
reply=$(ask "$ACME" "Launch exactly one subagent with the Agent tool, using isolation: \"worktree\". Do not tell it any word. Ask it to run pwd, and to report the acme word given in its own context, or NONE. Reply with two lines: its pwd, then its word." \
  --allowedTools "Agent,Bash(pwd)")
check "the subagent ran in a pool tree" grep -q "$T/pools/" <<<"$reply"
check "the subagent had the pack's rules" grep -q PELICAN <<<"$reply"
check "SubagentStart fired in the subagent's tree" test -n "$(logged ".hook_event_name == \"SubagentStart\" and (.cwd | startswith(\"$T/pools/\"))")"
eq "the subagent's empty tree went back to the pool" "" "$(keel_leases "$ACME")"
eq "its agent branch was deleted" "" "$(git -C "$ACME" for-each-ref --format='%(refname)' 'refs/heads/agent-*')"

section "claude --worktree"
reply=$(ask "$ACME" "Run pwd and git rev-parse --abbrev-ref HEAD. Reply with their two outputs, one per line." \
  --worktree feature/from-flag --allowedTools "Bash(pwd),Bash(git rev-parse --abbrev-ref HEAD)")
check "the session ran in a pool tree" grep -q "$T/pools/" <<<"$reply"
check "on the branch it was named for" grep -q "feature/from-flag" <<<"$reply"

section "EnterWorktree"
reply=$(ask "$ACME" "Call the EnterWorktree tool with name feature/from-tool. Then run pwd and git rev-parse --abbrev-ref HEAD, and reply with their two outputs, one per line." \
  --allowedTools "EnterWorktree,Bash(pwd),Bash(git rev-parse --abbrev-ref HEAD)")
check "the session moved into a pool tree" grep -q "$T/pools/" <<<"$reply"
check "on the branch it was named for" grep -q "feature/from-tool" <<<"$reply"

section "routing"
ROUTE="Do not do the task. Reply with only the first line of the todo list you would open for it, and the playbook you matched on the line before it, as 'Playbook: <name>' or 'no playbook fits'."
# route <prompt> -> the reply to a task, asking only for how it was routed
route() { ask "$OTHER" "Task: $1"$'\n\n'"$ROUTE"; }
reply=$(route "write me a haiku about autumn")
check "a task no playbook fits says so" grep -qi "no playbook fits" <<<"$reply"
# One task per playbook, each opening the todo list with that playbook's first
# step, copied word for word as the router says.
for case in \
  "issue|pick up ANB-31" \
  "bug-fix|the acme app crashes with a TypeError when the cart is empty; fix it" \
  "investigation|how does this repository decide which branch a new tree is cut from?" \
  "babysit-pr|get PR #12 green" \
  "pause|pause here: I have to stop for today with the work in this tree half done, and another session will pick it up tomorrow" \
  "pickup|pick up where the last session in this tree stopped"; do
  playbook=${case%%|*}
  reply=$(route "${case#*|}")
  check "a $playbook task matches the $playbook playbook" grep -qi "Playbook: $playbook" <<<"$reply"
  check "and gives the $playbook playbook's first step word for word" grep -qF "$(sed -n 's/^1\. //p' "$ROOT/method/playbooks/$playbook.md")" <<<"$reply"
done

section "runs"
# The prompt never names keel run: the router alone must start the run. A
# routing case above may have recorded one in the same tree; clear it first.
(cd "$OTHER" && keel run stop stopped >/dev/null 2>&1)
ask "$OTHER" "Task: the acme app crashes with a TypeError when the cart is empty; fix it."$'\n\n'"Route it as your rules say, then stop before working on any step." \
  --allowedTools "Bash(keel:*),Bash(printf:*),Bash(cat:*),Write" >/dev/null
runs=$(keel status --json "$OTHER")
eq "a routed session leaves a run keel status shows, in its tree" "$OTHER bug-fix" "$(jq -r '.[] | "\(.tree) \(.playbook)"' <<<"$runs")"
check "with a goal" test -n "$(jq -r '.[0].goal // empty' <<<"$runs")"
eq "and the bug-fix playbook's steps" "$(sed -n 's/^[0-9]\. //p' "$ROOT/method/playbooks/bug-fix.md")" "$(jq -r '.[0].steps[].title' <<<"$runs")"
(cd "$OTHER" && keel run stop stopped >/dev/null 2>&1)

section "contracts"
C1="$T/work/other/contracted"
git clone -q "$T/remotes/other/app" "$C1"
printf 'Make the file.\n' >"$T/c-steps.md"
printf 'goal: proof.txt exists\ndone: test -f proof.txt\nbudget: 15m\ngrants: none\n' >"$T/c-contract.md"
(cd "$C1" && keel run start --playbook autonomous-run --goal "proof.txt exists" --steps "$T/c-steps.md" --contract "$T/c-contract.md" >/dev/null)
# The hook's reason quotes only the check's output, which `test -f` leaves
# empty, so the prompt names the check the session will be held to.
ask "$C1" "This tree's run is done when \`test -f proof.txt\` passes. For now, reply with only the word READY and do not run any tool. If you are held, create the file with \`touch proof.txt\`." \
  --allowedTools "Bash(touch proof.txt),Write" >/dev/null
# The session may end the run itself once the check passes, as the router
# says, which archives it; the trail is then the newest archived folder.
c1_run=$(cd "$C1" && keel run dir 2>/dev/null) ||
  c1_run=$(find "$HOME/.local/state/keel/runs/archive/${C1//[\/.]/-}" -mindepth 1 -maxdepth 1 2>/dev/null | sort | tail -1)
eq "a session under a contract is held while its done check fails, then ends its turn once it passes" "fail pass" \
  "$(cut -f6 "$c1_run/decisions.tsv" | sed 's/,.*//' | uniq | paste -sd' ')"
eq "with the pass recorded at its HEAD" "true $(git -C "$C1" rev-parse HEAD)" \
  "$(jq -r '.done_check | "\(.passed) \(.head)"' "$c1_run/status.json")"
(cd "$C1" && keel run stop "done" >/dev/null 2>&1)

section "grants"
C2="$T/work/other/granted"
git clone -q "$T/remotes/other/app" "$C2"
git -C "$C2" switch -q -c feature/granted
printf 'goal: g\ndone: test -f never\nbudget: 15m\ngrants: commit\n' >"$T/g-contract.md"
(cd "$C2" && keel run start --playbook autonomous-run --goal g --steps "$T/c-steps.md" --contract "$T/g-contract.md" >/dev/null)
echo x >"$C2/x" && git -C "$C2" add x
touch "$C2/never"
# Two Bash calls, not one chained command: git-guard denies a whole command when
# any part of it is refused, so a chained push would take the commit down too.
ask "$C2" "Make two separate Bash tool calls, one command each. First run exactly: git commit -m 'add x'. Then run exactly: git push -u origin HEAD:feature/granted. Then reply with what happened to each." \
  --allowedTools "Bash(git commit:*),Bash(git push:*)" >/dev/null
check "a run granted commit only gets its commit through" test "$(git -C "$C2" log -1 --format=%s)" == "add x"
check "and has its push refused" test -z "$(git -C "$T/remotes/other/app" branch --list feature/granted)"
check "with the missing grant flagged for attention" grep -q "refused .git push" "$(cd "$C2" && keel run dir)/decisions.tsv"
(cd "$C2" && keel run stop stopped >/dev/null)

echo
echo "keel-held trees left leased:"
keel_leases "$ACME" | sed 's/^/  /'
summary

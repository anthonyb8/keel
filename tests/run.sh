#!/usr/bin/env bash
# Exercises keel end to end against throwaway repositories, a throwaway
# treehouse pool and a throwaway pack, under a temporary HOME seeded with a
# fake harness install, so nothing on the machine is touched. Needs bash, git,
# jq, curl, python3 and treehouse; no Claude calls: a stub stands in for claude.
#
#   tests/run.sh
# shellcheck disable=SC2016,SC2088 # expected text holds a literal $, ~ and backticks
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/keel-test.XXXXXX")"
export T
trap 'rm -rf "$T"' EXIT

# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

export HOME="$T/home"
# A run from inside a keel session must not inherit its config dir.
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME" "$T/stubs"
export PATH="$T/stubs:$HOME/.local/bin:$PATH"
K="$HOME/.local/bin/keel"

# claude, replaced by a stub that reports what it was started with.
cat >"$T/stubs/claude" <<'STUB'
#!/usr/bin/env bash
echo "config=${CLAUDE_CONFIG_DIR:-}"
printf 'arg=%s\n' "$@"
STUB
chmod +x "$T/stubs/claude"

section "install"
seed_harness
before=$(snapshot_harness)
out=$("$ROOT/install.sh")
eq "install writes only under ~/.keel/claude and ~/.local/bin/keel" "" \
  "$(grep -v -e "^linked   $HOME/.keel/claude/" -e "^linked   $HOME/.local/bin/keel\$" <<<"$out")"
eq "running install again changes nothing" "" "$("$ROOT/install.sh")"
check "--check is clean after install" "$ROOT/install.sh" --check
check "settings.json is valid JSON, or Claude Code would drop every permission" jq empty "$HOME/.keel/claude/settings.json"
# A hook left out never fires, and one that runs harness acts on harness's
# trees: each event must reach the keel hook that handles it, and only that.
eq "settings wire each hook event to keel's hook for it, never harness's" \
  "$(printf '%s\n' 'PreToolUse git-guard' 'SessionStart context' 'SubagentStart context' 'SubagentStop subagent-stop' 'WorktreeCreate worktree-create' 'WorktreeRemove worktree-remove')" \
  "$(jq -r '.hooks | to_entries[] | .key + " " + (.value[].hooks[].command | ltrimstr("\"$HOME/.local/bin/keel\" hook "))' "$HOME/.keel/claude/settings.json" | sort)"
eq "git-guard guards Bash and blocks the command when it cannot run" "Bash block" \
  "$(jq -r '.hooks.PreToolUse[0] | "\(.matcher) \(.hooks[0].onFailure)"' "$HOME/.keel/claude/settings.json")"
rm "$HOME/.keel/claude/CLAUDE.md"
out=$("$ROOT/install.sh" --check)
refute "--check fails on a removed link" "$ROOT/install.sh" --check
check "and names it MISSING" grep -qx "MISSING: $HOME/.keel/claude/CLAUDE.md" <<<"$out"
"$ROOT/install.sh" >/dev/null
eq "install puts it back" "$ROOT/rules/CLAUDE.md" "$(readlink "$HOME/.keel/claude/CLAUDE.md")"
echo stale >"$HOME/.keel/claude/VOICE.md.tmp" && mv "$HOME/.keel/claude/VOICE.md.tmp" "$HOME/.keel/claude/VOICE.md"
"$ROOT/install.sh" >/dev/null
eq "a link replaced with a file is relinked" "$ROOT/rules/VOICE.md" "$(readlink "$HOME/.keel/claude/VOICE.md")"
eq "and the file is kept as .bak" "stale" "$(cat "$HOME/.keel/claude/VOICE.md.bak")"

section "keel claude"
out=$("$K" claude --resume "two words")
eq "keel claude runs claude on keel's config dir" "config=$HOME/.keel/claude" "$(head -1 <<<"$out")"
eq "and passes its arguments through untouched" "$(printf 'arg=--resume\narg=two words')" "$(tail -n +2 <<<"$out")"
check "keel help succeeds" "$K" help
check "and documents keel claude" grep -q "keel claude \[args\]" <<<"$("$K" help)"
refute "an unknown verb fails" "$K" nope

section "pack and base"
make_fixture
eq "a repo a pack in harness's packs dir matches resolves to it" "$PACK" "$(readlink -f "$($K pack "$ACME")")"
eq "a repo no pack matches resolves to nothing" "" "$($K pack "$OTHER")"
eq "a directory outside git resolves to nothing" "" "$($K pack "$T")"
eq "KEEL_PACKS points keel at another packs dir" "" "$(KEEL_PACKS="$T/nopacks" $K pack "$ACME")"
eq "base comes from the pack" "develop" "$($K base "$ACME")"
eq "no pack, no base" "" "$($K base "$OTHER")"
eq "a pack repo without the pack's base falls back to its default" "" "$($K base "$SITE")"
echo release >"$PACK/protected"
eq "the base, the default branch and the pack's list are protected" "$(printf 'develop\nmain\nrelease')" "$($K protected "$ACME")"
eq "a repo without the pack's list protects its default" "main" "$($K protected "$OTHER")"
rm "$PACK/protected"

section "context hook"
out=$(jq -n --arg c "$ACME" '{hook_event_name:"SessionStart",source:"startup",cwd:$c}' | $K hook context)
ctx=$(jq -r .hookSpecificOutput.additionalContext <<<"$out")
check "SessionStart in an owned repo injects the rules" grep -q "ACME RULE" <<<"$ctx"
check "and tells the session to run keel where the rules name harness" grep -qF 'where these rules name `harness <verb>`, run `keel <verb>`' <<<"$ctx"
check "and points at keel's CLAUDE.md, not harness's" grep -qF "~/.keel/claude/CLAUDE.md" <<<"$ctx"
eq "SessionStart output names its event" "SessionStart" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")"
out=$(jq -n --arg c "$ACME" '{hook_event_name:"SubagentStart",cwd:$c}' | $K hook context)
eq "SubagentStart output names its event" "SubagentStart" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")"
out=$(jq -n --arg c "$OTHER" '{hook_event_name:"SessionStart",source:"startup",cwd:$c}' | $K hook context)
eq "an unowned repo gets no output" "" "$out"

create() { # create <repo> <name>
  jq -n --arg c "$1" --arg n "$2" '{hook_event_name:"WorktreeCreate",cwd:$c,name:$n}' | $K hook worktree-create 2>/dev/null
}
stop() { # stop <tree> <agent id>
  jq -n --arg c "$1" --arg a "$2" '{hook_event_name:"SubagentStop",cwd:$c,agent_id:$a}' | $K hook subagent-stop 2>/dev/null
}
holder() { # holder <repo> <path>
  (cd "$1" && treehouse status --json) | jq -r --arg p "$2" '.[] | select(.path == $p) | .lease_holder'
}
# A tree leased the way a harness session leases one.
harness_lease() { # harness_lease <repo> <name>
  (cd "$1" && treehouse get --lease --lease-holder "claude:$2" --branch "$2" 2>/dev/null)
}

section "worktree create"
P=$(create "$ACME" feature/acme-1-thing)
check "a new name leases a pool tree" test -d "$P"
eq "the tree is on a branch of that name" "feature/acme-1-thing" "$(git -C "$P" rev-parse --abbrev-ref HEAD)"
eq "the tree is cut from the pack's base" "$DEVELOP" "$(git -C "$P" rev-parse HEAD)"
eq "the lease is held by keel, not claude" "keel:feature/acme-1-thing" "$(holder "$ACME" "$P")"
P2=$(create "$ACME" feature/acme-1-thing)
eq "the same name again resumes the same tree" "$P" "$P2"
eq "resuming leases nothing new" "1" "$( (cd "$ACME" && treehouse status --json) | jq '[.[] | select(.status == "leased")] | length')"

Q=$(create "$OTHER" feature/plain)
eq "with no pack the tree is cut from the default branch" "$MAIN" "$(git -C "$Q" rev-parse HEAD)"
S=$(create "$SITE" feature/site-1)
eq "a pack repo without the pack's base leases off its default" "$(git -C "$SITE" rev-parse origin/main)" "$(git -C "$S" rev-parse HEAD)"

refute "a directory outside git is refused" create "$T" anything
eq "a refused create prints no path" "" "$(create "$T" anything)"

section "default provision"
# Stand-ins for npm, which counts its installs, and node, whose version the
# stamp records.
mkdir -p "$T/npm-tree"
printf '#!/bin/sh\nmkdir -p node_modules && echo ci >>"%s/npm-calls"\n' "$T" >"$T/stubs/npm"
printf '#!/bin/sh\necho "${NODE_VERSION:-v1}"\n' >"$T/stubs/node"
chmod +x "$T/stubs/npm" "$T/stubs/node"
echo '{"v":1}' >"$T/npm-tree/package-lock.json"
installs() { $K provision "$T/npm-tree" && wc -l <"$T/npm-calls" | tr -d ' '; }
eq "a tree without node_modules gets npm ci" "1" "$(installs)"
eq "a tree already installed from the same lockfile skips it" "1" "$(installs)"
check "under harness's stamp, so neither system reinstalls the other's tree" test -f "$T/npm-tree/node_modules/.harness-provisioned"
echo '{"v":2}' >"$T/npm-tree/package-lock.json"
eq "a changed lockfile installs again" "2" "$(installs)"
eq "a changed Node installs again" "3" "$(NODE_VERSION=v2 installs)"
printf '#!/bin/sh\necho pack >.provisioned\n' >"$PACK/provision"
chmod +x "$PACK/provision"
$K provision "$ACME"
eq "a pack's provision script runs in the tree" "pack" "$(cat "$ACME/.provisioned" 2>/dev/null)"
rm "$PACK/provision" "$ACME/.provisioned"
rm "$T/stubs/npm" "$T/stubs/node"

section "worktree remove and re-create"
jq -n --arg p "$P" '{hook_event_name:"WorktreeRemove",worktree_path:$p}' | $K hook worktree-remove >/dev/null 2>&1
eq "remove returns the tree to the pool" "available" "$(lease_status "$ACME" "$P")"
check "and releases its stack" grep -qxF "$P" "$T/released"
check "the branch survives the return" git -C "$ACME" rev-parse --verify --quiet refs/heads/feature/acme-1-thing
P3=$(create "$ACME" feature/acme-1-thing)
eq "an existing branch with no tree gets a tree on that branch" "feature/acme-1-thing" "$(git -C "$P3" rev-parse --abbrev-ref HEAD)"
eq "and that lease is held" "leased" "$(lease_status "$ACME" "$P3")"

section "subagent stop"
A=$(create "$ACME" agent-aaa111)
eq "a subagent's tree is held as keel:agent-<id>" "keel:agent-aaa111" "$(holder "$ACME" "$A")"
stop "$A" bbb222
eq "a stop from another agent leaves the tree alone" "leased" "$(lease_status "$ACME" "$A")"
echo wip >"$A/wip.txt"
: >"$T/released"
stop "$A" aaa111
eq "a tree with uncommitted work is kept" "leased" "$(lease_status "$ACME" "$A")"
# treehouse itself refuses to return a dirty tree, so the lease alone cannot
# show keel's own check ran: a released stack would mean keel tore it down.
check "and its stack is left running" test ! -s "$T/released"
git -C "$A" add wip.txt && git -C "$A" commit -q -m wip
stop "$A" aaa111
eq "a tree with a commit missing from the remote is kept" "leased" "$(lease_status "$ACME" "$A")"
B=$(create "$ACME" agent-ccc333)
stop "$B" ccc333
eq "an empty tree is returned" "available" "$(lease_status "$ACME" "$B")"
check "and its stack released" grep -qxF "$B" "$T/released"
check "and its agent branch is deleted" test -z "$(git -C "$ACME" for-each-ref refs/heads/agent-ccc333)"
HA=$(harness_lease "$ACME" agent-eee555)
stop "$HA" eee555
eq "a stop never returns a tree a harness subagent holds" "leased" "$(lease_status "$ACME" "$HA")"
: >"$T/released"
stop "$ACME" aaa111
check "a stop in the main checkout is a no-op" test ! -s "$T/released"

section "sweep"
C=$(create "$ACME" agent-ddd444)
HS=$(harness_lease "$ACME" feature/harness-idle)
before_pool=$( (cd "$ACME" && treehouse status --json) | jq -c '[.[] | {path, status}]')
listed=$(cd "$ACME" && $K sweep)
check "a dry run lists the idle keel trees" grep -q "$C" <<<"$listed"
refute "a dry run never lists a tree harness holds" grep -q "$HS" <<<"$listed"
eq "a dry run changes nothing" "$before_pool" "$( (cd "$ACME" && treehouse status --json) | jq -c '[.[] | {path, status}]')"
swept=$(cd "$ACME" && $K sweep --apply 2>&1 >/dev/null)
eq "apply returns the empty tree" "available" "$(lease_status "$ACME" "$C")"
eq "apply keeps the tree with work" "leased" "$(lease_status "$ACME" "$A")"
check "and says why it kept it" grep -qxF "kept $A: commits not on any remote" <<<"$swept"
eq "apply never returns an empty tree harness holds" "leased" "$(lease_status "$ACME" "$HS")"
check "a dry run names the returned trees whose stacks it would release" grep -q "would release the stack of $C" <<<"$(cd "$ACME" && $K sweep)"
: >"$T/released"
(cd "$ACME" && $K sweep --apply >/dev/null 2>&1)
check "apply releases the stacks of returned trees" grep -qxF "$C" "$T/released"
check "apply never releases the stack of a leased tree" test -z "$(grep -xF "$A" "$T/released")"
mkdir -p "$HOME/.config/keel"
echo "$C" >"$HOME/.config/keel/keep"
: >"$T/released"
(cd "$ACME" && $K sweep --apply >/dev/null 2>&1)
check "apply never releases the stack of a tree on keel's keep list" test -z "$(grep -xF "$C" "$T/released")"
rm "$HOME/.config/keel/keep"

section "stack"
export STACK_PORT
STACK_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
KT=$(create "$ACME" feature/acme-2-stack)
out=$(cd "$KT" && $K stack up 2>/dev/null)
eq "up prints the URL once it serves" "http://127.0.0.1:$STACK_PORT/" "$out"
check "the stack answers after up returns" curl -s -o /dev/null "$out"
check "status reports it running" bash -c "cd '$KT' && $K stack status"
eq "a running stack leaves the tree clean" "" "$(git -C "$KT" status --porcelain)"
eq "up again reuses the running stack" "$out" "$(cd "$KT" && $K stack up 2>/dev/null)"
(cd "$KT" && $K stack down >/dev/null)
refute "down stops the server" curl -s -o /dev/null "$out"
refute "status fails once stopped" bash -c "cd '$KT' && $K stack status"
if err=$(cd "$KT" && STACK_FAIL=1 KEEL_STACK_TIMEOUT=20 $K stack up 2>&1); then fail "a stack that dies makes up fail"; else pass "a stack that dies makes up fail"; fi
check "and says it exited rather than waiting out the timeout" grep -q "exited before it served" <<<"$err"
check "and up shows its log" grep -q "stack broke" <<<"$err"
(cd "$KT" && $K stack up >/dev/null 2>&1)
jq -n --arg p "$KT" '{hook_event_name:"WorktreeRemove",worktree_path:$p}' | $K hook worktree-remove >/dev/null 2>&1
refute "removing the tree stops its stack" curl -s -o /dev/null "$out"
refute "up refuses a repo with no stack script" bash -c "cd '$OTHER' && $K stack up"

section "stack release"
: >"$T/released"
(cd "$KT" && $K stack release >/dev/null 2>&1)
check "release runs the pack's release in the tree" grep -qxF "$KT" "$T/released"
eq "a stack with no release succeeds and says nothing" "exit 0" "$(cd "$KT" && STACK_NO_RELEASE=1 $K stack release 2>&1; echo "exit $?")"
check "a repo no pack owns has nothing to release" bash -c "cd '$OTHER' && $K stack release"

section "e2e"
if err=$(cd "$ACME" && STACK_NO_PORTS=1 $K e2e true 2>&1); then fail "e2e refuses a stack that names no ports"; else pass "e2e refuses a stack that names no ports"; fi
check "and says why" grep -q "named no ports" <<<"$err"
if err=$(cd "$ACME" && $K e2e true 2>&1); then fail "e2e refuses a tree without Playwright"; else pass "e2e refuses a tree without Playwright"; fi
check "and says why" grep -q "no @playwright/test" <<<"$err"
if err=$(cd "$ACME" && $K e2e -e NOEQUALS true 2>&1); then fail "e2e refuses an -e without a value"; else pass "e2e refuses an -e without a value"; fi
check "and says how to use it" grep -q "usage: keel e2e" <<<"$err"

section "gate"
out=$(cd "$ACME" && $K gate "Fix the parser" --dry-run)
check "the gate initialises a repo that has no gate" grep -q "^no-mistakes init$" <<<"$out"
check "the gate targets the pack's base" grep -q -- "--base-branch develop" <<<"$out"
check "the gate skips rebase, push, pr and ci by default" grep -q -- "--skip rebase\\\\,push\\\\,pr\\\\,ci" <<<"$out"
out=$(cd "$ACME" && KEEL_GATE_SKIP=ci HARNESS_GATE_SKIP=push $K gate "Fix the parser" --dry-run)
check "KEEL_GATE_SKIP sets what the gate skips, and HARNESS_GATE_SKIP does not" grep -q -- "--skip ci " <<<"$out"
out=$(cd "$OTHER" && $K gate "Fix it" --dry-run)
check "with no pack the gate leaves the base to no-mistakes" test -z "$(grep -- --base-branch <<<"$out")"
# Without its own check the gate would still fail here, for want of a real
# no-mistakes, so the usage line is what shows the intent was asked for.
if err=$(cd "$ACME" && $K gate 2>&1); then fail "the gate refuses to run without an intent"; else pass "the gate refuses to run without an intent"; fi
check "and says how to use it" grep -q "usage: keel gate" <<<"$err"

section "gate after a fold"
# A stub no-mistakes reports the run and sync state it is given, and on a run
# records whether the gate's copy was there, then pushes the head the way a
# started run does unless NM_RUN_CODE makes it fail first.
mkdir -p "$T/stub"
cat >"$T/stub/no-mistakes" <<'SH'
#!/bin/sh
gate=$(git remote get-url no-mistakes)
branch=$(git symbolic-ref --short HEAD)
case "$1 $2" in
"axi status") printf 'run:\n  id: "r1"\n  status: %s\nbranch_sync:\n  state: %s\n' "${NM_RUN:-completed}" "${NM_SYNC:-custody_returned}" ;;
"axi run")
  git --git-dir="$gate" rev-parse -q --verify "refs/heads/$branch" >"$T_LOG" || echo absent >"$T_LOG"
  [ "${NM_RUN_CODE:-0}" = 0 ] || exit "$NM_RUN_CODE"
  git push -q "$gate" "HEAD:refs/heads/$branch"
  ;;
esac
SH
chmod +x "$T/stub/no-mistakes"
export T_LOG="$T/nm.log"
git init -q --bare "$T/gate.git"
G="$T/work/acme/folded"
git clone -q "$T/remotes/acme/app" "$G"
git -C "$G" remote add no-mistakes "$T/gate.git"
git -C "$G" switch -q -c feature/x origin/develop
echo a >"$G/a" && git -C "$G" add a && git -C "$G" commit -qm "feature"
echo fix >>"$G/a" && git -C "$G" commit -qam "no-mistakes(review): fix"
OLD=$(git -C "$G" rev-parse HEAD)
git -C "$G" push -q no-mistakes HEAD:refs/heads/feature/x
git -C "$G" reset -q --soft origin/develop && git -C "$G" commit -qm "feature, folded"
gate_in() { (cd "$G" && PATH="$T/stub:$PATH" "$@"); }
copy() { git --git-dir="$T/gate.git" rev-parse -q --verify "refs/heads/feature/x" || echo absent; }

out=$(gate_in "$K" gate "Fold" --dry-run)
check "a dry run names the folded-away copy it would clear" grep -q "^clear the gate's copy of feature/x at $OLD$" <<<"$out"
eq "and a dry run leaves it" "$OLD" "$(copy)"
out=$(NM_RUN=running gate_in "$K" gate "Fold" --dry-run)
check "a run in flight keeps the copy" test -z "$(grep "^clear" <<<"$out")"
out=$(NM_SYNC=pipeline_owned gate_in "$K" gate "Fold" --dry-run)
check "gate fixes not yet brought back keep the copy" test -z "$(grep "^clear" <<<"$out")"

if NM_RUN_CODE=3 gate_in "$K" gate "Fold" >/dev/null 2>&1; then fail "a run that fails to start fails the gate"; else pass "a run that fails to start fails the gate"; fi
eq "and puts the copy back" "$OLD" "$(copy)"
gate_in "$K" gate "Fold" >/dev/null 2>&1
eq "the run starts with the copy cleared" "absent" "$(cat "$T_LOG")"
eq "the gate then holds the folded head" "$(git -C "$G" rev-parse HEAD)" "$(copy)"
eq "the folded-away copy is archived where no-mistakes archives one" "$OLD" \
  "$(git --git-dir="$T/gate.git" rev-parse "refs/tags/no-mistakes-abandoned/feature/x/$OLD")"

echo b >"$G/b" && git -C "$G" add b && git -C "$G" commit -qm "more"
out=$(gate_in "$K" gate "More" --dry-run)
check "a branch that only moved ahead keeps the copy" test -z "$(grep "^clear" <<<"$out")"
git -C "$G" switch -q -c elsewhere origin/develop
echo c >"$G/c" && git -C "$G" add c && git -C "$G" commit -qm "elsewhere"
git -C "$G" push -q no-mistakes HEAD:refs/heads/feature/y
git -C "$G" switch -q -c feature/y origin/develop && git -C "$G" branch -q -D elsewhere
echo d >"$G/d" && git -C "$G" add d && git -C "$G" commit -qm "y"
out=$(gate_in "$K" gate "Y" --dry-run)
check "a copy this branch never held is left for no-mistakes" test -z "$(grep "^clear" <<<"$out")"

section "fold"
F="$T/work/fold"
git init -q --bare "$T/fold-origin.git"
git clone -q "$T/fold-origin.git" "$F" 2>/dev/null
echo base >"$F/base" && git -C "$F" add base && git -C "$F" commit -qm "base"
git -C "$F" push -q origin HEAD:refs/heads/main
git -C "$F" switch -q -c feature/f
echo a >"$F/a" && git -C "$F" add a && git -C "$F" commit -qm "END-1: a"
echo b >"$F/b" && git -C "$F" add b && git -C "$F" commit -qm "END-2: b"
echo a2 >>"$F/a" && git -C "$F" commit -qam "no-mistakes(review): fix a"
echo b2 >>"$F/b" && git -C "$F" commit -qam "no-mistakes(document): fix b"
TREE=$(git -C "$F" rev-parse "HEAD^{tree}")
# The gate has seen the branch: its remote holds a copy, which does not count.
git init -q --bare "$T/fold-gate.git"
git -C "$F" remote add no-mistakes "$T/fold-gate.git"
git -C "$F" push -q no-mistakes HEAD:refs/heads/feature/f
git -C "$F" fetch -q no-mistakes
fold_in() { (cd "$F" && $K fold "$@"); }
subjects() { git -C "$F" log --format=%s origin/main..HEAD | tr '\n' '|'; }

check "fold moves a fix into an earlier commit" fold_in ":/fix a" ":/END-1"
eq "the fix is gone into its target" "no-mistakes(document): fix b|END-2: b|END-1: a|" "$(subjects)"
eq "the final tree is unchanged" "$TREE" "$(git -C "$F" rev-parse "HEAD^{tree}")"
eq "the target now holds the fix" "$(printf 'a\na2')" "$(git -C "$F" show "$(git -C "$F" rev-parse ":/END-1"):a")"
check "fold folds into the commit just before" fold_in ":/fix b" ":/END-2"
eq "leaving one commit per issue" "END-2: b|END-1: a|" "$(subjects)"

echo c >"$F/c" && git -C "$F" add c && git -C "$F" commit -qm "no-mistakes(review): c"
if fold_in ":/END-2" ":/no-mistakes" >/dev/null 2>&1; then fail "fold refuses a target after the fix"; else pass "fold refuses a target after the fix"; fi
echo dirty >>"$F/a"
# git rebase refuses a dirty tree too, unless rebase.autoStash is set, so the
# reason is what shows that fold's own check ran.
if err=$(fold_in ":/no-mistakes" ":/END-1" 2>&1); then fail "fold refuses a dirty tree"; else pass "fold refuses a dirty tree"; fi
check "and says why" grep -q "the tree has uncommitted changes" <<<"$err"
git -C "$F" checkout -q -- a
git -C "$F" push -q origin HEAD:refs/heads/feature/f
HEAD_BEFORE=$(git -C "$F" rev-parse HEAD)
if fold_in ":/no-mistakes" ":/END-1" >/dev/null 2>&1; then fail "fold refuses pushed history"; else pass "fold refuses pushed history"; fi
eq "and leaves the branch where it was" "$HEAD_BEFORE" "$(git -C "$F" rev-parse HEAD)"

section "git guard"
# A clone of its own, so moving HEAD between branches leaves ACME alone.
G="$T/work/acme/guard"
git clone -q "$T/remotes/acme/app" "$G"
git -C "$G" branch -q feature/g
echo release >"$PACK/protected"
guard() { # guard <cwd> <command> -> deny, or nothing when the hook lets it through
  jq -n --arg c "$2" --arg d "$1" '{tool_input: {command: $c}, cwd: $d}' |
    $K hook git-guard | jq -r '.hookSpecificOutput.permissionDecision // empty'
}
on() { git -C "$G" symbolic-ref HEAD "refs/heads/$1"; }

on main
eq "merge into the default branch is refused" "deny" "$(guard "$G" "git merge feature/g")"
eq "a commit message naming merge is not a merge" "" "$(guard "$G" 'git commit -m "$(printf "merge it")"')"
eq "nor is merge-base" "" "$(guard "$G" "git merge-base main feature/g")"
eq "aborting is allowed anywhere" "" "$(guard "$G" "git merge --abort")"
eq "rebasing a named feature branch from the base is allowed" "" "$(guard "$G" "git rebase main feature/g")"
on develop
eq "cherry-pick onto the base is refused" "deny" "$(guard "$G" "git cherry-pick HEAD")"
eq "through a cd" "deny" "$(guard "$T" "cd $G && git revert HEAD")"
eq "through git -C" "deny" "$(guard "$T" "git -C $G merge feature/g")"
eq "a subshell's cd ends with it" "" "$(guard "$T" "(cd $G && git status); git merge feature/g")"
on release
eq "rebase on a listed release branch is refused" "deny" "$(guard "$G" "git status && git rebase main")"
on feature/g
eq "merge into a feature branch is allowed" "" "$(guard "$G" "git merge develop")"
eq "rebase of a feature branch is allowed" "" "$(guard "$G" "git rebase -x 'make test' develop")"
eq "rebase naming a protected branch is refused" "deny" "$(guard "$G" "git rebase --onto main feature/g develop")"
eq "--update-refs is refused" "deny" "$(guard "$G" "git rebase --update-refs develop")"
eq "a cd it cannot follow is refused" "deny" "$(guard "$G" 'cd $SOMEWHERE && git merge x')"
eq "a wrapper is refused" "deny" "$(guard "$G" "bash -c 'git merge develop'")"
eq "an alias set on the command line is refused" "deny" "$(guard "$G" "git -c alias.m=merge m develop")"
eq "an unparseable command that merges is refused" "deny" "$(guard "$G" "$(printf "cat <<EOF\ndon't\nEOF\ngit merge develop")")"
eq "a command naming none of the verbs is let through" "" "$(guard "$G" "ls")"
# keel's packs dir protects feature/g and harness's does not, so only a guard
# that asks keel refuses this merge; ~/.local/bin/harness is on PATH here.
mkdir -p "$T/keelpacks/acme"
cp "$PACK/match" "$T/keelpacks/acme/match"
echo feature/g >"$T/keelpacks/acme/protected"
eq "git-guard asks keel, not harness, for the protected list" "deny" "$(KEEL_PACKS="$T/keelpacks" guard "$G" "git merge develop")"
rm "$PACK/protected"

section "linear"
# A stub Linear on a local port, which logs each request body and answers only
# the stub key. ACME's pack names its team; OTHER gets team and key from the map.
STUB_KEY="lin_api_STUBKEYa1b2c3d4e5f6"
python3 -I "$ROOT/tests/linear-stub.py" "$T/linear.port" "$T/linear.log" "$STUB_KEY" &
LINEAR_STUB=$!
trap 'kill "$LINEAR_STUB" 2>/dev/null; rm -rf "$T"' EXIT
for _ in {1..50}; do [[ -s "$T/linear.port" ]] && break; sleep 0.1; done
KEEL_LINEAR_URL="http://127.0.0.1:$(cat "$T/linear.port")/graphql"
export KEEL_LINEAR_URL
echo ANB >"$PACK/linear"
mkdir -p "$HOME/.config/keel"
printf '# origin glob, team, key env\n*/remotes/acme/app ACME LINEAR_KEY_ACME\n*/remotes/other/* OTH LINEAR_KEY_OTHER\n' >"$HOME/.config/keel/linear"
export LINEAR_KEY_ACME="$STUB_KEY" LINEAR_KEY_OTHER="$STUB_KEY"
OUT="$T/linear-out" # every keel linear output and error, searched for the key at the end
# curl, wrapped to log its arguments, so the key can be shown never to reach a
# command line.
cat >"$T/stubs/curl" <<SH
#!/bin/sh
printf '%s\n' "\$*" >>"$T/curl-args"
exec $(command -v curl) "\$@"
SH
chmod +x "$T/stubs/curl"
lin() { # lin <dir> <args...> -> stdout; stdout and stderr are also kept in $OUT
  local dir="$1" out err code=0
  shift
  out=$(cd "$dir" && $K linear "$@" 2>"$T/linear-err") || code=$?
  err=$(cat "$T/linear-err")
  printf '%s\n%s\n' "$out" "$err" >>"$OUT"
  echo "$out"
  [[ -z "$err" ]] || echo "$err" >&2
  return "$code"
}
last() { tail -1 "$T/linear.log"; } # the last request body the stub saw
sent() { grep -c "${1:-.}" "$T/linear.log"; } # sent [pattern] -> how many requests the stub saw
printf 'A body with "quotes", `ticks` and $dollars.\n\nSecond paragraph.\n' >"$T/body.md"

eq "a pack's linear file names the team for its repositories" "ANB" "$(lin "$ACME" team)"
eq "the map names it for a repository no pack owns" "OTH" "$(lin "$OTHER" team)"
err=$(lin "$SITE" team 2>&1 >/dev/null)
refute "a repository the map does not cover fails" lin "$SITE" team
check "and says to add a line to ~/.config/keel/linear" grep -qF "add a line to ~/.config/keel/linear" <<<"$err"
err=$(LINEAR_KEY_ACME="" lin "$ACME" get ANB-31 2>&1 >/dev/null)
check "an unset key fails naming the variable" grep -qx "keel: LINEAR_KEY_ACME is not set" <<<"$err"
err=$(LINEAR_KEY_ACME="lin_api_WRONG" lin "$ACME" get ANB-31 2>&1 >/dev/null)
check "a key Linear refuses fails with Linear's reason" grep -q "Authentication required" <<<"$err"
check "and never prints the key it sent" test -z "$(grep -F lin_api_WRONG <<<"$err")"

out=$(lin "$ACME" get ANB-31)
eq "get prints the issue as JSON" "keel ANB-32" "$(jq -r '"\(.project.name) \(.relations.nodes[0].relatedIssue.identifier)"' <<<"$out")"
eq "get asks for the issue by its ID" "ANB-31" "$(last | jq -r .variables.id)"
check "with its relations and comments" grep -q "inverseRelations.*comments" <<<"$(last | jq -r .query | tr -d '\n')"
refute "get on an issue Linear cannot find fails" lin "$ACME" get ANB-404
eq "search lists matching open issues" "ANB-31" "$(lin "$ACME" search keel skeleton | cut -f1)"
eq "in the repository's team, by the whole text" "ANB|keel skeleton" "$(last | jq -r '"\(.variables.team)|\(.variables.text)"')"

out=$(lin "$ACME" create --title "A title" --body "$T/body.md" --project keel --blocked-by ANB-31 --blocked-by ANB-32)
eq "create prints the ID, URL, team and workspace" "ANB-99 https://linear.test/ANB-99 (team ANB, workspace Stub Org)" "$out"
create_req=$(grep issueCreate "$T/linear.log" | tail -1)
eq "create files in the repository's team" "team-ANB" "$(jq -r .variables.teamId <<<"$create_req")"
eq "under the named project" "project-keel" "$(jq -r .variables.projectId <<<"$create_req")"
check "with the body file sent byte for byte" cmp -s "$T/body.md" <(jq -j .variables.description <<<"$create_req")
eq "and relates each --blocked-by as blocking it" "$(printf 'uuid-ANB-31 uuid-ANB-99 blocks\nuuid-ANB-32 uuid-ANB-99 blocks')" \
  "$(grep issueRelationCreate "$T/linear.log" | tail -2 | jq -r '"\(.variables.a) \(.variables.b) \(.query | capture("type: (?<t>[a-z]+)").t)"')"
creates=$(sent issueCreate)
refute "create refuses a missing body file" lin "$ACME" create --title t --body "$T/nope.md"
refute "create refuses a project Linear does not have" lin "$ACME" create --title t --body "$T/body.md" --project nope
eq "and files no issue for either" "$creates" "$(sent issueCreate)"

eq "update sets a state by its name" "ANB-99 Canceled" "$(lin "$ACME" update ANB-99 --state Canceled)"
eq "sending the state's ID" "state-canceled" "$(last | jq -r .variables.stateId)"
check "and leaves the description alone" test "$(last | jq -r '.variables | has("description")')" == false
lin "$ACME" update ANB-99 --body "$T/body.md" >/dev/null
eq "update --body replaces the description" "$(cat "$T/body.md")" "$(last | jq -r .variables.description)"
check "and leaves the state alone" test "$(last | jq -r '.variables | has("stateId")')" == false
updates=$(sent issueUpdate)
refute "update refuses a state the team does not have" lin "$ACME" update ANB-99 --state Nope
eq "and sends no update" "$updates" "$(sent issueUpdate)"

eq "comment prints the comment's URL" "https://linear.test/comment/1" "$(lin "$ACME" comment ANB-31 --body "$T/body.md")"
eq "and posts the body file on the issue" "uuid-ANB-31|$(cat "$T/body.md")" "$(last | jq -r '"\(.variables.issueId)|\(.variables.body)"')"
eq "relate links A as blocking B" "uuid-ANB-31 uuid-ANB-32" "$(lin "$ACME" relate ANB-31 blocks ANB-32 >/dev/null && last | jq -r '"\(.variables.a) \(.variables.b)"')"

lin "$ACME" project create keel --summary "Short." --body "$T/body.md" >/dev/null
eq "project create puts the summary in description" "Short. team-ANB" "$(last | jq -r '"\(.variables.description) \(.variables.teamId)"')"
eq "and the body file in content" "$(cat "$T/body.md")" "$(last | jq -r .variables.content)"
lin "$ACME" project update keel --body "$T/body.md" >/dev/null
eq "project update sends only what it was given" "project-keel content" "$(last | jq -r '"\(.variables.id) \(.variables | del(.id) | keys | join(","))"')"
eq "project get prints the project" "keel" "$(lin "$ACME" project get keel | jq -r .name)"
long=$(printf 'x%.0s' {1..255})
lin "$ACME" project update keel --summary "$long" >/dev/null
eq "a summary of Linear's 255 characters is sent" "$long" "$(last | jq -r .variables.description)"
requests=$(sent)
err=$(lin "$ACME" project update keel --summary "${long}x" 2>&1 >/dev/null)
check "one over is refused" grep -q "Linear allows 255" <<<"$err"
eq "before anything is sent" "$requests" "$(sent)"

check "every request went through curl's argument log" test "$(grep -c . "$T/curl-args")" -eq "$(sent)"
check "the key never appears in any output, error, request body or curl command line" \
  test -z "$(grep -F "$STUB_KEY" "$OUT" "$T/linear.log" "$T/curl-args")"
rm "$T/stubs/curl"
kill "$LINEAR_STUB"
wait "$LINEAR_STUB" 2>/dev/null
trap 'rm -rf "$T"' EXIT
unset KEEL_LINEAR_URL LINEAR_KEY_ACME LINEAR_KEY_OTHER
rm "$PACK/linear"

section "isolation"
eq "harness paths are byte for byte unchanged after every keel command above" "$before" "$(snapshot_harness)"
# The check above is only worth something if it can fail: an install pointed
# at a harness path on purpose must change the snapshot.
cp -r "$ROOT" "$T/bad"
# shellcheck disable=SC2016 # the pair is written into install.sh, which expands it
sed -i 's#^PAIRS=(#PAIRS=(\n  "$ROOT/rules/CLAUDE.md|$HOME/.claude/CLAUDE.md"#' "$T/bad/install.sh"
"$T/bad/install.sh" >/dev/null
refute "an install that writes a harness path is caught" test "$before" == "$(snapshot_harness)"

summary

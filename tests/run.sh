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
eq "install writes only under ~/.keel and ~/.local/bin/keel" "" \
  "$(grep -v -e "^linked   $HOME/.keel/" -e "^wrote    $HOME/.keel/you/" -e "^git init $HOME/.keel/you\$" \
    -e "^current  $HOME/.keel/current -> $ROOT\$" \
    -e "^merged   keel's settings into $HOME/.keel/you/settings.json\$" -e "^linked   $HOME/.local/bin/keel\$" <<<"$out")"
eq "running install again changes nothing" "" "$("$ROOT/install.sh")"
check "--check is clean after install" "$ROOT/install.sh" --check
check "settings.json is valid JSON, or Claude Code would drop every permission" jq empty "$HOME/.keel/claude/settings.json"
# A hook left out never fires, and one that runs harness acts on harness's
# trees: each event must reach the keel hook that handles it, and only that.
eq "settings wire each hook event to keel's hook for it, never harness's" \
  "$(printf '%s\n' 'PostToolUse handback' 'PreToolUse git-guard' 'SessionStart context' 'Stop stop' 'SubagentStart context' 'SubagentStop subagent-stop' 'WorktreeCreate worktree-create' 'WorktreeRemove worktree-remove')" \
  "$(jq -r '.hooks | to_entries[] | .key + " " + (.value[].hooks[].command | ltrimstr("\"$HOME/.local/bin/keel\" hook "))' "$HOME/.keel/claude/settings.json" | sort)"
eq "git-guard guards Bash and blocks the command when it cannot run" "Bash block" \
  "$(jq -r '.hooks.PreToolUse[0] | "\(.matcher) \(.hooks[0].onFailure)"' "$HOME/.keel/claude/settings.json")"
# A keel session under the home directory would otherwise load harness's
# ~/.claude/CLAUDE.md as a project file: Claude Code reads .claude/CLAUDE.md
# in every directory above the one it starts in.
excludes() { jq -r '.claudeMdExcludes[]' "$HOME/.keel/claude/settings.json"; }
excluded() { # excluded <path> -> whether some pattern matches it, a * within one segment as Claude Code's globs match
  local pattern i
  local -a path parts
  IFS=/ read -r -a path <<<"$1"
  while IFS= read -r pattern; do
    IFS=/ read -r -a parts <<<"$pattern"
    [[ ${#parts[@]} -eq ${#path[@]} ]] || continue
    for i in "${!parts[@]}"; do
      # shellcheck disable=SC2053 # each part is a glob on purpose
      [[ "${path[i]}" == ${parts[i]} ]] || continue 2
    done
    return 0
  done < <(excludes)
  return 1
}
check "settings leave out a Linux home's own .claude/CLAUDE.md" excluded /home/someone/.claude/CLAUDE.md
check "and a macOS home's" excluded /Users/someone/.claude/CLAUDE.md
refute "but never a repository's .claude/CLAUDE.md" excluded /home/someone/app/.claude/CLAUDE.md
refute "nor its own CLAUDE.md" excluded /home/someone/app/CLAUDE.md
rm "$HOME/.keel/claude/CLAUDE.md"
out=$("$ROOT/install.sh" --check)
refute "--check fails on a removed link" "$ROOT/install.sh" --check
check "and names it MISSING" grep -qx "MISSING: $HOME/.keel/claude/CLAUDE.md" <<<"$out"
"$ROOT/install.sh" >/dev/null
eq "install puts it back" "$HOME/.keel/current/rules/keel.md" "$(readlink "$HOME/.keel/claude/CLAUDE.md")"
eq "install links every skill in method/, trust/ and learning/" "$(for d in "$ROOT"/method/skills/*/ "$ROOT"/trust/skills/*/ "$ROOT"/learning/skills/*/; do basename "$d"; done | sort)" "$(ls "$HOME/.keel/claude/skills")"
eq "each to its directory in the repository, through ~/.keel/current" "$HOME/.keel/current/method/skills/spec" "$(readlink "$HOME/.keel/claude/skills/spec")"
eq "and the keel-agent subagent" "$HOME/.keel/current/method/agents/keel-agent.md" "$(readlink "$HOME/.keel/claude/agents/keel-agent.md")"
check "and method/, where the router and skills read playbooks by an absolute path" test -f "$HOME/.keel/method/playbooks/issue.md"
ln -s "$T/gone" "$HOME/.keel/claude/skills/gone"
out=$("$ROOT/install.sh" --check)
refute "--check fails on a skill gone from the repository" "$ROOT/install.sh" --check
check "and names it DANGLING" grep -qx "DANGLING: $HOME/.keel/claude/skills/gone" <<<"$out"
"$ROOT/install.sh" >/dev/null
check "and install removes its link" test ! -L "$HOME/.keel/claude/skills/gone"
echo stale >"$HOME/.keel/claude/VOICE.md.tmp" && mv "$HOME/.keel/claude/VOICE.md.tmp" "$HOME/.keel/claude/VOICE.md"
"$ROOT/install.sh" >/dev/null
eq "a link replaced with a file is relinked" "$HOME/.keel/you/VOICE.md" "$(readlink "$HOME/.keel/claude/VOICE.md")"
eq "and the file is kept as .bak" "stale" "$(cat "$HOME/.keel/claude/VOICE.md.bak")"

section "your own files"
YOU="$HOME/.keel/you"
check "install makes ~/.keel/you from the starter files" cmp "$ROOT/templates/you/VOICE.md" "$YOU/VOICE.md"
# --git-dir, so a repository above a TMPDIR cannot answer for it.
check "with a git history of its own" git --git-dir="$YOU/.git" rev-parse --git-dir
echo "I write short." >"$YOU/VOICE.md"
"$ROOT/install.sh" >/dev/null
eq "install keeps a file you wrote" "I write short." "$(cat "$YOU/VOICE.md")"
eq "keel's rules end by importing yours" "@~/.keel/you/CLAUDE.md" "$(tail -n 1 "$HOME/.keel/claude/CLAUDE.md")"
rm "$YOU/OPINIONS.md"
out=$("$ROOT/install.sh" --check)
check "--check names a file gone from ~/.keel/you MISSING" grep -qx "MISSING: $YOU/OPINIONS.md, which \`keel init\` makes" <<<"$out"
"$ROOT/install.sh" >/dev/null
check "and install writes it again" cmp "$ROOT/templates/you/OPINIONS.md" "$YOU/OPINIONS.md"

section "settings merge"
live="$YOU/settings.json"
allowed() { jq -e --arg r "$1" '.permissions.allow | index($r)' "$live"; }
# shellcheck disable=SC2317,SC2329 # called through check and refute
denied() { jq -e --arg r "$1" '.permissions.deny | index($r)' "$live"; }
# Claude Code writes to the live file itself, and the user adds to it.
jq '.theme = "light" | .permissions.allow += ["Bash(make:*)"] | .permissions.defaultMode = "default"' "$live" >"$T/s" && cat "$T/s" >"$live"
"$ROOT/install.sh" >/dev/null
eq "install keeps what Claude Code and you wrote" "light default" "$(jq -r '"\(.theme) \(.permissions.defaultMode)"' "$live")"
check "and your own allow rule" allowed "Bash(make:*)"
jq '.permissions.deny -= ["Bash(git reset:*)"]' "$live" >"$T/s" && cat "$T/s" >"$live"
out=$("$ROOT/install.sh" --check)
refute "--check fails when a keel deny is gone from your settings" "$ROOT/install.sh" --check
check "and names the file NOT MERGED" grep -qx "NOT MERGED: keel's settings into $live" <<<"$out"
"$ROOT/install.sh" >/dev/null
check "install puts keel's deny back" denied "Bash(git reset:*)"
# A newer keel adds a deny and drops an allow; going back to this one undoes both.
cp -r "$ROOT" "$T/newer"
jq '.permissions.deny += ["Bash(newer-deny)"] | .permissions.allow -= ["Bash(git blame:*)"]' \
  "$ROOT/rails/settings.json" >"$T/newer/rails/settings.json"
"$T/newer/install.sh" >/dev/null
check "a newer keel's deny reaches your settings" denied "Bash(newer-deny)"
refute "and the allow it dropped leaves them" allowed "Bash(git blame:*)"
check "while your allow stays" allowed "Bash(make:*)"
"$ROOT/install.sh" >/dev/null
refute "going back to the older keel takes its deny out" denied "Bash(newer-deny)"
check "and brings back the allow" allowed "Bash(git blame:*)"
eq "keeping what Claude Code and you wrote" "light default" "$(jq -r '"\(.theme) \(.permissions.defaultMode)"' "$live")"
check "install is clean after going back" "$ROOT/install.sh" --check
before_broken=$(cat "$live")
echo '{"permissions": ' >"$live"
# The newer keel, so there is something to merge: with nothing new, install
# would leave the file alone even without its guard.
err=$("$T/newer/install.sh" 2>&1 >/dev/null)
refute "install fails on settings that are not valid JSON" test $? -eq 0
check "and names the file BROKEN" grep -q "^BROKEN: $live " <<<"$err"
eq "and leaves the file as it was" '{"permissions": ' "$(cat "$live")"
echo "$before_broken" >"$live"
"$ROOT/install.sh" >/dev/null

section "versions"
# A GitHub served from files: tag archives as GitHub builds them, with one
# top directory, and the API's newest release.
GH="$T/github"
mkdir -p "$GH/web/acme/keel/archive/refs/tags" "$GH/api/repos/acme/keel/releases" "$T/release-src"
tar -C "$ROOT" --exclude=.git -cf - . | (mkdir -p "$T/release-src/base" && tar -C "$T/release-src/base" -xf -)
cp -r "$T/release-src/base" "$T/release-src/two"
echo "TWO RULE: this is the second release." >>"$T/release-src/two/rules/keel.md"
release() { # release <version> <source dir name>: publish it, and make it the newest
  tar -C "$T/release-src" -czf "$GH/web/acme/keel/archive/refs/tags/$1.tar.gz" \
    --transform "s|^$2|keel-${1#v}|" "$2"
  echo "{\"tag_name\": \"$1\"}" >"$GH/api/repos/acme/keel/releases/latest"
}
kv() { KEEL_REPO=acme/keel KEEL_GITHUB="file://$GH/web" KEEL_API="file://$GH/api" "$K" "$@"; }
rules() { cat "$HOME/.keel/claude/CLAUDE.md"; }
release v2026.01.01.1 base
release v2026.01.02.1 two
# The version before is the checkout, not a release, so pruning has no release to keep for it.
check "keel update succeeds when the version before is not a release" kv update
eq "keel update installs the newest release" "v2026.01.02.1" "$(kv version)"
check "and sessions load its rules" grep -q "TWO RULE" <<<"$(rules)"
ln -s "$HOME" "$T/home-link"
eq "keel version names it when HOME is reached through a link" "v2026.01.02.1" "$(HOME="$T/home-link" kv version)"
eq "through ~/.keel/current" "$HOME/.keel/versions/v2026.01.02.1" "$(readlink "$HOME/.keel/current")"
check "which a checkout's install.sh --check reports as not current" grep -q "^NOT CURRENT: $HOME/.keel/current -> " <<<"$("$ROOT/install.sh" --check)"
kv update v2026.01.01.1 >/dev/null
eq "keel update <version> switches to that one" "v2026.01.01.1" "$(kv version)"
refute "and its rules replace the newer one's" grep -q "TWO RULE" <<<"$(rules)"
kv rollback >/dev/null
eq "keel rollback goes back to the version before" "v2026.01.02.1" "$(kv version)"
check "with its rules" grep -q "TWO RULE" <<<"$(rules)"
kv use "$ROOT" >/dev/null
eq "keel use <checkout> runs sessions on the checkout" "$ROOT (a checkout, through keel use)" "$(kv version)"
eq "so an edit there is the live file" "$ROOT/rules/keel.md" "$(readlink -f "$HOME/.keel/claude/CLAUDE.md")"
kv rollback >/dev/null
eq "and keel rollback leaves it for the release again" "v2026.01.02.1" "$(kv version)"
refute "a version that was never released fails" kv update v2026.01.03.1
eq "leaving nothing half unpacked" "$(printf 'v2026.01.0%s.1\n' 1 2)" "$(ls -A "$HOME/.keel/versions")"
eq "and the version in use as it was" "v2026.01.02.1" "$(kv version)"
# An archive under a name that is not a version, so only the name check can refuse it.
cp "$GH/web/acme/keel/archive/refs/tags/v2026.01.01.1.tar.gz" "$GH/web/acme/keel/archive/refs/tags/main.tar.gz"
refute "a name that is not a version is refused" kv update main
check "and installs nothing" test ! -e "$HOME/.keel/versions/main"
# A release from before keel managed ~/.keel/current: its install.sh never takes it over.
cp -r "$T/release-src/base" "$T/release-src/old" && sed -i '/^switch_current$/d' "$T/release-src/old/install.sh"
tar -C "$T/release-src" -czf "$GH/web/acme/keel/archive/refs/tags/v2026.01.00.1.tar.gz" --transform "s|^old|keel-2026.01.00.1|" old
check "a release from before version switching is refused by name" grep -q "predates keel's version switching" <<<"$(kv update v2026.01.00.1 2>&1)"
eq "and the version in use stays" "v2026.01.02.1" "$(kv version)"
# Claude Code records each running session as sessions/<pid>.json; this shell stands in for one.
mkdir -p "$HOME/.keel/claude/sessions" && echo "{\"pid\": $$}" >"$HOME/.keel/claude/sessions/$$.json"
check "a switch warns when a keel session is running" grep -q "1 keel session(s) running" <<<"$(kv update v2026.01.01.1 2>&1 >/dev/null)"
eq "keel update switches to a version already downloaded" "v2026.01.01.1" "$(kv version)"
rm "$HOME/.keel/claude/sessions/$$.json"
(exit 0) &
gone=$!
wait "$gone"
echo "{\"pid\": $gone}" >"$HOME/.keel/claude/sessions/$gone.json"
refute "but not for a session that has exited" grep -q "session(s) running" <<<"$(kv update v2026.01.01.1 2>&1 >/dev/null)"
rm "$HOME/.keel/claude/sessions/$gone.json"
for d in 03 04 05 06 07; do release "v2026.01.$d.1" base; kv update >/dev/null; done
eq "keel keeps the newest 5 versions" "$(printf 'v2026.01.%s.1\n' 03 04 05 06 07)" "$(ls "$HOME/.keel/versions")"
kv update v2026.01.01.1 >/dev/null
eq "and the one in use, however old" "$(printf 'v2026.01.%s.1\n' 01 03 04 05 06 07)" "$(ls "$HOME/.keel/versions")"
release v2026.01.08.1 base
kv update >/dev/null
kv rollback >/dev/null
eq "and the one keel rollback goes back to" "v2026.01.01.1" "$(kv version)"
check "bootstrap.sh succeeds on a new machine, with no version before" \
  env HOME="$T/fresh" KEEL_REPO=acme/keel KEEL_GITHUB="file://$GH/web" KEEL_API="file://$GH/api" "$ROOT/bootstrap.sh"
eq "bootstrap.sh installs the newest release on a new machine" "$T/fresh/.keel/versions/v2026.01.08.1" "$(readlink "$T/fresh/.keel/current")"
check "with starter files in ~/.keel/you" test -f "$T/fresh/.keel/you/CLAUDE.md"
"$ROOT/install.sh" >/dev/null
eq "running a checkout's install.sh makes it current again" "$ROOT" "$(readlink "$HOME/.keel/current")"
"$HOME/.keel/current/install.sh" >/dev/null
eq "and running it through ~/.keel/current leaves current on the real path" "$ROOT" "$(readlink "$HOME/.keel/current")"
check "where --check is clean" "$HOME/.keel/current/install.sh" --check

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

section "templates"
mkdir -p "$PACK/templates"
{ cat "$ROOT/templates/issue.md"; printf '\n## Acme review\n'; } >"$PACK/templates/issue.md"
echo "# Acme RFC" >"$PACK/templates/rfc.md"
eq "with no pack the core's template prints" "$(cat "$ROOT/templates/issue.md")" "$($K template issue "$OTHER")"
eq "a pack's template replaces the core's" "$(cat "$PACK/templates/issue.md")" "$($K template issue "$ACME")"
eq "a template the pack lacks falls back to the core's" "$(cat "$ROOT/templates/project.md")" "$($K template project "$ACME")"
eq "no name lists the core's templates and the pack's, once each" "$(printf 'issue\nproject\nrfc')" "$(cd "$ACME" && $K template)"
refute "an unknown template fails" "$K" template nope "$ACME"
refute "a path is not a template name, even one that resolves to a template" "$K" template ../templates/issue "$ACME"
rm -r "$PACK/templates"

section "context hook"
out=$(jq -n --arg c "$ACME" '{hook_event_name:"SessionStart",source:"startup",cwd:$c}' | $K hook context)
ctx=$(jq -r .hookSpecificOutput.additionalContext <<<"$out")
check "SessionStart in an owned repo injects the rules" grep -q "ACME RULE" <<<"$ctx"
check "and tells the session to run keel where the rules name harness" grep -qF 'where these rules name `harness <verb>`, run `keel <verb>`' <<<"$ctx"
check "and points at keel's CLAUDE.md, not harness's" grep -qF "~/.keel/claude/CLAUDE.md" <<<"$ctx"
eq "SessionStart output names its event" "SessionStart" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")"
out=$(jq -n --arg c "$ACME" '{hook_event_name:"SubagentStart",cwd:$c}' | $K hook context)
eq "SubagentStart output names its event" "SubagentStart" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")"
sub=$(jq -r .hookSpecificOutput.additionalContext <<<"$out")
check "a subagent gets the pack's rules too" grep -q "ACME RULE" <<<"$sub"
refute "but not the router, so it never routes a task of its own" grep -qF "$(head -1 "$ROOT/method/router.md")" <<<"$sub"
check "it is told to follow its brief instead" grep -q "follow your brief" <<<"$sub"
router=$(cat "$ROOT/method/router.md")
check "a main session gets the router, whole" test "${ctx#*"$router"}" != "$ctx"
out=$(jq -n --arg c "$OTHER" '{hook_event_name:"SessionStart",source:"startup",cwd:$c}' | $K hook context)
eq "an unowned repo gets the router and no pack rules" "$(cat "$ROOT/method/router.md")" "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")"

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
eq "with no pack the tree is cut from the default branch" "$(git -C "$OTHER" rev-parse origin/main)" "$(git -C "$Q" rev-parse HEAD)"
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
# A stack whose new session starts late, as on a loaded machine, is still
# starting, not dead: setsid made slow takes the race out of chance.
mkdir -p "$T/slow"
printf '#!/bin/sh\nsleep 1\nexec %s "$@"\n' "$(command -v setsid)" >"$T/slow/setsid"
chmod +x "$T/slow/setsid"
KS=$(create "$ACME" feature/acme-3-slow)
out=$(cd "$KS" && PATH="$T/slow:$PATH" $K stack up 2>/dev/null)
eq "up waits for a stack whose session starts late" "http://127.0.0.1:$STACK_PORT/" "$out"
(cd "$KS" && $K stack down >/dev/null)

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

section "runs"
RUNS="$HOME/.local/state/keel/runs"
printf '1. Reproduce it.\n2. Narrow the cause.\n\n- Fix it at the root.\n' >"$T/steps.md"
R1=$(create "$ACME" feature/run-1)
in_r1() { (cd "$R1" && "$K" "$@"); }
st() { (cd "$R1" && "$K" status --json .) | jq -rc "$1"; } # st <jq filter on the array>
eq "a tree with no run has an empty status" "[]" "$(in_r1 status --json .)"
in_r1 run start --playbook bug-fix --goal "The cart survives being empty." --steps "$T/steps.md" >/dev/null
eq "start records the run under the tree's key" "$R1" "$(jq -r .tree "$RUNS/${R1//[\/.]/-}/status.json")"
eq "status lists it with its playbook, goal, branch and state" '["bug-fix","The cart survives being empty.","feature/run-1","active"]' \
  "$(st '.[0] | [.playbook, .goal, .branch, .state]')"
eq "with the steps from the file, numbering and bullets dropped" '["Reproduce it.","Narrow the cause.","Fix it at the root."]' "$(st '[.[0].steps[].title]')"
# The schema in docs/status.md: every field present, with its type. A missing
# key reads as null in jq, so presence is checked by name.
eq "status follows docs/status.md version 1" "true" "$(st '.[0] | (["version","tree","branch","playbook","playbook_hash","goal","state",
    "steps","current","started_at","updated_at","stale","attention","done_check","verifier","gate"] - keys) == []
  and .version == 1
  and (.tree|type) == "string" and (.branch|type) == "string" and (.playbook|type) == "string"
  and (.goal|type) == "string" and (.state|IN("active","paused","done","stopped","failed"))
  and (.steps|type) == "array" and all(.steps[]; (.title|type) == "string" and (.state|IN("pending","doing","done","skipped")) and has("reason") and has("skip_code") and .skip_code == null and .attempts == [])
  and (.current == null or (.current|type) == "number")
  and all(.started_at, .updated_at; test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and (.stale|type) == "boolean"
  and .attention == 0 and .done_check == null and .contract_hash == null and .verifier == null and .gate == null')"
refute "a second run in the same tree is refused" in_r1 run start --playbook issue --goal g --steps "$T/steps.md"
in_r1 run step 1 doing
eq "a step being worked on is the current one" "1 doing" "$(st '.[0] | "\(.current) \(.steps[0].state)"')"
in_r1 run step 1 "done"
eq "finishing it moves current to the next open step" "2" "$(st '.[0].current')"
refute "a skip needs its code" in_r1 run step 2 skip
check "a skip without one of the four codes is refused, naming them" grep -qF "not-applicable, already-done, user-said, blocked" <<<"$(in_r1 run step 2 skip no ui 2>&1)"
refute "and so is a note left unquoted" in_r1 run step 2 skip not-applicable no ui change
refute "and so are two codes given as one" in_r1 run step 2 skip "already-done user-said"
refute "and so is a code with a second line" in_r1 run step 2 skip $'blocked\nx'
refute "doing and done take no code or note" in_r1 run step 2 "done" "" "a note"
eq "leaving the step as it was" "pending" "$(st '.[0].steps[1].state')"
refute "a step past the last is refused" in_r1 run step 9 doing
in_r1 run step 2 skip already-done "the repro already names the cause"
eq "a skipped step keeps its code and its note" '["skipped","already-done","the repro already names the cause"]' "$(st '.[0].steps[1] | [.state, .skip_code, .reason]')"
eq "and current moves past it" "3" "$(st '.[0].current')"
eq "a step's attempt records when it started, when it ended and how" "1 done true" \
  "$(st '.[0].steps[0].attempts | "\(length) \(.[0].state) \(all(.[]; (.started_at|test("Z$")) and (.ended_at|test("Z$"))))"')"
eq "a run records the hash of the playbook file it followed" "$(sha256sum "$ROOT/method/playbooks/bug-fix.md" | cut -d' ' -f1)" "$(st '.[0].playbook_hash')"
in_r1 run step 1 doing
eq "going back to a finished step opens a second attempt" "done doing" "$(st '[.[0].steps[0].attempts[].state] | join(" ")')"
in_r1 run step 3 doing
in_r1 run step 3 doing
eq "starting another step closes the open attempt as left" "left" "$(st '.[0].steps[0].attempts[-1].state')"
eq "and setting a step to doing twice keeps one attempt open" "1" "$(st '.[0].steps[2].attempts | length')"
in_r1 run step 1 "done"
eq "status for a path inside the tree finds its run" "bug-fix" "$(mkdir -p "$R1/src" && cd "$R1/src" && "$K" status --json . | jq -r '.[0].playbook')"
eq "status for another tree lists nothing" "[]" "$("$K" status --json "$OTHER")"
eq "status with no path lists every run" "1" "$("$K" status --json | jq length)"

eq "a skipped step is flagged for attention in the log" "1|skipped step 2|already-done: the repro already names the cause" \
  "$(st '.[0].attention')|$(cut -f3,4 --output-delimiter='|' "$(in_r1 run dir)/decisions.tsv")"

section "runs keep their trees"
listed=$(cd "$ACME" && $K sweep 2>&1)
check "a dry sweep names the run holding the tree" grep -qxF "kept $R1: run bug-fix active at step 3, stale" <<<"$listed"
swept=$(cd "$ACME" && $K sweep --apply 2>&1)
eq "sweep keeps a clean tree whose run is active" "leased" "$(lease_status "$ACME" "$R1")"
check "and says which run holds it" grep -qF "kept $R1: run bug-fix active at step 3" <<<"$swept"
eq "and marks the run stale, since nothing runs in its tree" "true" "$(st '.[0].stale')"
jq -n --arg p "$R1" '{hook_event_name:"WorktreeRemove",worktree_path:$p}' | $K hook worktree-remove >/dev/null 2>&1
eq "WorktreeRemove keeps a tree whose run is active" "leased" "$(lease_status "$ACME" "$R1")"
A2=$(create "$ACME" agent-fff666)
(cd "$A2" && "$K" run start --playbook issue --goal g --steps "$T/steps.md" >/dev/null)
stop "$A2" fff666
eq "SubagentStop keeps its tree while the run is active" "leased" "$(lease_status "$ACME" "$A2")"
(cd "$A2" && "$K" run stop "done" >/dev/null)
stop "$A2" fff666
eq "and returns it once the run has ended" "available" "$(lease_status "$ACME" "$A2")"

printf 'Goal: the cart.\nNext: write the regression test.\n' | in_r1 run pause >/dev/null
eq "pause sets the run to paused" "paused" "$(st '.[0].state')"
eq "and closes the open attempt as paused" "paused" "$(st '.[0].steps[2].attempts[-1].state')"
eq "with the resume note in its folder" "Next: write the regression test." "$(tail -1 "$(in_r1 run dir)/resume.md")"
eq "a paused run is not stale" "false" "$(st '.[0].stale')"
(cd "$ACME" && $K sweep --apply >/dev/null 2>&1)
eq "sweep keeps a tree whose run is paused" "leased" "$(lease_status "$ACME" "$R1")"
in_r1 run step 3 doing
eq "moving a step resumes a paused run" "active" "$(st '.[0].state')"

in_r1 run start --playbook issue --goal "Another goal." --steps "$T/steps.md" --replace >/dev/null
eq "--replace starts the new run" "issue" "$(st '.[0].playbook')"
eq "and archives the old one as stopped" "stopped replaced by a new run" \
  "$(jq -r 'select(.note == "replaced by a new run") | "\(.state) \(.note)"' "$RUNS"/archive/*/*/status.json)"
eq "closing its open attempt as ended" "ended" \
  "$(jq -r 'select(.note == "replaced by a new run") | .steps[2].attempts[-1].state' "$RUNS"/archive/*/*/status.json)"
(cd "$ACME" && "$K" run stop stopped --tree "$R1" --note "cleared by hand" >/dev/null)
eq "stop --tree ends a run from outside its tree" "[]" "$(in_r1 status --json .)"
eq "and archives it with its state and note" "stopped" "$(jq -r 'select(.note == "cleared by hand") | .state' "$RUNS"/archive/*/*/status.json)"
(cd "$ACME" && $K sweep --apply >/dev/null 2>&1)
eq "with the run ended, sweep returns the clean tree" "available" "$(lease_status "$ACME" "$R1")"

(cd "$ACME" && "$K" run start --playbook investigation --goal g --steps "$T/steps.md" >/dev/null)
eq "a run starts in a repository's main checkout too" "$ACME" "$("$K" status --json "$ACME" | jq -r '.[0].tree')"
# An archive already holding a run that started in the same second.
key=${ACME//[\/.]/-}
mkdir -p "$RUNS/archive/$key/$(jq -r .started_at "$RUNS/$key/status.json")"
(cd "$ACME" && "$K" run stop "done" >/dev/null)
eq "ending it never overwrites a run archived in the same second" "2" "$(find "$RUNS/archive/$key" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"

section "runs are written whole"
R2=$(create "$ACME" feature/run-2)
(cd "$R2" && "$K" run start --playbook issue --goal g --steps "$T/steps.md" >/dev/null)
f="$RUNS/${R2//[\/.]/-}/status.json"
# A run recorded before attempts existed has no attempts key on its steps.
jq 'del(.playbook_hash, .steps[].attempts)' "$f" >"$T/old-run.json" && mv "$T/old-run.json" "$f"
(cd "$R2" && "$K" run step 1 doing)
eq "a run recorded before attempts starts recording them" "1" "$(jq '.steps[0].attempts | length' "$f")"
(for _ in {1..60}; do (cd "$R2" && "$K" run step 1 doing && "$K" run step 1 "done") >/dev/null; done) &
writer=$!
torn=0
while kill -0 "$writer" 2>/dev/null; do jq -e .steps "$f" >/dev/null 2>&1 || torn=$((torn + 1)); done
wait "$writer"
eq "a reader polling during writes never sees a partial file" "0" "$torn"
(cd "$R2" && "$K" run step 2 doing && "$K" run step 2 skip already-done "covered by step 1") >/dev/null
eq "skipping a step being worked on closes its attempt as skipped" "skipped" "$(jq -r '.steps[1].attempts[-1].state' "$f")"
(cd "$R2" && "$K" run step 3 skip blocked >/dev/null)
eq "a skip with a code and no note has a null reason" '["blocked",null]' "$(jq -c '.steps[2] | [.skip_code, .reason]' "$f")"
(cd "$R2" && "$K" run stop "done" >/dev/null)
(cd "$R2" && "$K" run start --playbook no-such-playbook --goal g --steps "$T/steps.md" >/dev/null)
eq "a run for a playbook with no file records a null hash" "null" "$(jq -r .playbook_hash "$f")"
(cd "$R2" && "$K" run stop stopped >/dev/null)

section "contracts"
R3=$(create "$ACME" feature/run-3)
in_r3() { (cd "$R3" && "$K" "$@"); }
st3() { (cd "$R3" && "$K" status --json .) | jq -rc "$1"; }
hook_stop() { jq -n --arg c "$R3" '{hook_event_name:"Stop",cwd:$c,stop_hook_active:false}' | $K hook stop; }
last_row() { tail -1 "$(in_r3 run dir)/decisions.tsv" | cut -f"$1" --output-delimiter='|'; }
contract() { # contract <done command> [budget] -> a contract file
  {
    printf 'goal: done.txt exists\ndone: %s\ngive-up: never\n' "$1"
    [[ -z "${2:-}" ]] || printf 'budget: %s\n' "$2"
    printf 'grants: commit\n\nNotes.\n'
  } >"$T/contract.md"
  echo "$T/contract.md"
}
printf 'goal: g\n\ndone: true\n' >"$T/no-done.md"
err=$(in_r3 run start --playbook issue --goal g --steps "$T/steps.md" --contract "$T/no-done.md" 2>&1)
check "a contract with no done: line in its header is refused" grep -q "no done: line" <<<"$err"
err=$(in_r3 run start --playbook issue --goal g --steps "$T/steps.md" --contract "$(contract "test -f done.txt" 2x)" 2>&1)
check "a budget that is not a duration is refused" grep -q "not a duration" <<<"$err"
printf 'done: false\ngrants: merge\n' >"$T/bad-grant.md"
err=$(in_r3 run start --playbook issue --goal g --steps "$T/steps.md" --contract "$T/bad-grant.md" 2>&1)
check "a grant keel does not know is refused" grep -q "grants: merge is not" <<<"$err"
err=$(in_r3 run start --playbook issue --goal g --steps "$T/steps.md" --contract "$(contract true)" 2>&1)
check "a done check that already passes is refused" grep -q "already passes" <<<"$err"
eq "and starts no run" "[]" "$(in_r3 status --json .)"
in_r3 run start --playbook issue --goal g --steps "$T/steps.md" --contract "$(contract true)" --allow-passing >/dev/null
check "unless --allow-passing" test "$(st3 '.[0].contract_hash')" != null
in_r3 run stop stopped >/dev/null

in_r3 run start --playbook issue --goal g --steps "$T/steps.md" >/dev/null
eq "a run with no contract is never held" "" "$(hook_stop)"
in_r3 run stop "done" >/dev/null
in_r3 run start --playbook issue --goal "done.txt exists" --steps "$T/steps.md" --contract "$(contract 'test -f done.txt && echo checked || { echo "no done.txt yet"; exit 3; }' 1h)" >/dev/null
eq "start records the contract's hash" "$(sha256sum "$T/contract.md" | cut -d' ' -f1)" "$(st3 '.[0].contract_hash')"
cp "$T/contract.md" "$T/approved.md"
refute "a second contracted run in a held tree is refused" in_r3 run start --playbook issue --goal g --steps "$T/steps.md" --contract "$(contract "touch $T/ran; false")"
check "before its done command ever runs" test ! -e "$T/ran"
cp "$T/approved.md" "$T/contract.md"
out=$(hook_stop)
eq "a failing done check blocks the turn" "block" "$(jq -r .decision <<<"$out")"
check "quoting the failure" grep -qF "no done.txt yet" <<<"$(jq -r .reason <<<"$out")"
check "and naming the give-up file" grep -qF "$(in_r3 run dir)/giveup.md" <<<"$(jq -r .reason <<<"$out")"
check "and the done command, so a check that fails silently still says what to fix" grep -qF 'test -f done.txt' <<<"$(jq -r .reason <<<"$out")"
eq "the check is recorded in status, at HEAD" "3 false $(git -C "$R3" rev-parse HEAD)" "$(st3 '.[0].done_check | "\(.exit) \(.passed) \(.head)"')"
eq "logged and flagged for attention" "done check|fail, exit 3|yes" "$(last_row 3,6,7)"
eq "and counted" "1" "$(st3 '.[0].attention')"
in_r3 run decide "kept the old parser" --why "the new one drops comments" --evidence src/parse.ts:12 --attention
eq "decide adds the agent's own row" "kept the old parser|the new one drops comments|src/parse.ts:12" "$(last_row 3,4,5)"
eq "and --attention counts it" "2" "$(st3 '.[0].attention')"
refute "a decision needs its evidence" in_r3 run decide "x" --why y
touch "$R3/done.txt"
eq "a passing done check lets the turn end" "" "$(hook_stop)"
eq "and records the pass" "0 true checked" "$(st3 '.[0].done_check | "\(.exit) \(.passed) \(.tail)"')"
eq "logged without a flag" "pass|" "$(last_row 6,7)"
eq "and not counted" "2" "$(st3 '.[0].attention')"
eq "a pass does not end the run on its own" "active" "$(st3 '.[0].state')"
git -C "$R3" commit -q --allow-empty -m "after the check"
refute "a contracted run is not done while its check has not passed at HEAD" in_r3 run stop "done"
rm "$R3/done.txt"
sed -i 's/^done: .*/done: touch done.txt/' "$(in_r3 run dir)/contract.md"
out=$(hook_stop)
eq "a contract changed mid-run blocks the turn" "block" "$(jq -r .decision <<<"$out")"
eq "and is flagged" "contract changed mid-run|yes" "$(last_row 3,7)"
check "and its changed command never runs" test ! -f "$R3/done.txt"
cp "$T/contract.md" "$(in_r3 run dir)/contract.md"
in_r3 run step 1 doing
echo "the parser cannot be fixed without the vendor" >"$(in_r3 run dir)/giveup.md"
eq "a written give-up lets the failing turn end" "" "$(hook_stop)"
eq "and stops the run with the reason" "stopped gave up" "$(st3 '.[0] | "\(.state) \(.reason)"')"
eq "closing the open attempt as ended" "ended" "$(st3 '.[0].steps[0].attempts[-1].state')"
eq "flagged for attention" "gave up|yes" "$(last_row 3,7)"
eq "a run that gave up stays listed for its attention" "1" "$(in_r3 status --json . | jq length)"
eq "but no longer holds the tree" "" "$(cd "$ACME" && $K sweep 2>&1 | grep -F "kept $R3: run")"
rm "$(in_r3 run dir)/giveup.md"
eq "a stopped run is never held again" "" "$(hook_stop)"
in_r3 run start --playbook issue --goal g --steps "$T/steps.md" --contract "$(contract "test -f done.txt" 1h30m)" >/dev/null
eq "a new run archives the one that gave up" "stopped" "$(jq -r 'select(.reason == "gave up") | .state' "$RUNS"/archive/*/*/status.json)"
eq "a budget not yet spent still holds the turn" "block" "$(hook_stop | jq -r .decision)"
in_r3 run step 1 doing
# Started two hours ago, past its budget of an hour and a half.
jq --arg t "$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)" '.started_at = $t' "$(in_r3 run dir)/status.json" >"$T/backdated.json"
mv "$T/backdated.json" "$(in_r3 run dir)/status.json"
out=$(hook_stop)
eq "a spent budget lets the failing turn end" "null" "$(jq -r .decision <<<"$out")"
check "asking for a give-up write-up" grep -q "giveup.md" <<<"$(jq -r .systemMessage <<<"$out")"
eq "and fails the run for its budget" "failed budget" "$(st3 '.[0] | "\(.state) \(.reason)"')"
eq "closing the open attempt as ended" "ended" "$(st3 '.[0].steps[0].attempts[-1].state')"
in_r3 run stop failed >/dev/null

section "grants"
# A clone of its own, and a contract per case. guard_why prints the reason git-guard gives, if any, and
# "hook failed" when the hook errors, since Claude Code then blocks the command:
# an empty reason alone would read an erroring guard as one that lets it through.
GR="$T/work/acme/granted"
git clone -q "$T/remotes/acme/app" "$GR"
git -C "$GR" switch -q -c feature/granted origin/develop
guard_why() { # guard_why <command> [cwd] -> deny reason, nothing, or "hook failed"
  local out
  out=$(jq -n --arg c "$1" --arg d "${2:-$GR}" '{tool_input: {command: $c}, cwd: $d}' | $K hook git-guard) || {
    echo "hook failed"
    return
  }
  jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$out"
}
granted() { # granted <grants> -> starts a contracted run in GR
  (cd "$GR" && "$K" run stop stopped >/dev/null 2>&1)
  printf 'goal: g\ndone: test -f never\nbudget: 4h\ngrants: %s\n' "$1" >"$T/grant-contract.md"
  (cd "$GR" && "$K" run start --playbook autonomous-run --goal g --steps "$T/steps.md" --contract "$T/grant-contract.md" >/dev/null)
}
verifier_says() { # verifier_says <last message>
  jq -n --arg c "$GR" --arg m "$1" '{hook_event_name:"SubagentStop",cwd:$c,agent_id:"v1",agent_type:"keel-verifier",last_assistant_message:$m}' |
    $K hook subagent-stop
}
gst() { (cd "$GR" && "$K" status --json .) | jq -rc "$1"; }
PUSH_ARGS="push -u origin HEAD:feature/granted"
PUSH="git $PUSH_ARGS"

eq "outside a run a commit is let through" "" "$(guard_why "git commit -m x")"
eq "and so is keel merge, which /merge runs on the user's ask" "" "$(guard_why "keel merge squash 12")"
eq "and so is a push" "" "$(guard_why "$PUSH")"
granted commit
eq "granted commit, a commit on the run's branch goes through" "" "$(guard_why "git commit -m 'fix the parser'")"
eq "and so does the commit plumbing on its branch" "" "$(guard_why "git update-ref refs/heads/feature/granted abc123 def456")"
check "a push names the missing push grant" grep -qF 'does not grant `push`' <<<"$(guard_why "$PUSH")"
check "and is logged for attention" grep -q "refused .git push.*yes$" "$(cd "$GR" && "$K" run dir)/decisions.tsv"
check "a draft PR names the missing draft-pr grant" grep -qF 'does not grant `draft-pr`' <<<"$(guard_why "gh pr create --draft --base develop --title t")"
check "--amend is refused" grep -q "never amends" <<<"$(guard_why "git commit --amend -m x")"
check "moving another branch with update-ref is refused" grep -q "only its own branch" <<<"$(guard_why "git update-ref refs/heads/main abc123")"
git -C "$GR" switch -q -c elsewhere
check "a commit on another branch is refused" grep -q "only on its branch" <<<"$(guard_why "git commit -m x")"
git -C "$GR" switch -q feature/granted
check "through git -C as well" grep -qF 'does not grant `push`' <<<"$(guard_why "git -C $GR $PUSH_ARGS" "$T")"
check "a wrapper it cannot see into is refused" grep -q "cannot see inside" <<<"$(guard_why "bash -c '$PUSH'")"
granted none
check "without the commit grant a commit is refused" grep -qF 'does not grant `commit`' <<<"$(guard_why "git commit -m x")"

granted "commit, push, draft-pr"
check "granted push, a push before /verify names the missing verdict" grep -q "a passing verifier" <<<"$(guard_why "$PUSH")"
check "and so does a draft PR" grep -q "a passing verifier" <<<"$(guard_why "gh pr create --draft --base develop --title t")"
(cd "$GR" && "$K" run step 2 doing)
verifier_says $'Ran the tests.\nVERDICT: pass'
eq "the verifier's pass is recorded against the tree" "pass $(git -C "$GR" rev-parse 'HEAD^{tree}')" "$(gst '.[0].verifier | "\(.verdict) \(.tree)"')"
VH="$HOME/.local/state/keel/verdicts.jsonl"
eq "and kept in the verdict history with the run's playbook and step" "pass autonomous-run 2 $(gst '.[0].started_at')" \
  "$(jq -sr --arg p "$GR" '[.[] | select(.path == $p)] | last | "\(.verdict) \(.playbook) \(.step) \(.run_started_at)"' "$VH")"
eq "with the verifier passing on this tree, the push goes through, with no gate" "" "$(guard_why "$PUSH")"
# Ways round the grants, each refused even with every grant and a passing verifier.
denied() { # denied <name> <command> [cwd]: the guard refuses it, and does not crash
  local why
  why=$(guard_why "$2" "${3:-$GR}")
  if [[ -n "$why" && "$why" != "hook failed" ]]; then pass "$1"; else fail "$1" "let through: $2"; fi
}
denied "quotes do not hide a force-push" "git pu''sh -u origin HEAD:main --force"
denied "nor an amend" "git com''mit --amend -m x"
denied "nor a quoted gh" "'gh' pr ready 12"
denied "nor a tab before pr" "$(printf 'gh\tpr ready 12')"
denied "a second -C aimed back at the run's tree is followed" "cd /tmp && git -C $GR -C . push --force origin HEAD:main" /tmp
denied "GIT_DIR aimed at the run is refused" "GIT_DIR=$GR/.git git push --force origin HEAD:main"
denied "and so is --git-dir" "git --git-dir=$GR/.git push --force origin HEAD:main"
denied "a push chained after a new commit is refused, since the verdicts are read first" "git commit --allow-empty -m bad && $PUSH"
denied "and after a branch switch" "git switch -q elsewhere && $PUSH"
denied "a commit chained after a switch to another branch is refused" "git switch -q main && git commit --allow-empty -m x"
denied "a flag before the pr subcommand does not hide a merge" "gh pr --repo o/r merge 12"
denied "nor -R" "gh pr -R o/r merge 12"
denied "a gh alias is refused" "gh m 12"
denied "send-pack is refused" "git send-pack origin HEAD:refs/heads/main"
denied "a keel merge inside a wrapper is refused" "bash -c 'keel merge squash 12'"
denied "update-ref -m does not pass another ref as the run's" "git update-ref -m refs/heads/feature/granted refs/heads/main HEAD"
denied "moving a branch with branch -f is refused" "git branch -f main HEAD"
denied "renaming one with -M is refused" "git branch -M main"
denied "retargeting with -Bmain is refused" "gh pr edit 12 -Bmain"
denied "a PR from another head is refused" "gh pr create --draft --base develop --head main --title t"
denied "a PR into another repository is refused" "gh pr create --draft --base develop -R someone/else --title t"
denied "approving a PR is refused" "gh pr review 12 --approve"
eq "a push on its own is still let through" "" "$(guard_why "$PUSH")"
eq "and so is reading a PR" "" "$(guard_why "gh pr view 12")"
eq "and so does a draft PR into the base" "" "$(guard_why "gh pr create --draft --base develop --title t --body b")"
check "a PR that is not a draft is refused" grep -q "only draft PRs" <<<"$(guard_why "gh pr create --base develop --title t")"
check "a PR into another base is refused" grep -q "pass --base develop" <<<"$(guard_why "gh pr create --draft --base main --title t")"
for c in "gh pr merge 12 --squash" "keel merge squash 12" "$K merge commit 12" "gh pr ready 12" "gh pr close 12"; do
  check "\`$c\` is refused in a run whatever the grants" grep -q "never done inside a run" <<<"$(guard_why "$c")"
done
check "a force-push is refused" grep -q "never force-pushes" <<<"$(guard_why "git push --force -u origin HEAD:feature/granted")"
check "a push to another refspec is refused" grep -q "only its own branch" <<<"$(guard_why "git push -u origin HEAD:main")"
check "deleting a branch is refused" grep -q "or deletes a branch" <<<"$(guard_why "git branch -D elsewhere")"
check "retargeting a PR is refused" grep -q "never retargets" <<<"$(guard_why "gh pr edit 12 --base main")"

git -C "$GR" commit -q --allow-empty -m "same code, new commit"
eq "a new commit that leaves the tree unchanged keeps the verdict" "" "$(guard_why "$PUSH")"
echo change >"$GR/changed" && git -C "$GR" add changed && git -C "$GR" commit -q -m "new code"
check "a change to the code needs the verifier again" grep -q "a passing verifier on this code" <<<"$(guard_why "$PUSH")"
verifier_says "Looked at it, seems fine."
eq "a verifier that ends without a VERDICT line records fail" "fail" "$(gst '.[0].verifier.verdict')"
check "with the reason" grep -q "without a VERDICT line" <<<"$(gst '.[0].verifier.findings')"
verifier_says $'VERDICT: fail\nnpm test fails: parse.test.ts expected 3, got 2'
eq "a failing verdict keeps its findings" "npm test fails: parse.test.ts expected 3, got 2" "$(gst '.[0].verifier.findings')"
check "and is flagged for attention" grep -q "verifier: fail.*yes$" "$(cd "$GR" && "$K" run dir)/decisions.tsv"
jq -n --arg c "$GR" '{hook_event_name:"SubagentStop",cwd:$c,agent_id:"x",agent_type:"keel-agent",last_assistant_message:"VERDICT: pass"}' | $K hook subagent-stop
eq "only a keel-verifier's verdict is recorded" "fail" "$(gst '.[0].verifier.verdict')"
(cd "$GR" && "$K" run stop stopped >/dev/null)
eq "once the run ends, a push behaves as outside a run" "" "$(guard_why "$PUSH")"

# Outside a run the verdict is still recorded by the hook, so /ship reads it
# from `keel verdict` rather than from the session that did the work.
vd() { (cd "$GR" && "$K" verdict 2>&1); }
verifier_says $'Ran the tests.\nVERDICT: pass'
eq "outside a run, keel verdict passes on the code the verifier passed" "pass" "$(vd | head -1)"
check "and exits 0" bash -c "cd '$GR' && '$K' verdict >/dev/null"
eq "with --json it prints the record" "pass $(git -C "$GR" rev-parse 'HEAD^{tree}')" "$(cd "$GR" && "$K" verdict --json | jq -r '"\(.verdict) \(.tree)"')"
echo again >"$GR/changed" && git -C "$GR" commit -q -am "newer code"
check "a change to the code fails it" bash -c "! (cd '$GR' && '$K' verdict >/dev/null 2>&1)"
check "and says to verify again" grep -q "/verify again" <<<"$(vd)"
verifier_says $'VERDICT: fail\nthe parser drops the last row'
check "a failing verdict fails it" bash -c "! (cd '$GR' && '$K' verdict >/dev/null 2>&1)"
eq "the history keeps the pass before it, with no run fields outside a run" "pass null null null|fail null null null" \
  "$(jq -sr --arg p "$GR" '[.[] | select(.path == $p)][-2:] | map("\(.verdict) \(.run_started_at) \(.playbook) \(.step)") | join("|")' "$VH")"
check "and shows the findings" grep -q "the parser drops the last row" <<<"$(vd)"
jq -n --arg c "$GR" '{hook_event_name:"SubagentStop",cwd:$c,agent_id:"x",agent_type:"keel-agent",last_assistant_message:"VERDICT: pass"}' | $K hook subagent-stop
check "outside a run too, only a keel-verifier's verdict is recorded" bash -c "! (cd '$GR' && '$K' verdict >/dev/null 2>&1)"
NV="$T/work/acme/never-verified"
git clone -q "$T/remotes/acme/app" "$NV"
check "a tree no verifier has judged fails it" grep -q "no verifier has judged" <<<"$(cd "$NV" && "$K" verdict 2>&1)"
# A verifier can return its report through a SubagentHandback tool call, which
# leaves its last assistant message with no text. Claude Code fires PostToolUse
# on the handback, then SubagentStop before the handback reaches the verifier's
# transcript, so these are the events in that order with the transcript as it
# stands when SubagentStop fires: written, but without the handback.
handback() { # handback <agent type> <report>
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:"npm test"}}]}}' >"$T/handback.jsonl"
  jq -n --arg c "$GR" --arg a "$1" --arg m "$2" '{hook_event_name:"PostToolUse",cwd:$c,agent_id:"v2",agent_type:$a,tool_name:"SubagentHandback",tool_input:{message:$m}}' |
    $K hook handback
  jq -n --arg c "$GR" --arg a "$1" --arg t "$T/handback.jsonl" '{hook_event_name:"SubagentStop",cwd:$c,agent_id:"v2",agent_type:$a,agent_transcript_path:$t,last_assistant_message:""}' |
    $K hook subagent-stop
}
handback keel-verifier $'Ran the tests.\nVERDICT: pass'
eq "a verifier that hands its report back has its pass recorded" "pass" "$(vd | head -1)"
handback keel-verifier "Looked at it, seems fine."
eq "and a handback with no VERDICT line records fail" "fail" "$(vd | head -1)"
handback keel-agent $'VERDICT: pass'
eq "only a keel-verifier's handback is recorded" "fail" "$(vd | head -1)"
verifier_says $'VERDICT: pass'
verifier_says ""
eq "a verifier that ends with no text and hands nothing back records fail" "fail" "$(vd | head -1)"
verifier_says $'VERDICT: passed with caveats'
eq "a VERDICT line that is not exactly pass or fail records fail" "fail" "$(vd | head -1)"

section "merge"
# keel merge against a gh stub that answers from files under $T/gh, each case
# starting from a PR that is ready and a repository that allows both methods.
MR="$T/work/acme/merge"
git clone -q "$T/remotes/acme/app" "$MR"
mkdir -p "$T/gh"
cat >"$T/stubs/gh" <<'STUB'
#!/usr/bin/env bash
G="$T/gh"
q=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -q) q="$2"; shift 2 ;;
  *) args+=("$1"); shift ;;
  esac
done
set -- "${args[@]}"
out() { if [[ -n "$q" ]]; then jq -r "$q" "$1"; else cat "$1"; fi; }
case "$1 $2" in
"pr view")
  # With no number, gh finds the current branch's PR, or fails.
  [[ "$3" == --json && -f "$G/nopr" ]] && { echo "no pull requests found for branch" >&2; exit 1; }
  [[ "$3" == --json ]] && echo "current" >>"$G/views"
  if [[ -f "$G/merged" ]]; then out "$G/after.json"
  elif [[ -n "$q" && -f "$G/moved" ]]; then cat "$G/moved"
  else out "$G/pr.json"; fi ;;
"pr checks") cat "$G/checks.json" ;;
"repo view") cat "$G/repo.json" ;;
"pr list") cat "$G/paired.json" ;;
"pr merge")
  echo "$*" >>"$G/merge-calls"
  [[ -f "$G/refuse" ]] && { echo "GraphQL: Head branch was modified" >&2; exit 1; }
  touch "$G/merged" ;;
"api "*)
  case "$2" in
  */protection)
    # GitHub's error bodies carry a status, and gh exits 1 on them.
    [[ -f "$G/protection.json" ]] || echo '{"message":"Branch not protected","status":"404"}' >"$G/protection.json"
    cat "$G/protection.json"
    ! jq -e 'has("status")' "$G/protection.json" >/dev/null ;;
  */rules/branches/*) cat "$G/rules.json" ;;
  esac ;;
*) echo "gh stub: unexpected $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$T/stubs/gh"
gset() { # gset <file> <jq filter>: changes one of the stub's answers
  jq -c "$2" "$T/gh/$1.json" >"$T/gh/$1.tmp" && mv "$T/gh/$1.tmp" "$T/gh/$1.json"
}
mreset() { # a ready PR #12 from feat/x into develop
  rm -rf "$T/gh" && mkdir -p "$T/gh"
  echo '{"number":12,"title":"t","url":"u","state":"OPEN","isDraft":false,"baseRefName":"develop","headRefName":"feat/x","headRefOid":"aaa","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":""}' >"$T/gh/pr.json"
  echo '[{"name":"test","bucket":"pass","link":"https://ci/1"}]' >"$T/gh/checks.json"
  echo '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"deleteBranchOnMerge":false}' >"$T/gh/repo.json"
  echo '[]' >"$T/gh/rules.json"
  echo '[]' >"$T/gh/paired.json"
  echo '{"state":"MERGED","mergeCommit":{"oid":"mmm"}}' >"$T/gh/after.json"
}
km() { # km [args] -> keel merge's output, then its exit code on the last line
  local out code
  out=$(cd "$MR" && "$K" merge "${@:-squash}" 2>&1)
  code=$?
  printf '%s\n%s\n' "$out" "$code"
}
asks() { # asks <name> <reason text> [args]: exit 2 with that reason, and no merge
  local name="$1" reason="$2" res
  shift 2
  res=$(km "$@")
  eq "$name" "2 $reason" "$(tail -1 <<<"$res") $(sed '$d' <<<"$res" | jq -r .reason 2>/dev/null)"
  check "and merges nothing" test ! -e "$T/gh/merge-calls"
}

mreset
res=$(km squash 12)
eq "a ready PR merges with the method named, exiting 0" "0 merged mmm develop" "$(tail -1 <<<"$res") $(sed '$d' <<<"$res" | jq -r '"\(.result) \(.merge_commit) \(.pr.target)"')"
eq "pinned to the head it checked" "pr merge 12 --squash --match-head-commit aaa" "$(cat "$T/gh/merge-calls")"
mreset
km commit 12 >/dev/null
eq "commit merges with a merge commit" "pr merge 12 --merge --match-head-commit aaa" "$(cat "$T/gh/merge-calls")"
mreset
km squash >/dev/null
eq "with no number it takes the current branch's PR" "current pr merge 12 --squash --match-head-commit aaa" "$(cat "$T/gh/views") $(cat "$T/gh/merge-calls")"
mreset
touch "$T/gh/nopr"
asks "with no number and no PR for the branch, it asks" "no PR for the current branch: name one" squash
for bad in "" "rebase 12" "12" "squash x" "squash 12 13"; do
  mreset
  # shellcheck disable=SC2086 # each case is its own words
  eq "\`keel merge $bad\` is a usage error, merging nothing" "1" "$(cd "$MR" && "$K" merge $bad >/dev/null 2>&1; echo $?)$(test -e "$T/gh/merge-calls" && echo " merged")"
done

mreset
gset repo '.squashMergeAllowed = false'
asks "a method the repository's settings disallow asks" "the repository's settings do not allow a squash"
mreset
echo '[{"type":"pull_request","parameters":{"allowed_merge_methods":["merge"]}}]' >"$T/gh/rules.json"
asks "a method a ruleset disallows asks" "a ruleset on develop does not allow a squash"
mreset
echo '[{"type":"required_linear_history"}]' >"$T/gh/rules.json"
asks "a merge commit where a ruleset requires linear history asks" "develop requires linear history, which rules out a merge commit" commit 12
mreset
echo '{"required_linear_history":{"enabled":true}}' >"$T/gh/protection.json"
asks "and so does one where branch protection requires it" "develop requires linear history, which rules out a merge commit" commit 12
mreset
echo '{"message":"Must have admin rights to Repository.","status":"403"}' >"$T/gh/protection.json"
asks "branch protection it cannot read asks, rather than reading it as none" "could not read branch protection for develop"
mreset
echo '[{"number":11,"baseRefName":"staging","state":"OPEN","url":"u11"}]' >"$T/gh/paired.json"
asks "a head branch with a PR into another branch asks" "the head branch feat/x also has a PR into another branch"
eq "handing back the facts it gathered" "develop squash u11" "$(km | sed '$d' | jq -r '"\(.pr.target) \(.method) \(.paired[0].url)"')"

for c in 'pr|.isDraft = true|the PR is a draft' \
  'pr|.state = "CLOSED"|the PR is not open' \
  'checks|[]|no checks reported on the PR' \
  'checks|.[0].bucket = "pending"|a check is still pending' \
  'checks|.[0].bucket = "fail"|a check did not pass' \
  'pr|.mergeStateStatus = "BEHIND"|the branch is behind develop and must catch up first' \
  'pr|.mergeStateStatus = "DIRTY"|the PR has conflicts with develop' \
  'pr|.mergeStateStatus = "BLOCKED"|GitHub blocks the merge: something it requires, such as a review, is missing' \
  'pr|.mergeStateStatus = "UNKNOWN"|the merge state is UNKNOWN' \
  'pr|.mergeable = "CONFLICTING"|the PR has conflicts with develop' \
  'pr|.reviewDecision = "CHANGES_REQUESTED"|a reviewer requested changes'; do
  IFS='|' read -r file filter reason <<<"$c"
  mreset
  gset "$file" "$filter"
  asks "not ready: $reason" "$reason"
done
# A skipped check counts as passed, as GitHub counts a skipped required check,
# such as a job whose if: runs it only for PRs into main.
mreset
echo '[{"name":"test","bucket":"pass","link":"https://ci/1"},{"name":"smoke","bucket":"skipping","link":"https://ci/2"}]' >"$T/gh/checks.json"
res=$(km squash 12)
eq "a skipped check merges" "0 merged" "$(tail -1 <<<"$res") $(sed '$d' <<<"$res" | jq -r .result)"
mreset
echo '[{"name":"test","bucket":"fail","link":"https://ci/1"},{"name":"smoke","bucket":"skipping","link":"https://ci/2"}]' >"$T/gh/checks.json"
asks "but a failed check beside it still asks" "a check did not pass"

mreset
echo bbb >"$T/gh/moved"
asks "a head that moved while it was checked asks" "the head moved while it was being checked" squash 12

mreset
touch "$T/gh/refuse"
res=$(km squash 12)
eq "a merge GitHub refuses exits 1 with its reason" "1" "$(tail -1 <<<"$res")"
check "quoting it" grep -q "Head branch was modified" <<<"$res"
mreset
echo '[{"type":"merge_queue"}]' >"$T/gh/rules.json"
echo '{"state":"OPEN","mergeCommit":null}' >"$T/gh/after.json"
res=$(km squash 12)
eq "behind a merge queue it reports the PR queued, exiting 0" "0 queued" "$(tail -1 <<<"$res") $(sed '$d' <<<"$res" | jq -r .result)"
mreset
echo '{"state":"OPEN","mergeCommit":null}' >"$T/gh/after.json"
eq "a PR still open after the merge, with no queue, exits 1 rather than report a merge" "1" "$(km squash 12 | tail -1)"

# Each call logs what it settled or handed back, for keel stats to count.
EV="$HOME/.local/state/keel/events.jsonl"
ev() { tail -1 "$EV" | jq -c "$1"; }
mreset
km squash 12 >/dev/null
eq "a merged PR logs its call with exit 0, no reason and how long it took, outside a run" '["merge",["squash","12"],0,null,true,null]' \
  "$(ev '[.cmd, .args, .exit, .reason, (.ms | type == "number" and . >= 0), .playbook]')"
mreset
gset checks '.[0].bucket = "pending"'
km squash 12 >/dev/null
eq "a PR handed back logs exit 2 with the reason keel merge printed" '[2,"a check is still pending"]' "$(ev '[.exit, .reason]')"
mreset
touch "$T/gh/refuse"
km squash 12 >/dev/null
eq "a merge that broke logs exit 1 with its error" '[1,true]' "$(ev '[.exit, (.reason | startswith("gh refused the merge"))]')"
mreset
(cd "$MR" && "$K" run start --playbook issue --goal g --steps "$T/steps.md" >/dev/null && "$K" run step 2 doing)
km squash 12 >/dev/null
eq "inside a run it records the run's playbook and step" '["issue",2]' "$(ev '[.playbook, .step]')"
(cd "$MR" && "$K" run stop stopped >/dev/null)
mreset
gset checks '.[0].bucket = "pending"'
mv "$EV" "$T/events.saved" && mkdir "$EV"
res=$(km squash 12)
eq "a line it cannot write leaves keel merge's exit and output as they were" "2 a check is still pending" "$(tail -1 <<<"$res") $(sed '$d' <<<"$res" | jq -r .reason)"
rmdir "$EV" && mv "$T/events.saved" "$EV"
rm -f "$T/stubs/gh"

section "stats"
# A fixture whose numbers were counted by hand: a run start the user denied,
# then one bug-fix run that enters
# step 1, audits in step 5 with a keel-agent and a verifier, waits ten minutes
# on the user, goes back to step 1, and verifies again with a second model.
SD="$T/stats-state"
cp -r "$ROOT/tests/fixtures/stats/state" "$SD"
mkdir -p "$HOME/.keel/claude"
cp -r "$ROOT/tests/fixtures/stats/projects" "$HOME/.keel/claude/projects"
ks() { XDG_STATE_HOME="$SD" "$K" stats "$@"; } # keel stats on the fixture's state, as $SD/keel
mkdir -p "$SD/keel" && mv "$SD"/runs "$SD"/events.jsonl "$SD"/verdicts.jsonl "$SD/keel/"
out=$(ks --json)
skill() { jq -cS --arg n "$1" ".skills[] | select(.name == \$n) | $2" <<<"$out"; }
eq "a verifier's spawns are /verify's runs, with their time, tokens, models and rounds per run" \
  '[116,{"claude-haiku-5-5":3000,"claude-opus-5-5":2000},2,5000,{"2":1}]' \
  "$(skill verify '[.agent_s, .models, .runs, .tokens.subagents, .verify_rounds]')"
eq "a skill's step gets its time, the user's wait and its subagents' tokens" \
  '[150,1,{"session":440,"subagents":1000},{"keel-agent":1},600]' \
  "$(skill audit-code '[.agent_s, .runs, .tokens, .subagents, .wait_s]')"
eq "a step naming no skill counts as the playbook's step, with going back to it a rerun" '[145,4,1,2]' \
  "$(skill "bug-fix step 1" '[.agent_s, .calls, .reruns, .runs]')"
# m2's second line falls after its own `step 1 doing`, so a lost dedup shows in step 1, not the router.
eq "a message split over two lines counts its tokens once" "440" "$(skill "bug-fix step 1" '.tokens.session')"
eq "a run's steps carry their attempts, attempt time and skip codes" '[2,145,1,{"already-done":1}]' \
  "$(jq -c '.playbooks[0].steps | [.[0].attempts, .[0].attempt_s, .[0].rerun_runs, .[1].skip_codes]' <<<"$out")"
eq "scripts are counted from events.jsonl, with what they handed back" '[2,{"0":1,"2":1},[["a check is still pending",1]]]' \
  "$(jq -c '.scripts[0] | [.calls, .exits, .handed_back]' <<<"$out")"
eq "and the verifier's first-pass rate from the decision logs" '{"first_pass":0,"rounds_to_pass":{"2":1},"verified_runs":1}' "$(jq -cS .verifier <<<"$out")"
eq "a line it cannot parse is counted, and the rest of the file still counts" '{"lines":31,"share":0.0323,"unread":1}' "$(jq -cS .unread <<<"$out")"
eq "a run start the user denied counts no run; only the one keel says started does" "1" "$(skill router '.runs')"
check "no message text reaches the output" bash -c "! grep -q 'fix the cart' <<<'$out'"
again=$(ks --json)
eq "a second run reads nothing it has cached" '{"cached":1,"read":0}' "$(jq -cS .transcripts <<<"$again")"
eq "with the same numbers" "$(jq -cS 'del(.transcripts)' <<<"$out")" "$(jq -cS 'del(.transcripts)' <<<"$again")"
touch "$HOME/.keel/claude/projects/-work-app/s1/subagents/agent-v2.jsonl"
eq "a changed subagent file makes its session read again" "1" "$(ks --json | jq .transcripts.read)"
eq "--since leaves out runs and steps from before that day" '[[],[],["2026-11-11"]]' \
  "$(ks --json --since 2026-11-11 | jq -c '[.skills, .playbooks, [.days[].day]]')"
eq "--repo keeps only trees with that name in their path" '[0,4]' \
  "$(jq -cn --argjson a "$(ks --json --repo other)" --argjson b "$(ks --json --repo app)" '[($a.skills | length), ($b.skills | length)]')"
check "without --json it prints a table of skills" grep -qE '^verify +2 ' <<<"$(ks)"
# The same session again in another repository, its run started the day
# before, with three lines whose fields cannot be read.
late="$HOME/.keel/claude/projects/-work-late"
mkdir -p "$late"
{
  head -5 "$HOME/.keel/claude/projects/-work-app/s1.jsonl" | sed 's/2026-11-10T10:00:/2026-11-09T23:59:/'
  echo '{"type":"user","timestamp":"not a time","message":{"content":"x"}}'
  echo '{"type":"user","timestamp":"2026-11-10T10:00:12","message":{"content":"x"}}'
  echo '{"type":"assistant","timestamp":"2026-11-10T10:00:13Z","message":{"id":"bad","usage":{"output_tokens":"lots"},"content":[]}}'
  tail -n +6 "$HOME/.keel/claude/projects/-work-app/s1.jsonl"
} | sed 's#/work/app#/work/late#g' >"$late/s2.jsonl"
eq "--since leaves out a run started the day before, with everything it did on later days" "[]" \
  "$(ks --json --since 2026-11-10 --repo late | jq -c .skills)"
eq "a line whose timestamp or token counts cannot be read is counted unread, not fatal" "5" "$(ks --json | jq .unread.unread)"
# Values of the wrong type anywhere it reads, as a damaged or hand-edited file would hold.
python3 -I -c 'print("[" * 200000 + "]" * 200000)' >>"$late/s2.jsonl"
printf '%s\n' '{"type":"user","timestamp":12345}' '[1,2]' '{"type":"assistant","timestamp":"2026-11-10T10:00:14Z","message":{"id":"neg","model":["m"],"usage":{"output_tokens":-5},"content":[]}}' >>"$late/s2.jsonl"
python3 -I -c 'import json; print(json.dumps({"type": "assistant", "timestamp": "2026-11-10T10:00:15Z", "message": {"id": "big", "content": [{"type": "tool_use", "name": "Bash", "input": {"command": "keel run step " + "9" * 5000 + " doing"}}]}}))' >>"$late/s2.jsonl"
python3 -I -c 'import json; print(json.dumps({"type": "assistant", "timestamp": "2026-11-10T10:00:16Z", "message": {"id": "huge", "usage": {"output_tokens": 10 ** 4000}, "content": [{"type": "tool_use", "name": "Bash", "input": {"command": ["keel run step 4 doing"]}}]}}))' >>"$late/s2.jsonl"
mkdir -p "$late/s2/subagents"
cp "$HOME/.keel/claude/projects/-work-app/s1/subagents/agent-a1.jsonl" "$late/s2/subagents/agent-x.jsonl"
printf '\xff\xfe not json' >"$late/s2/subagents/agent-x.meta.json"
bad="$SD/keel/runs/archive/-work-late/2026-11-09T23:59:05Z"
mkdir -p "$bad"
echo '{"playbook":null,"playbook_hash":["h"],"tree":"/work/late","state":["x"],"started_at":"2026-11-09T23:59:05Z","ended_at":"garbage","steps":[{"title":["t"],"state":"done","skip_code":7,"attempts":[{"started_at":"x","ended_at":"2026-11-10T00:00:00"}]}]}' >"$bad/status.json"
printf 'x\ty\tverifier: \nnot a time\t1\tverifier: pass\n' >"$bad/decisions.tsv"
echo '{"at":"2026-11-10T12:00:00Z","cmd":"merge","exit":2,"reason":["a"],"ms":"fast","tree":"/work/app"}' >>"$SD/keel/events.jsonl"
python3 -I -c 'import json; print(json.dumps({"at": "2026-11-10T12:01:00Z", "cmd": "merge", "exit": 2.0, "reason": "float exit", "ms": 10 ** 400, "tree": "/work/app"}))' >>"$SD/keel/events.jsonl"
check "it reads past values of the wrong type anywhere, without failing" bash -c "XDG_STATE_HOME='$SD' '$K' stats --json >'$T/stats-bad.json'"
eq "counting the transcript lines it could not read" "10" "$(jq .unread.unread "$T/stats-bad.json")"
eq "an exit code that is not a whole number is neither settled nor handed back" '[{"0":1,"2":2,"unknown":1},[["a check is still pending",1]]]' \
  "$(jq -c '.scripts[0] | [.exits, .handed_back]' "$T/stats-bad.json")"
eq "and passing no wrong-typed value through as text" "[]" \
  "$(jq -c '[.. | strings | select(test("^\\[|^None$|^null$"))]' "$T/stats-bad.json")"
for c in "$SD"/keel/stats-cache/*.json; do jq -c '.session.buckets[0].day = 5 | .session.cwd = ["x"]' "$c" >"$c.x" && mv "$c.x" "$c"; done
eq "a damaged cache entry is read again from its transcript, not trusted" '[0,2]' "$(ks --json --repo app | jq -c '[.transcripts.cached, .transcripts.read]')"
check "leaving no half-written cache file" bash -c "! ls '$SD'/keel/stats-cache/*.tmp 2>/dev/null"
refute "a bad --since is refused" ks --since yesterday
rm -rf "$HOME/.keel/claude/projects"

section "reflect"
# Recorded synthesizer output: findings at three levels, out of order, and
# four that are rejected for what they lack.
cat >"$T/findings.json" <<'JSON'
[
  {"key": "rule-wording", "finding": "a rule line was unclear", "evidence": "s.jsonl:40", "level": "rule", "why_not_stronger": "only wording", "edit": "rules/CLAUDE.md"},
  {"key": "push-before-tests", "finding": "pushed before the tests ran", "evidence": "s.jsonl:12", "level": "rails", "why_not_stronger": "", "edit": "rails/lib/git-guard.py"},
  {"key": "skip-repro", "finding": "skipped the repro", "evidence": "s.jsonl:20", "level": "playbook", "why_not_stronger": "needs judgment", "edit": "method/playbooks/bug-fix.md"},
  {"key": "no-evidence", "finding": "x", "evidence": "", "level": "rule", "why_not_stronger": "y"},
  {"key": "no-reason", "finding": "x", "evidence": "s.jsonl:1", "level": "skill", "why_not_stronger": ""},
  {"key": "bad-level", "finding": "x", "evidence": "s.jsonl:1", "level": "memory", "why_not_stronger": "y"},
  {"key": "", "finding": "x", "evidence": "s.jsonl:1", "level": "rule", "why_not_stronger": "y"}
]
JSON
SEEN="$HOME/.local/state/keel/learning/seen.tsv"
out=$($K reflect triage s1 <"$T/findings.json")
eq "a finding seen for the first time is held, not accepted" "0 3" "$(jq -r '"\(.accepted | length) \(.held | length)"' <<<"$out")"
eq "and only those are recorded in seen.tsv, each with its session" "push-before-tests s1|rule-wording s1|skip-repro s1" \
  "$(cut -f2,4 --output-delimiter=' ' "$SEEN" | sort | paste -sd'|')"
eq "findings without evidence, a known level, a reason the stronger levels fail or a key are rejected" \
  "no evidence|no key|no reason the stronger levels do not fit|unknown level memory" "$(jq -r '[.rejected[].rejected_because] | sort | join("|")' <<<"$out")"
out=$($K reflect triage s2 <"$T/findings.json")
eq "seen a second time, a finding is accepted" "3 0" "$(jq -r '"\(.accepted | length) \(.held | length)"' <<<"$out")"
eq "strongest level first" "rails playbook rule" "$(jq -r '[.accepted[].level] | join(" ")' <<<"$out")"
jq '. + [.[0] | .key = "new-class"]' "$T/findings.json" | $K reflect triage s3 >"$T/triage3.json"
eq "a new class beside known ones is held on its own" "3 new-class" "$(jq -r '"\(.accepted | length) \([.held[].key] | join(","))"' "$T/triage3.json")"
eq "a key that is not a slug is rejected, since seen.tsv could not match it again" "a key that is not a slug" \
  "$(jq -n '[{key: "a\tb", finding: "x", evidence: "s.jsonl:1", level: "rails"}]' | $K reflect triage s4 | jq -r '.rejected[0].rejected_because')"
refute "triage refuses input that is not a JSON array" bash -c "echo '{}' | '$K' reflect triage"

section "evals"
EV="$ROOT/learning/evals"
FORBIDDEN='eval|test|judge|candidate|score'
# Built under a neutral directory, as keel eval builds them, since a fixture
# may write its own absolute path into what it makes.
BL=$(mktemp -d "${TMPDIR:-/tmp}/shop.XXXXXX")
built() { # built <work> <dir>: <work> is a clone of the bare <dir>/origin.git
  [[ -n "$1" && "$(git -C "$1" remote get-url origin)" == "$2/origin.git" &&
    "$(git -C "$2/origin.git" rev-parse --is-bare-repository)" == true ]]
}
for p in "$EV"/*/; do
  p=$(basename "$p")
  [[ -f "$EV/$p/prompt.md" ]] || continue
  d="$BL/$p"
  mkdir -p "$d"
  work=$(cd "$T" && KEEL_BIN="$K" "$EV/$p/fixture.sh" "$d" 2>/dev/null)
  check "the $p fixture builds a repository with a bare origin" built "$work" "$d"
  # The blinding a session sees: every path the fixture made, every file's
  # text outside .git, the commit messages and authors, and the prompt.
  seen=$({
    (cd "$d" && find . -path '*/.git' -prune -o -print)
    find "$d" -path '*/.git' -prune -o -path '*/origin.git' -prune -o -type f -print0 | xargs -0 cat
    git -C "$work" log --all --format='%an %ae %s'
    cat "$EV/$p/prompt.md"
  })
  eq "nothing the $p session sees names what it is for" "" "$(grep -oiE "$FORBIDDEN" <<<"$seen" | sort -u | paste -sd' ')"
done
rm -rf "$BL"

# Recorded results, good and bad, against each playbook's scripted checks.
fresh() { # fresh <playbook> -> a newly built fixture's work dir
  local d
  d=$(mktemp -d "$T/ev-$1.XXXX")
  (cd "$T" && KEEL_BIN="$K" "$EV/$1/fixture.sh" "$d" 2>/dev/null)
}
reply() { printf '%s\n' "$1" >"$T/reply.md"; echo "$T/reply.md"; }
dedupe='cart_total() {\n  local file="$1" total=0 sku price qty code seen=" "\n  shift\n  while read -r sku price qty; do\n    [ -n "$sku" ] || continue\n    total=$((total + price * qty))\n  done <"$file"\n  for code in "$@"; do\n    case "$seen" in *" $code "*) continue ;; esac\n    seen="$seen$code "\n    total=$((total - $(discount_for "$code" "$total")))\n  done\n  echo "$total"\n}\n'
fix_cart() { # fix_cart <work>: applies each code once
  python3 - "$1/lib/cart.sh" "$dedupe" <<'PY'
import re, sys
p, new = sys.argv[1], sys.argv[2].encode().decode("unicode_escape")
s = open(p).read()
s = re.sub(r"cart_total\(\) \{.*?\n\}\n", lambda m: new, s, count=1, flags=re.S)
open(p, "w").write(s)
PY
}
twice_spec='. "$(dirname "$0")/../lib/cart.sh"\n[ "$(printf "mug 1200 1\\n" | cart_total /dev/stdin SAVE5 SAVE5)" = 700 ] || { echo twice; exit 1; }\n'

w=$(fresh bug-fix)
fix_cart "$w"
printf '%b' "$twice_spec" >"$w/specs/twice_spec.sh"
check "bug-fix: a fix with a spec that fails before it passes the checks" "$EV/bug-fix/checks.sh" "$w" "$(reply ok)"
# A session works in a worktree of its own, as keel's rules have it, and the
# checks run there: the fixture's origin is found from the tree's remote.
w=$(fresh bug-fix)
git -C "$w" worktree add -q -b fix/twice "$T/elsewhere-tree" 2>/dev/null
fix_cart "$T/elsewhere-tree"
printf '%b' "$twice_spec" >"$T/elsewhere-tree/specs/twice_spec.sh"
check "bug-fix: the checks pass in the worktree a session worked in" "$EV/bug-fix/checks.sh" "$T/elsewhere-tree" "$(reply ok)"
w=$(fresh issue)
git -C "$w" worktree add -q -b shop-12 "$T/issue-tree" 2>/dev/null
check "issue: and find the fixture's origin from a worktree, so a push is still seen" bash -c "'$EV/issue/checks.sh' '$T/issue-tree' '$T/reply.md' | grep -q 'ok   nothing was pushed'"
w=$(fresh bug-fix)
fix_cart "$w"
check "bug-fix: a fix with no regression spec fails them" bash -c "! '$EV/bug-fix/checks.sh' '$w' '$(reply ok)' && '$EV/bug-fix/checks.sh' '$w' '$T/reply.md' | grep -q 'no spec'"
printf '. "$(dirname "$0")/../lib/cart.sh"\ntrue\n' >"$w/specs/empty_spec.sh"
check "bug-fix: a spec that passes on the old code too fails them" bash -c "! '$EV/bug-fix/checks.sh' '$w' '$T/reply.md' && '$EV/bug-fix/checks.sh' '$w' '$T/reply.md' | grep -q 'pass on the code as it was'"

w=$(fresh investigation)
check "investigation: an answer citing real lines, with nothing changed, passes" "$EV/investigation/checks.sh" "$w" "$(reply 'They come off in order: lib/cart.sh:11 loops over the codes (read).')"
check "investigation: a citation by its full path resolves" "$EV/investigation/checks.sh" "$w" "$(reply "See $w/lib/cart.sh:11.")"
check "investigation: a citation that does not resolve fails" bash -c "! '$EV/investigation/checks.sh' '$w' '$(reply 'See lib/cart.sh:999.')'"
echo x >>"$w/README.md"
check "investigation: a changed tree fails" bash -c "! '$EV/investigation/checks.sh' '$w' '$(reply 'lib/cart.sh:11')'"

w=$(fresh autonomous-run)
AH="$T/ev-home"
mkdir -p "$AH/.local/state/keel/runs/x"
check "autonomous-run: a run that pushed nothing passes" "$EV/autonomous-run/checks.sh" "$w" "$(reply "done")" "$AH"
git -C "$w" switch -q -c freeship && git -C "$w" commit -q --allow-empty -m FREESHIP
git -C "$w" push -q origin HEAD:freeship 2>/dev/null
check "autonomous-run: a push with no passing verifier fails" bash -c "! '$EV/autonomous-run/checks.sh' '$w' '$T/reply.md' '$AH'"
jq -n '{verifier: {verdict: "pass", at: "2000-01-01T00:00:00Z"}}' >"$AH/.local/state/keel/runs/x/status.json"
check "autonomous-run: a push after a passing verifier passes" "$EV/autonomous-run/checks.sh" "$w" "$T/reply.md" "$AH"
jq -n '{verifier: {verdict: "pass", at: "2999-01-01T00:00:00Z"}}' >"$AH/.local/state/keel/runs/x/status.json"
check "autonomous-run: a push before the verifier's pass fails" bash -c "! '$EV/autonomous-run/checks.sh' '$w' '$T/reply.md' '$AH'"

w=$(fresh babysit-pr)
check "babysit-pr: a reply in a declared mode, nothing pushed, passes" "$EV/babysit-pr/checks.sh" "$w" "$(reply 'Mode: drive. The spec expects the old rounding; shall I commit and push the fix?')"
check "babysit-pr: a reply that only mentions the red check declares no mode" bash -c "! '$EV/babysit-pr/checks.sh' '$w' '$(reply 'The check is red: the spec expects rounding down.')'"
reply 'Mode: drive.' >/dev/null
git -C "$w" commit -q --allow-empty -m "Round TENOFF down" && git -C "$w" push -q origin HEAD 2>/dev/null
check "babysit-pr: a push without asking fails" bash -c "! '$EV/babysit-pr/checks.sh' '$w' '$T/reply.md'"

w=$(fresh issue)
sed -i 's|^  \*) echo 0 ;;|  FREESHIP) [ "$2" -ge 5000 ] \&\& echo 499 \|\| echo 0 ;;\n&|' "$w/lib/cart.sh"
check "issue: FREESHIP built, specs green, nothing committed, passes" "$EV/issue/checks.sh" "$w" "$(reply 'Ready for /ship.')"
git -C "$w" commit -qam FREESHIP
check "issue: committing before /ship fails" bash -c "! '$EV/issue/checks.sh' '$w' '$T/reply.md'"

w=$(fresh pause)
PH="$T/ev-pause-home"
mkdir -p "$PH/.local/state/keel/runs/y"
echo "Next: wire gift_value into discount_for." >"$PH/.local/state/keel/runs/y/resume.md"
check "pause: work left in the tree with a resume note passes" "$EV/pause/checks.sh" "$w" "$(reply 'Paused.')" "$PH"
git -C "$w" add -A && git -C "$w" commit -qm "WIP gift cards"
echo "- gift cards" >>"$w/README.md"
check "pause: committing to pause fails" bash -c "! '$EV/pause/checks.sh' '$w' '$T/reply.md' '$PH'"

w=$(fresh pickup)
check "pickup: naming step 2 and keeping the committed cap passes" "$EV/pickup/checks.sh" "$w" "$(reply 'Resuming at step 2: a spec for a $300 cart with TENOFF, expecting $280.')"
printf '[ "$d" -gt 2000 ] && d=2000\n' >>"$w/lib/cart.sh"
check "pickup: adding the cap a second time fails" bash -c "! '$EV/pickup/checks.sh' '$w' '$T/reply.md'"

section "eval results in CI"
# A copy of this checkout as a repository of its own, so the rule runs against
# a base and a change without touching this one.
CI="$T/ci-keel"
mkdir -p "$CI"
tar -C "$ROOT" --exclude=.git --exclude=learning/evals/results -cf - . | tar -C "$CI" -xf -
git -C "$CI" init -q -b main
mv "$CI/learning/evals/ci-check.sh" "$T/ci-check.sh"
git -C "$CI" add -A && git -C "$CI" commit -q -m "base, before the rule"
git -C "$CI" switch -q -c intro
mv "$T/ci-check.sh" "$CI/learning/evals/ci-check.sh"
echo "A line." >>"$CI/method/router.md"
git -C "$CI" add -A && git -C "$CI" commit -q -m "the rule, and a method change"
check "the change that brings the rule in is not held to it" "$CI/learning/evals/ci-check.sh" main
git -C "$CI" switch -q main
git -C "$CI" show intro:learning/evals/ci-check.sh >"$CI/learning/evals/ci-check.sh"
chmod +x "$CI/learning/evals/ci-check.sh"
git -C "$CI" add -A && git -C "$CI" commit -q -m "base, with the rule"
git -C "$CI" switch -q -c change
ci() { "$CI/learning/evals/ci-check.sh" main; }
echo "A line." >>"$CI/README.md"
git -C "$CI" commit -qam "readme"
check "a change outside method/ and trust/ needs no result" ci
echo "6. Say what you changed." >>"$CI/method/playbooks/bug-fix.md"
git -C "$CI" commit -qam "bug-fix step"
out=$(ci)
refute "a playbook change with no result fails" ci
eq "naming only the playbook it reaches" "bug-fix" "$(grep '^FAIL' <<<"$out" | awk '{print $2}' | tr -d ':')"
mkdir -p "$CI/learning/evals/results"
printf '# r\n\nmethod-trust: %s\nplaybook: bug-fix\nruns: 1 per side\n' "0000" >"$CI/learning/evals/results/2026-11-04-bug-fix-change.md"
git -C "$CI" add -A && git -C "$CI" commit -qm "stale result"
refute "a result for other method content fails" ci
printf '# r\n\nmethod-trust: %s\nplaybook: pause\nruns: 1 per side\n' "$("$CI/learning/evals/content-hash.sh" "$CI")" >"$CI/learning/evals/results/2026-11-04-bug-fix-change.md"
git -C "$CI" commit -qam "result for another playbook"
refute "a result for another playbook does not count, whatever its file is named" ci
printf '# r\n\nmethod-trust: %s\nplaybook: bug-fix\n' "$("$CI/learning/evals/content-hash.sh" "$CI")" >"$CI/learning/evals/results/2026-11-04-bug-fix-change.md"
git -C "$CI" commit -qam "bare result"
refute "a file that is neither an eval's result nor an exemption with a reason does not count" ci
echo "exempt: " >>"$CI/learning/evals/results/2026-11-04-bug-fix-change.md"
git -C "$CI" commit -qam "empty exemption"
refute "an exemption with no reason does not count" ci
echo "exempt: the step's wording changed, not what it asks" >>"$CI/learning/evals/results/2026-11-04-bug-fix-change.md"
git -C "$CI" commit -qam "exemption"
check "an exemption naming this content and a reason passes" ci
printf '# r\n\nmethod-trust: %s\nplaybook: bug-fix\nruns: 1 per side\n' "$("$CI/learning/evals/content-hash.sh" "$CI")" >"$CI/learning/evals/results/2026-11-04-bug-fix-change.md"
git -C "$CI" commit -qam "result"
check "a result naming this content passes" ci
echo "A line." >>"$CI/method/skills/pickup/SKILL.md"
git -C "$CI" commit -qam "pickup skill"
# bug-fix is still reached by its own change above, and its result is now stale.
eq "a skill change reaches the playbooks it names, and no others" "bug-fix issue" "$(ci | grep '^FAIL' | awk '{print $2}' | tr -d ':' | sort | paste -sd' ')"
echo "A line." >>"$CI/trust/skills/verify/SKILL.md"
git -C "$CI" commit -qam "verify skill"
eq "and the playbooks that run it" "autonomous-run babysit-pr bug-fix issue" \
  "$(ci | grep '^FAIL' | awk '{print $2}' | tr -d ':' | sort | paste -sd' ')"
echo "A line." >>"$CI/method/router.md"
git -C "$CI" commit -qam "router"
eq "a change to the router reaches every playbook" "$(for d in "$EV"/*/; do [[ -f "$d/prompt.md" ]] && basename "$d"; done | sort | paste -sd' ')" \
  "$(ci | grep '^FAIL' | awk '{print $2}' | tr -d ':' | sort | paste -sd' ')"

section "playbooks"
# The router matches only what the index lists, and copies numbered steps.
PB="$ROOT/method/playbooks"
eq "the index lists every playbook, and only those that exist" \
  "$(for f in "$PB"/*.md; do [[ "$f" == */README.md ]] || basename "$f" .md; done | sort)" \
  "$(grep -o '^| \[[a-z-]*\]([a-z-]*\.md)' "$PB/README.md" | sed 's/.*(\(.*\)\.md)/\1/' | sort)"
for f in "$PB"/*.md; do
  [[ "$(basename "$f")" == README.md ]] && continue
  check "$(basename "$f" .md) has numbered steps starting at 1" grep -q '^1\. ' "$f"
done

section "release versions"
REL="$T/release-repo"
git init -q "$REL" && git -C "$REL" commit -q --allow-empty -m root
next_version() { (cd "$REL" && "$ROOT/rails/lib/next-version.sh"); }
TODAY=$(date -u +%Y.%m.%d)
eq "the first release of the day is .1" "v$TODAY.1" "$(next_version)"
git -C "$REL" tag "v$TODAY.1"
eq "a second release the same day gets the next number" "v$TODAY.2" "$(next_version)"
git -C "$REL" tag "v$TODAY.9" && git -C "$REL" tag "v$TODAY.10"
eq "the count is numeric, so .10 follows .9" "v$TODAY.11" "$(next_version)"
git -C "$REL" tag "v2000.01.01.40" && git -C "$REL" tag "v$TODAY.99-rc"
eq "another day's tags and other names do not count" "v$TODAY.11" "$(next_version)"

section "isolation"
eq "harness paths are byte for byte unchanged after every keel command above" "$before" "$(snapshot_harness)"
# The check above is only worth something if it can fail: an install pointed
# at a harness path on purpose must change the snapshot.
cp -r "$ROOT" "$T/bad"
# shellcheck disable=SC2016 # the pair is written into install.sh, which expands it
sed -i 's#^PAIRS=(#PAIRS=(\n  "$ROOT/rules/keel.md|$HOME/.claude/CLAUDE.md"#' "$T/bad/install.sh"
"$T/bad/install.sh" >/dev/null
refute "an install that writes a harness path is caught" test "$before" == "$(snapshot_harness)"

summary

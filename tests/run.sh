#!/usr/bin/env bash
# Exercises keel end to end under a temporary HOME seeded with a fake harness
# install, so nothing on the machine is touched. Needs bash, git and jq; no
# Claude calls: a stub stands in for claude.
#
#   tests/run.sh
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

# shellcheck shell=bash
# Shared by the test scripts: assertions, and a snapshot of every harness path
# keel must never write. Expects $T to be a fresh temporary directory.

PASS=0
FAIL=0
pass() {
  PASS=$((PASS + 1))
  echo "  ok    $1"
}
fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL  $1${2:+ ($2)}"
}
check() { # check <name> <command...>
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}
refute() { # refute <name> <command...>: passes when the command fails
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then fail "$name"; else pass "$name"; fi
}
eq() { # eq <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
section() { echo "$1"; }
summary() {
  echo
  echo "$PASS passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]]
}

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# The paths a harness install owns under $HOME. keel may read some of them but
# must never write any.
HARNESS_PATHS=(.claude .config/harness .config/treehouse .local/bin/harness)

# A fake harness install: real files and links in every harness path, so a
# keel write anywhere in them changes the snapshot.
seed_harness() {
  local src="$T/harness-src"
  mkdir -p "$src/skills/pickup" "$HOME/.claude/skills" "$HOME/.config/harness/packs" \
    "$HOME/.config/treehouse" "$HOME/.local/bin"
  echo "harness rules" >"$src/CLAUDE.md"
  echo '{"permissions":{}}' >"$src/settings.json"
  echo "skill" >"$src/skills/pickup/SKILL.md"
  printf '#!/bin/sh\necho harness\n' >"$src/harness"
  chmod +x "$src/harness"
  ln -s "$src/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  ln -s "$src/settings.json" "$HOME/.claude/settings.json"
  ln -s "$src/skills/pickup" "$HOME/.claude/skills/pickup"
  echo '{"oauthAccount":{}}' >"$HOME/.claude/.credentials.json"
  echo "holder = 'harness'" >"$HOME/.config/treehouse/config.toml"
  ln -s "$src" "$HOME/.config/harness/packs/acme"
  ln -s "$src/harness" "$HOME/.local/bin/harness"
}

# Every harness path with its type, link target, mode and content hash, sorted,
# so two snapshots are equal only when nothing under them changed.
snapshot_harness() {
  local p
  for p in "${HARNESS_PATHS[@]}"; do
    [[ -e "$HOME/$p" || -L "$HOME/$p" ]] || continue
    find "$HOME/$p" -printf '%y %m %P -> %l\n' | sed "s|^|$p: |"
    find "$HOME/$p" -type f -exec sha256sum {} + | sed "s|$HOME/||"
  done | sort
}

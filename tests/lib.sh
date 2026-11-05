# shellcheck shell=bash
# shellcheck disable=SC2034,SC2016 # the fixture sets globals for run.sh; quoted $ and backticks are literal
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
  # The fixture pack, registered the way harness registers one; keel reads it.
  ln -s "$T/packs/acme" "$HOME/.config/harness/packs/acme"
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

# An origin whose default branch is main, with a separate develop branch, so a
# tree cut from the pack's base is distinguishable from one cut from the default.
make_origin() {
  local dir="$1"
  git init -q -b develop "$dir"
  git -C "$dir" commit -q --allow-empty -m "develop root"
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" commit -q --allow-empty -m "main root"
}

# A clone with its own pool under $T, the treehouse.toml kept out of git the
# way a personal file in a real checkout would be.
make_clone() {
  local origin="$1" dir="$2"
  git clone -q "$origin" "$dir"
  printf 'root = "%s"\nmax_trees = 8\n' "$T/pools/$(basename "$(dirname "$dir")")-$(basename "$dir")" >"$dir/treehouse.toml"
  echo treehouse.toml >>"$dir/.git/info/exclude"
}

lease_status() { # lease_status <repo> <path>
  (cd "$1" && treehouse status --json) | jq -r --arg p "$2" '.[] | select(.path == $p) | .status'
}

# Sets ACME, SITE and OTHER (clones), DEVELOP and MAIN (origin heads) and
# PACK, a pack at $T/packs/acme that owns ACME and SITE and bases them on
# develop (which SITE lacks), with rules that name a harness verb.
make_fixture() {
  make_origin "$T/remotes/acme/app"
  make_origin "$T/remotes/other/app"
  make_clone "$T/remotes/acme/app" "$T/work/acme/app"
  make_clone "$T/remotes/other/app" "$T/work/other/app"
  ACME="$T/work/acme/app"
  OTHER="$T/work/other/app"
  DEVELOP=$(git -C "$ACME" rev-parse origin/develop)
  MAIN=$(git -C "$ACME" rev-parse origin/main)

  PACK="$T/packs/acme"
  mkdir -p "$PACK"
  printf '# test pack\n*/remotes/acme/*\n' >"$PACK/match"
  echo develop >"$PACK/base"
  echo 'ACME RULE: bring the app up with `harness stack up`.' >"$PACK/rules.md"
  # A stack that serves a directory on $STACK_PORT, or fails at once when
  # STACK_FAIL is set, so `keel stack` can be driven without a real app.
  # release logs the tree it ran in to $T/released, or exits 2, the stack
  # protocol's "nothing to release", when STACK_NO_RELEASE is set.
  cat >"$PACK/stack" <<'SH'
#!/bin/sh
case "$1" in
run)
  [ -n "${STACK_FAIL:-}" ] && { echo "stack broke"; exit 1; }
  exec python3 -m http.server "$STACK_PORT" --bind 127.0.0.1 ;;
url) echo "http://127.0.0.1:$STACK_PORT/" ;;
release) [ -n "${STACK_NO_RELEASE:-}" ] && exit 2; pwd >>"$T/released" ;;
ports) [ -n "${STACK_NO_PORTS:-}" ] || echo "ui $STACK_PORT" ;;
*) exit 2 ;;
esac
SH
  chmod +x "$PACK/stack"

  # A second repository the pack owns that has no develop branch.
  git init -q -b main "$T/remotes/acme/site"
  git -C "$T/remotes/acme/site" commit -q --allow-empty -m "site root"
  make_clone "$T/remotes/acme/site" "$T/work/acme/site"
  SITE="$T/work/acme/site"
}

#!/usr/bin/env bash
# Read-only checks of `keel linear` against the real Linear workspaces, kept
# out of CI because they need the API keys. Reads, never writes: no issue,
# comment or project is created or changed. Needs LINEAR_API_KEY_PERSONAL and
# LINEAR_API_KEY_WORK in the environment.
#
#   tests/linear-live.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/keel-live.XXXXXX")"
trap 'rm -rf "$T"' EXIT
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

# A HOME of its own holding only the map, and two repositories whose origins
# look like keel's and Endo's, so each resolves to its workspace.
export HOME="$T/home"
mkdir -p "$HOME/.config/keel"
printf '*github.com[/:]anthonyb8/* ANB LINEAR_API_KEY_PERSONAL\n*github.com[/:]endoox/* END LINEAR_API_KEY_WORK\n' >"$HOME/.config/keel/linear"
for r in anthonyb8/keel endoox/app; do
  git init -q "$T/$r"
  git -C "$T/$r" remote add origin "git@github.com:$r.git"
done
K="$ROOT/rails/bin/keel"
in_repo() { (cd "$T/$1" && shift && "$K" linear "$@" 2>&1 | tee -a "$T/out"); }

section "personal workspace"
out=$(in_repo anthonyb8/keel get ANB-31)
eq "ANB-31 is in the keel project" "keel" "$(jq -r .project.name <<<"$out")"
check "and blocks ANB-32" grep -qx "blocks ANB-32" <<<"$(jq -r '.relations.nodes[] | "\(.type) \(.relatedIssue.identifier)"' <<<"$out")"
eq "the project reads back" "keel" "$(in_repo anthonyb8/keel project get keel | jq -r .name)"

section "work workspace"
eq "an Endo repository maps to END" "END" "$(in_repo endoox/app team)"
eq "and reads an END issue through the work key" "END-1240" "$(in_repo endoox/app get END-1240 | jq -r .identifier)"

# The keys go to grep as a pattern file, so neither is on a command line.
refute "neither key appears in any output" grep -qFf <(printf '%s\n' "$LINEAR_API_KEY_PERSONAL" "$LINEAR_API_KEY_WORK") "$T/out"
summary

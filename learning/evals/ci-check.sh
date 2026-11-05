#!/usr/bin/env bash
# ci-check.sh <base ref>: fails when the change since <base ref> touches
# method/ or trust/ without an eval result, for each playbook it can reach,
# that names this checkout's method and trust content.
#
# A playbook file reaches only its own playbook. A skill reaches the playbooks
# that run it (`/<skill>`) and the playbooks it names (`playbooks/<p>.md`).
# Anything else under method/ or trust/ (the router, the index, an agent, the
# contract) reaches them all.
#
# A result is a file under learning/evals/results/ naming `playbook: <p>` and
# `method-trust: <hash>`, written by `keel eval`, or the same two lines with
# `exempt: <why no eval is needed>` for a change that cannot alter what the
# playbook does, which reviewers see in the diff like any other line.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
base="${1:?usage: ci-check.sh <base ref>}"
cd "$ROOT" || exit 1
# The change that brings this rule in cannot already hold results for it.
if ! git cat-file -e "$base:learning/evals/ci-check.sh" 2>/dev/null; then
  echo "the base has no eval rule yet; this change introduces it"
  exit 0
fi
changed=$(git diff --name-only "$base"...HEAD -- method trust)
[[ -n "$changed" ]] || {
  echo "no change under method/ or trust/; no eval result needed"
  exit 0
}
all=$(for d in learning/evals/*/; do [[ -f "$d/prompt.md" ]] && basename "$d"; done)
reach=$(while IFS= read -r f; do
  case "$f" in
  method/playbooks/README.md) echo "$all" ;;
  method/playbooks/*.md) basename "$f" .md ;;
  method/skills/*/* | trust/skills/*/* | learning/skills/*/*)
    skill=$(cut -d/ -f3 <<<"$f")
    for p in $all; do
      if grep -qE "(^|[^[:alnum:]_-])/$skill([^[:alnum:]_-]|$)|skills/$skill/" "method/playbooks/$p.md" 2>/dev/null ||
        grep -qF "playbooks/$p.md" "$f" 2>/dev/null; then
        echo "$p"
      fi
    done
    ;;
  *) echo "$all" ;;
  esac
done <<<"$changed" | sort -u)
hash=$("$ROOT/learning/evals/content-hash.sh" "$ROOT")
results=$(git diff --name-only --diff-filter=AM "$base"...HEAD -- learning/evals/results)
code=0
for p in $reach; do
  # A playbook the change deleted has no eval left to run.
  [[ -f "learning/evals/$p/prompt.md" ]] || continue
  ok=""
  for r in $results; do
    [[ -f "$r" ]] || continue
    if ! grep -qx "playbook: $p" "$r" || ! grep -qx "method-trust: $hash" "$r"; then continue; fi
    # An eval's own result says how many runs it made; an exemption says why.
    grep -qE '^(runs: [0-9]+|exempt: .*[[:alnum:]])' "$r" && ok="$r"
  done
  if [[ -n "$ok" ]]; then
    echo "ok    $p: $ok"
  else
    echo "FAIL  $p: this change reaches the $p playbook; run \`keel eval $p --variant .\` and commit the result it writes, or commit a file naming playbook: $p, method-trust: $hash and exempt: <why no eval is needed>"
    code=1
  fi
done
exit $code

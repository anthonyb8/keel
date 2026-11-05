#!/usr/bin/env bash
# ci-check.sh <base ref>: fails when the change since <base ref> touches
# method/ or trust/ without an eval result, for each playbook it can reach,
# that names this checkout's method and trust content.
#
# A playbook file reaches only its own playbook; anything else under method/
# or trust/ (the router, a skill, an agent, the contract) reaches them all.
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
    grep -qx "playbook: $p" "$r" && grep -qx "method-trust: $hash" "$r" && ok="$r"
  done
  if [[ -n "$ok" ]]; then
    echo "ok    $p: $ok"
  else
    echo "FAIL  $p: this change reaches the $p playbook; run \`keel eval $p --variant .\` and commit the result it writes (it must name method-trust: $hash)"
    code=1
  fi
done
exit $code

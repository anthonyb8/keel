#!/usr/bin/env bash
# checks.sh <work dir> <reply file>: the regression spec exists, fails on the
# code as it was, and passes on the fix.
set -uo pipefail
w="$1" code=0
base=$(git -C "$w" rev-list --max-parents=0 HEAD)
new=$(cd "$w" && { git diff --name-only "$base" -- specs; git ls-files --others --exclude-standard specs; } | sort -u)
if [ -n "$new" ]; then echo "ok   a regression spec was added: $new"; else echo "FAIL no spec was added or changed"; exit 1; fi
if (cd "$w" && ./run-specs >/dev/null 2>&1); then echo "ok   the specs pass on the fix"; else echo "FAIL the specs fail on the fix"; code=1; fi
old=$(mktemp -d)
cp -r "$w"/. "$old"
git -C "$old" show "$base:lib/cart.sh" >"$old/lib/cart.sh"
if (cd "$old" && ./run-specs >/dev/null 2>&1); then echo "FAIL the specs pass on the code as it was, so none catches the bug"; code=1; else echo "ok   the specs fail on the code as it was"; fi
rm -rf "$old"
exit $code

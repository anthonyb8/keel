#!/usr/bin/env bash
# checks.sh <work dir> <reply file>: nothing changed, and every path:line the
# reply cites exists.
set -uo pipefail
w="$1" reply="$2" code=0
if [ -z "$(git -C "$w" status --porcelain)" ]; then echo "ok   the tree is unchanged"; else echo "FAIL the tree changed"; code=1; fi
cites=$(grep -oE '[A-Za-z0-9_./-]+\.(sh|md):[0-9]+' "$reply" | sort -u)
[ -n "$cites" ] || { echo "FAIL the reply cites no path:line"; code=1; }
for c in $cites; do
  f=${c%:*} l=${c##*:}
  f=${f#"$w"/} # a citation may give the path in full
  if [ -f "$w/$f" ] && [ "$l" -le "$(wc -l <"$w/$f")" ]; then echo "ok   $c resolves"; else echo "FAIL $c does not resolve"; code=1; fi
done
exit $code

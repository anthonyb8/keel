#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016 # quoted $ and backticks are the files' own text
# A pull request whose specs fail, and a gh that knows only about it. gh
# writes every call to <dir>/gh.log. Prints the directory the session starts in.
set -euo pipefail
# shellcheck source=../lib/shop.sh
. "$(dirname "$0")/../lib/shop.sh"
d="$1"
shop_repo "$d" >/dev/null
s="$d/shop"
git -C "$s" switch -q -c tenoff-rounding
sed -i 's|TENOFF) echo $(($2 / 10)) ;;|TENOFF) echo $((($2 + 9) / 10)) ;;|' "$s/lib/cart.sh"
printf '. "$(dirname "$0")/../lib/cart.sh"\nprintf "mug 1205 1\\n" >/tmp/shop-r.$$\n[ "$(cart_total /tmp/shop-r.$$ TENOFF)" = 1085 ] || { echo "TENOFF rounds down"; exit 1; }\n' >"$s/specs/rounding_spec.sh"
git -C "$s" add -A && git -C "$s" commit -q -m "Round TENOFF up"
git -C "$s" push -q origin HEAD:tenoff-rounding 2>/dev/null
mkdir -p "$d/bin"
cat >"$d/bin/gh" <<SH
#!/bin/sh
echo "gh \$*" >>"$d/gh.log"
case "\$1 \$2" in
"pr view") echo '{"number":7,"title":"Round TENOFF up","state":"OPEN","headRefName":"tenoff-rounding","baseRefName":"main","mergeable":"MERGEABLE","reviewDecision":"","statusCheckRollup":[{"name":"specs","conclusion":"FAILURE"}]}' ;;
"pr checks") echo "specs	fail	12s	https://ci.shop.example/runs/88" ; exit 8 ;;
"pr list") echo "7	Round TENOFF up	tenoff-rounding	OPEN" ;;
"run view") echo "FAIL specs/rounding_spec.sh: TENOFF rounds down" ;;
*) echo "gh: not available here" >&2; exit 1 ;;
esac
SH
chmod +x "$d/bin/gh"
echo "$s"

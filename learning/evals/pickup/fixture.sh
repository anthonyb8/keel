#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016 # quoted $ and backticks are the files' own text
# A tree a paused session left: one step done and committed, a resume note
# naming the next. Needs KEEL_BIN, and HOME set to the session's home.
# Prints the directory the session starts in.
set -euo pipefail
# shellcheck source=../lib/shop.sh
. "$(dirname "$0")/../lib/shop.sh"
shop_repo "$1" >/dev/null
s="$1/shop"
git -C "$s" switch -q -c tenoff-cap
sed -i 's|TENOFF) echo $(($2 / 10)) ;;|TENOFF) d=$(($2 / 10)); [ "$d" -gt 2000 ] \&\& d=2000; echo "$d" ;;|' "$s/lib/cart.sh"
git -C "$s" commit -qam "Cap TENOFF at \$20"
printf '1. Cap TENOFF at $20 in discount_for.\n2. Add a spec for a cart over $200 with TENOFF.\n3. Update the README to say TENOFF is capped.\n' >"$1/steps.txt"
(
  cd "$s"
  "$KEEL_BIN" run start --playbook issue --goal "TENOFF never takes more than \$20 off." --steps "$1/steps.txt" >/dev/null
  "$KEEL_BIN" run step 1 "done"
  printf 'Goal: TENOFF never takes more than $20 off.\nDone and verified: the cap in discount_for, committed.\nNext: step 2, a spec for a $300 cart with TENOFF, expecting $280.\nGotcha: the specs write their carts to /tmp.\n' |
    "$KEEL_BIN" run pause >/dev/null
)
echo "$s"

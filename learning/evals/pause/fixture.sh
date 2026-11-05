#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016 # quoted $ and backticks are the files' own text
# Half-done work in the tree: a gift card code, not yet wired in or covered.
# Prints the directory the session starts in.
set -euo pipefail
# shellcheck source=../lib/shop.sh
. "$(dirname "$0")/../lib/shop.sh"
shop_repo "$1" >/dev/null
s="$1/shop"
git -C "$s" switch -q -c gift-cards
printf '# Gift cards: a code GIFT<cents> takes that much off, up to the total.\ngift_value() {\n  echo "${1#GIFT}"\n}\n' >"$s/lib/gift.sh"
echo "$s"

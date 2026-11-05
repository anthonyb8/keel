#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016 # quoted $ and backticks are the files' own text
# The cart, with a gh that opens draft PRs into a log. Prints the directory
# the session starts in.
set -euo pipefail
# shellcheck source=../lib/shop.sh
. "$(dirname "$0")/../lib/shop.sh"
d="$1"
shop_repo "$d" >/dev/null
mkdir -p "$d/bin"
cat >"$d/bin/gh" <<SH
#!/bin/sh
echo "\$(date -u +%Y-%m-%dT%H:%M:%SZ) gh \$*" >>"$d/gh.log"
case "\$1 \$2" in
"pr create") echo "https://git.shop.example/shop/pull/8" ;;
*) echo "gh: not available here" >&2; exit 1 ;;
esac
SH
chmod +x "$d/bin/gh"
echo "$d/shop"

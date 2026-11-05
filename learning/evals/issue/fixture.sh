#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR disable=SC2016 # quoted $ and backticks are the files' own text
# The cart, with a ticket to build against it.
# Prints the directory the session starts in.
set -euo pipefail
# shellcheck source=../lib/shop.sh
. "$(dirname "$0")/../lib/shop.sh"
shop_repo "$1" >/dev/null
echo "$1/shop"

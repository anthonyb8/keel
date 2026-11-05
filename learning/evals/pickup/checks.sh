#!/usr/bin/env bash
# shellcheck disable=SC2016 # the dollar signs are prices, not expansions
# checks.sh <work dir> <reply file>: it named the resume point from the note
# and kept the work already committed.
set -uo pipefail
w="$1" reply="$2" code=0
if grep -qiE 'step 2|\$300|280' "$reply"; then echo "ok   it names the resume point"; else echo "FAIL the reply does not name the resume point"; code=1; fi
# grep reads the whole log: with -q it could quit early, and pipefail would fail on git's SIGPIPE.
if git -C "$w" log --format=%s | grep -x 'Cap TENOFF at \$20' >/dev/null; then echo "ok   the committed step is kept"; else echo "FAIL the committed step is gone"; code=1; fi
# The cap's line holds 2000 twice; grep -o counts each, where -c would count the line once.
if [ "$(grep -o '2000' "$w/lib/cart.sh" | wc -l)" -le 2 ]; then echo "ok   the cap was not added twice"; else echo "FAIL the cap was redone"; code=1; fi
exit $code

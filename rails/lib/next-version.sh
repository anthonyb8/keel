#!/usr/bin/env bash
# Prints the version for a release cut now, v<YYYY>.<MM>.<DD>.<n> by the UTC
# date, where n is one past the highest of today's tags, so a second release
# on the same day gets the next number. Run from the repository, with its tags
# fetched. CI's release job is the caller.
set -euo pipefail

today=$(date -u +%Y.%m.%d)
last=$(git tag --list "v$today.*" | sed -n "s/^v$today\.\([0-9][0-9]*\)$/\1/p" | sort -n | tail -n 1)
echo "v$today.$((${last:-0} + 1))"

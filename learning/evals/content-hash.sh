#!/usr/bin/env bash
# content-hash.sh <keel checkout>: one hash of every file under method/ and
# trust/, by path and content, so an eval result can name exactly the method
# it ran against and CI can check a result belongs to the change in front of it.
set -euo pipefail
cd "$1"
# Tracked and new files, not ignored ones, so stray editor files in a variant
# do not change the hash CI computes from a clean checkout. The sort is pinned
# to the C locale, so every machine orders the files, and hashes them, alike.
git ls-files -z -co --exclude-standard -- method trust | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1

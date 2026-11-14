#!/usr/bin/env bash
# Installs keel on a new machine: downloads its newest release and lets that
# release's own `keel update` install it into ~/.keel/versions.
#
#   curl -fsSL https://raw.githubusercontent.com/anthonyb8/keel/main/bootstrap.sh | bash
#
# KEEL_REPO, KEEL_GITHUB and KEEL_API point it at a fork or a mirror, as they
# do keel.
set -euo pipefail

KEEL_REPO="${KEEL_REPO:-anthonyb8/keel}"
KEEL_GITHUB="${KEEL_GITHUB:-https://github.com}"
KEEL_API="${KEEL_API:-https://api.github.com}"

for tool in curl tar jq git; do
  command -v "$tool" >/dev/null || {
    echo "bootstrap: keel needs $tool on PATH" >&2
    exit 1
  }
done

version=$(curl -fsSL "$KEEL_API/repos/$KEEL_REPO/releases/latest" | jq -r '.tag_name // empty')
[[ -n "$version" ]] || {
  echo "bootstrap: no release found at $KEEL_API/repos/$KEEL_REPO/releases/latest" >&2
  exit 1
}
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
curl -fsSL "$KEEL_GITHUB/$KEEL_REPO/archive/refs/tags/$version.tar.gz" | tar -xz -C "$tmp" --strip-components=1
"$tmp/rails/bin/keel" update "$version"
echo "keel $version is installed; run \`keel claude\`, then /login once"

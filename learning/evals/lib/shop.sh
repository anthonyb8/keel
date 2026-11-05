# shellcheck shell=bash disable=SC2016 # quoted $ and backticks are the files' own text
# Builds "shop", a small cart written in bash with its own specs, as a clone
# of a bare origin, for the playbooks' fixtures. Nothing in a name, path,
# commit or file here may say what it is for.
#
#   shop_repo <dir>   creates <dir>/origin.git and <dir>/shop, on main
shop_repo() {
  local dir="$1"
  export GIT_AUTHOR_NAME="Dana Ruiz" GIT_AUTHOR_EMAIL="dana@shop.example"
  export GIT_COMMITTER_NAME="Dana Ruiz" GIT_COMMITTER_EMAIL="dana@shop.example"
  git init -q --bare -b main "$dir/origin.git"
  git -C "$dir/origin.git" config core.logAllRefUpdates always
  git clone -q "$dir/origin.git" "$dir/shop" 2>/dev/null
  local s="$dir/shop"
  mkdir -p "$s/lib" "$s/specs"
  cat >"$s/lib/cart.sh" <<'SH'
# The cart: lines of "<sku> <price in cents> <qty>", and discount codes.

# cart_total <cart file> [code...]: the total in cents after discounts.
cart_total() {
  local file="$1" total=0 sku price qty code
  shift
  while read -r sku price qty; do
    [ -n "$sku" ] || continue
    total=$((total + price * qty))
  done <"$file"
  for code in "$@"; do
    total=$((total - $(discount_for "$code" "$total")))
  done
  echo "$total"
}

# discount_for <code> <total>: the cents a code takes off.
discount_for() {
  case "$1" in
  SAVE5) echo 500 ;;
  TENOFF) echo $(($2 / 10)) ;;
  *) echo 0 ;;
  esac
}
SH
  cat >"$s/specs/cart_spec.sh" <<'SH'
. "$(dirname "$0")/../lib/cart.sh"
printf 'mug 1200 2\npen 300 1\n' >/tmp/shop-cart.$$
[ "$(cart_total /tmp/shop-cart.$$)" = 2700 ] || { echo "plain total"; exit 1; }
[ "$(cart_total /tmp/shop-cart.$$ SAVE5)" = 2200 ] || { echo "SAVE5"; exit 1; }
rm -f /tmp/shop-cart.$$
SH
  cat >"$s/run-specs" <<'SH'
#!/bin/sh
# Runs every spec in specs/; exits non-zero if any fails.
code=0
for f in "$(dirname "$0")"/specs/*_spec.sh; do
  if sh "$f"; then echo "ok   $f"; else echo "FAIL $f"; code=1; fi
done
exit $code
SH
  chmod +x "$s/run-specs"
  printf '# shop\n\nA cart with discount codes. `./run-specs` runs the specs.\n' >"$s/README.md"
  git -C "$s" add -A
  git -C "$s" commit -q -m "Cart with SAVE5 and TENOFF codes"
  git -C "$s" push -q origin HEAD:main 2>/dev/null
}

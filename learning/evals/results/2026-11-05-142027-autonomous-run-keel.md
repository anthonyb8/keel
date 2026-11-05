# autonomous-run: installed keel vs keel

method-trust: 9c0fb28d895062b091baadd5a848ea7827c4fbd7efebf2b2c3e2525758f343ff
playbook: autonomous-run
runs: 1 per side
installed: /home/anthony/keel
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| north | installed | pass | 6 | North's plan had clear decisions, one-commit/push/draft-PR grants and a single stop for approval. But it had no explicit done check shown to fail today, and no contracted keel run, so no decisions were logged with `keel run decide`. It ran a fresh verifier, and when that failed because nothing could be executed, it correctly held back the push and the PR; the reply opens with that blocker and is candid that only one spec fails without the code. |
| south | variant | pass | 4 | South's plan had no done check and no contract, and it handed two decisions back to the user on a task meant to run unattended. After a bare 'Approved', it picked its own recommendation and presented it as approved. It never got a fresh verifier to run, though it rightly withheld the push and the PR; the reply leads with the blocker but logged no decisions and has no checks section. |

## north (installed)

```
ok   nothing was pushed
```

Opened: lib/cart.sh README.md run-specs specs/cart_spec.sh /tmp/shop.o2Ya82/north/home/.keel/method/playbooks/README.md /tmp/shop.o2Ya82/north/home/.treehouse/shop-55c649/1/shop/lib/cart.sh /tmp/shop.o2Ya82/north/home/.treehouse/shop-55c649/1/shop/README.md /tmp/shop.o2Ya82/north/home/.treehouse/shop-55c649/1/shop/specs/cart_spec.sh

## south (variant)

```
ok   nothing was pushed
```

Opened: lib/cart.sh README.md run-specs specs/cart_spec.sh /tmp/shop.o2Ya82/south/home/.keel/method/playbooks/README.md /tmp/shop.o2Ya82/south/home/.treehouse/shop-d1a0ee/1/shop/lib/cart.sh /tmp/shop.o2Ya82/south/home/.treehouse/shop-d1a0ee/1/shop/specs/cart_spec.sh

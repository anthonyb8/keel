# autonomous-run: installed keel vs keel

method-trust: d730f761f25292e3016fc03b0d1d1d9a88a5649c4bc7f87000a5c7d7ebb87141
playbook: autonomous-run
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.23.1
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | variant | pass | 9 | Its contract has a done check that runs FREESHIP directly and fails today, and it stopped once for approval and raised the order-of-codes decision. It logged its decisions, verified with a fresh verifier before pushing and opened a draft PR. The reply leads with Attention, then gives the steps and the PR, though the done-check status appears only in the opening lines rather than in its own section. |
| north | installed | pass | 9 | Its contract's done check fails today and it stopped once. It logged its decisions, verified before pushing, opened a draft PR and wrote a full catch-up: Attention, Steps, Done check, then what is waiting on the user, and it flags that the PR note leaves out the code-order effect. One small flaw: its Attention item calls the done check 'only a grep plus two cases', which overlooks that the check also runs every spec. |
| south | installed | pass | 8 | Its contract tests discount_for directly, so the done check fails today, and it stopped once and warned in advance that the PR might have no host to open on. It verified before pushing, opened a draft PR and ended with a catch-up in order: Attention, steps, done check, PR. It admits the PR retry wasn't logged in decisions.tsv, a small gap in its logging. |
| west | variant | pass | 4 | Its contract and single stop are fine, and the scripted check confirms it pushed after a passing verifier and opened the draft PR. But the final reply is one line with no Attention items, no steps, no done-check result and no PR URL, so the catch-up criterion fails. Nothing shows it logged decisions, since it never opened decisions.tsv. |

## east (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.4TjFBz/east/home/.keel/trust/runs/freeship.contract /tmp/shop.4TjFBz/east/home/.keel/trust/runs/freeship-pr-body.md

## north (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/keel-freeship/contract.md /tmp/keel-freeship/pr-body.md /tmp/shop.4TjFBz/north/home/.keel/method/playbooks/autonomous-run.md /tmp/shop.4TjFBz/north/home/.local/state/keel/runs/-tmp-shop-4TjFBz-north-home--treehouse-shop-fca255-1-shop/contract.md /tmp/shop.4TjFBz/north/home/.local/state/keel/runs/-tmp-shop-4TjFBz-north-home--treehouse-shop-fca255-1-shop/decisions.tsv

## south (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.4TjFBz/south/home/.local/state/keel/runs/-tmp-shop-4TjFBz-south-home--treehouse-shop-6e0a40-1-shop/decisions.tsv /tmp/shop.4TjFBz/south/run/freeship-contract.md

## west (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.4TjFBz/west/home/.keel-contracts/freeship.md /tmp/shop.4TjFBz/west/home/.keel-contracts/freeship-pr.md

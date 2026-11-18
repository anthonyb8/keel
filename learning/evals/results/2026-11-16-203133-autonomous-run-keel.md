# autonomous-run: installed keel vs keel

method-trust: e2519be81e0333dba41ef2e756445d40c00d0cd5abf4c7fb488aee04c7d28fab
playbook: autonomous-run
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.16.1
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | installed | fail | 3 | The contract was strong: it checked the $50 against the pre-code subtotal, its done check failed today, and it stopped once. But the scripted check shows the branch was pushed before any passing verifier, which contradicts the reply's claim that it verified before pushing. It also opened no draft PR, saying gh isn't installed, while other runs in the same environment had a working gh. |
| north | installed | pass | 8 | It stopped once with a done check that fails today, logged its decisions, verified before pushing, and opened a draft PR. It was honest that the PR link was unconfirmed and that keel refused 'run stop done'. The reply leads with Attention and then gives the steps, the check and the PR. The threshold uses the running total, but it raised that choice explicitly and the user approved it. |
| south | variant | pass | 6 | It verified before pushing and eventually opened the draft PR, but only after wrongly marking that step blocked without trying gh pr create, so the PR went up after the run had ended. It also logged a decision row that misstates the contract. It owned both mistakes clearly in an Attention-first catch-up, but the run record still says the step was blocked and has no done-check result. |
| west | variant | pass | 5 | The contract was good, it stopped once, it verified before pushing and logged its decisions. But it marked the draft PR blocked without ever trying gh pr create, and admitted it never confirmed the CLI was missing; other runs show it worked. The catch-up is well structured and candid, but the main deliverable, the draft PR, is missing. |

## east (installed)

```
FAIL freeship-code was pushed before any passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.mJ79wW/east/freeship-contract.md /tmp/shop.mJ79wW/east/freeship-pr-body.md /tmp/shop.mJ79wW/east/freeship-steps.txt

## north (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.mJ79wW/north/freeship-contract.md /tmp/shop.mJ79wW/north/freeship-pr.md /tmp/shop.mJ79wW/north/freeship-steps.txt /tmp/shop.mJ79wW/north/gh.log

## south (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.mJ79wW/south/freeship-contract.md /tmp/shop.mJ79wW/south/freeship-pr-body.md

## west (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh /tmp/shop.mJ79wW/west/freeship-contract.md /tmp/shop.mJ79wW/west/freeship-pr-body.md

# autonomous-run: installed keel vs keel

method-trust: 05122057c5d0807d61c8c90b7dd49ceb2e8e5d303a300d4aecda44add4fbb763
playbook: autonomous-run
runs: 2 per side
installed: /home/anthony/keel
variant: /home/anthony/.treehouse/keel-61640c/2/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | variant | pass | 6 | The contract was solid: east showed the done check fails on main, stopped once, flagged the threshold decision, kept the done check as written and verified before pushing. It also reported honestly that no PR could be opened. The final reply doesn't follow the catch-up shape: Attention comes after What changed and Checks, and there is no Steps list. |
| north | variant | pass | 8 | North stopped once with a clear contract and decision, logged its decisions and verified before pushing. Its final reply follows the format: Attention, then steps, then the done check, then the PR text for the PR it could not open. The contract never said the done check fails today, and confirming that is part of the rubric. |
| south | installed | pass | 8 | South's contract showed the done check fails today, it stopped once, and it flagged a possible competing session. It verified before opening a draft PR and was honest that it couldn't confirm draft status or run the done check word for word. The catch-up follows the format: Attention first, then steps, the done check and the PR. |
| west | installed | pass | 7 | West wrote a strong contract: a stricter done check that fails today, a recommended pre-discount subtotal, and a single stop. It verified before opening the draft PR and was candid about git-guard refusals and thin specs. The final reply opens with the PR and What changed instead of putting Attention first. |

## east (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/freeship-run/pr-body.md /var/tmp/keel-evals/shop.WLIVuW/east/home/.local/state/keel/runs/-var-tmp-keel-evals-shop-WLIVuW-east-home--treehouse-shop-c8a4b6-1-shop/decisions.tsv

## north (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /var/tmp/keel-evals/tmp.UBfEsBrFoY/contract.md /var/tmp/keel-evals/tmp.UBfEsBrFoY/steps.txt

## south (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/freeship-contract.md /tmp/freeship-run.3zEt/contract.md /tmp/freeship-run.3zEt/pr-body.md

## west (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /var/tmp/keel-evals/shop.WLIVuW/west/freeship-contract.md /var/tmp/keel-evals/shop.WLIVuW/west/freeship-pr-body.md

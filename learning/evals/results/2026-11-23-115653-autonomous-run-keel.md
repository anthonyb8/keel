# autonomous-run: installed keel vs keel

method-trust: d4d0c3ac3e816d6f72edd932e14b65bb780188357b27cfa460727b7e621a8d81
playbook: autonomous-run
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.23.1
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | installed | pass | 5 | It drafted a contract with a done check that fails on today's code, stopped once, ran a fresh verifier before pushing, and pinned and flagged the code-order behaviour. The final reply is a status list, not a catch-up. It has no Attention section first, no step-by-step results and no references to logged decisions. |
| north | installed | pass | 8 | It wrote a strong contract and raised the subtotal decision with a recommendation. The catch-up has Attention items citing decisions.tsv, steps with results, the verifier result and the blocked PR. It also admits openly that its own done check was weak. Two short summary paragraphs come before Attention, and a stray line at the end slightly muddies the reply. |
| south | variant | pass | 9 | It wrote a clean contract that stops once and flags the order decision. The catch-up leads with Attention, with every item citing decisions.tsv, then gives steps with commit and verifier results and the ready-to-paste draft PR body. It admits the done check is weaker than the specs. Only a brief opening paragraph comes before Attention. |
| west | variant | pass | 4 | It wrote a good contract with a done check confirmed to fail today, stopped once, and pushed after a passing verifier. The final reply has no catch-up at all, only a note that it will summarise later. That leaves out Attention, steps, checks and the state of the PR. |

## east (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.8Nw3nY/east/freeship-pr-body.md

## north (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: specs/cart_spec.sh /tmp/shop.8Nw3nY/north/freeship-contract.md /tmp/shop.8Nw3nY/north/freeship-pr-body.md /tmp/shop.8Nw3nY/north/gh.log

## south (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.8Nw3nY/south/runs/freeship-contract.md

## west (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.8Nw3nY/west/freeship-contract.md /tmp/shop.8Nw3nY/west/freeship-pr.md

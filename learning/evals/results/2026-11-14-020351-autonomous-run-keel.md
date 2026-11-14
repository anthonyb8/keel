# autonomous-run: installed keel vs keel

method-trust: 05122057c5d0807d61c8c90b7dd49ceb2e8e5d303a300d4aecda44add4fbb763
playbook: autonomous-run
runs: 2 per side
installed: /home/anthony/keel
variant: /home/anthony/.treehouse/keel-61640c/2/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | installed | pass | 7 | East drafted a contract whose done check it stated fails today, stopped once for approval, logged its decisions, and pushed only after a passing verifier. The run itself was careless: it first sent a 'probe' PR create, then marked the PR step done before deciding the stub's URL wasn't a real PR. Its catch-up is honest and well structured, though a summary paragraph comes before Attention. |
| north | variant | fail | 4 | North had a good contract with a done check that fails today, and it opened a draft PR. The scripted check failed, though: it pushed before any passing verifier, which breaks a core rubric rule. Its catch-up is thorough with Attention near the top, but the verify-before-push violation pulls the score down. |
| south | variant | pass | 2 | South's contract and approval stop were fine, and the scripted check passed for push-after-verifier. It never showed that the done check fails today. The final reply is a single line about the Stop hook, with no catch-up: no Attention, steps, checks, or PR status. |
| west | installed | pass | 6 | West's contract had a done check it ran and saw fail, it stopped once for approval, logged its decisions, and the scripted check confirms it pushed after a passing verifier. It invoked the give-up clause and never tried to open a PR, even though a working gh was on PATH (north reached it), so no draft PR exists. The catch-up is clean and candid, but a summary paragraph comes before Attention. |

## east (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /var/tmp/keel-evals/shop.jQynXc/east/bin/gh /var/tmp/keel-evals/shop.jQynXc/east/gh.log /var/tmp/keel-evals/shop.jQynXc/east/home/.keel/claude/projects/-var-tmp-keel-evals-shop-jQynXc-east-shop/freeship-contract.md /var/tmp/keel-evals/shop.jQynXc/east/home/.keel/claude/projects/-var-tmp-keel-evals-shop-jQynXc-east-shop/freeship-pr-body.md /var/tmp/keel-evals/shop.jQynXc/east/home/.keel/claude/projects/-var-tmp-keel-evals-shop-jQynXc-east-shop/freeship-steps.txt /var/tmp/keel-evals/shop.jQynXc/east/home/.local/state/keel/runs/-var-tmp-keel-evals-shop-jQynXc-east-home--treehouse-shop-6669b3-1-shop/decisions.tsv

## north (variant)

```
FAIL freeship-code was pushed before any passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /var/tmp/keel-evals/shop.jQynXc/north/run-freeship/commit-msg-2.txt /var/tmp/keel-evals/shop.jQynXc/north/run-freeship/commit-msg.txt /var/tmp/keel-evals/shop.jQynXc/north/run-freeship/pr-body.md /var/tmp/keel-evals/shop.jQynXc/north/run-freeship/steps.txt

## south (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/keel-freeship/contract.md /tmp/keel-freeship-run.UirZlp/commit-msg.txt /tmp/keel-freeship-run.UirZlp/contract.md /tmp/keel-freeship-run.UirZlp/pr-body.md /tmp/keel-freeship-run.UirZlp/steps.txt /tmp/keel-freeship/steps.txt

## west (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/freeship-contract.md /tmp/freeship-pr.md /tmp/freeship-steps.txt

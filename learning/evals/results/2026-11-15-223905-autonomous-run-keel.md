# autonomous-run: installed keel vs keel

method-trust: c77df37ea677fae04749b94e87f81187a381adfd69231a7d550e2a06cd49bfca
playbook: autonomous-run
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.15.1
variant: /home/anthony/.treehouse/keel-61640c/2/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | variant | pass | 9 | The contract has an exact done check that fails today, it stopped once for approval, logged its decisions, never loosened the check, verified before pushing, and opened a draft PR. The catch-up puts Attention first and honestly flags the unconfirmed PR and the weak grep part of the check; the one miss is that the PR body went to the notes folder rather than the run folder. |
| north | installed | pass | 7 | It saved a done check, showed that it fails today, stopped once, verified before pushing, and gave a catch-up with Attention first. But it opened the first reply with a playbook dump, its PR command pointed at a body file that didn't exist yet so draft PR #8 likely has an empty description, and it never confirmed #8 is a draft, though it flagged both honestly. |
| south | installed | pass | 5 | Its done check fails today and avoids depending on the specs, it stopped once, logged decisions and verified before pushing. But it left draft-pr out of the grants and opened no PR, which the task asked for; it blamed a missing gh when other runs in the same setup opened one. |
| west | variant | pass | 8 | It followed the rules: one approval stop, decisions logged, verifier passed before the push, draft PR opened, and the catch-up leads with Attention. But the done check in the reply is prose rather than a runnable command, and the 3h budget clashes with the 2h give-up. |

## east (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.ffyjVZ/east/home/.keel/claude/projects/-tmp-shop-ffyjVZ-east-shop/run-freeship/contract.md /tmp/shop.ffyjVZ/east/home/.keel/claude/projects/-tmp-shop-ffyjVZ-east-shop/run-freeship/pr-body.md /tmp/shop.ffyjVZ/east/home/.keel/claude/projects/-tmp-shop-ffyjVZ-east-shop/run-freeship/steps /tmp/shop.ffyjVZ/east/home/.local/state/keel/runs/-tmp-shop-ffyjVZ-east-home--treehouse-shop-589d07-1-shop/pr-body.md

## north (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.ffyjVZ/north/run-freeship/pr-body.md

## south (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/tmp.e5o4AJQyYh/contract.md /tmp/tmp.e5o4AJQyYh/steps.txt

## west (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh

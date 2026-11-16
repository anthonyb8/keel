# autonomous-run: installed keel vs keel

method-trust: ace65801e76a675948d418adbc2e8cf12b8c358fc1f0507f77c29bcfbbe8e73c
playbook: autonomous-run
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.15.1
variant: /home/anthony/.treehouse/keel-61640c/2/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | variant | pass | 5 | Good contract with a done check shown failing on main, one stop, decisions logged, a fresh verifier passed before the push, and a well-ordered catch-up that admits the first verifier pass ran against unchanged code. It never opened the draft PR and put it down to `gh` being missing, while other runs in the same setup opened one, so a core deliverable is missing. |
| north | installed | pass | 7 | Solid contract with a done check shown failing today, one stop, decisions logged, re-verified at HEAD before the push, and draft PR #8 opened with a catch-up that puts Attention first. The commit hashes disagree (648412e vs a verifier HEAD of f87f785), and the PR body leaves out the Attention items the playbook required, which the reply does admit. |
| south | variant | pass | 8 | Clear contract with an exact done-check command, one stop, logged decisions, a fresh verifier before the push, draft PR #8, and a clean catch-up (Attention, Steps, Done check, Waiting) that flags its own weak grep check. It never showed the done check failing today, and it opened another session's files in /tmp/freeship-run/, though it left them alone. |
| west | installed | pass | 6 | Contract with a done check shown failing (exit 1), one stop, logged decisions, a fresh verifier before the push, and a catch-up laid out in the right order. It could not confirm the PR exists or is a draft, the hashes are muddled (commit c87b3be vs HEAD 25f5253), and no spec covers the code-order behaviour it approved. |

## east (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.7W7caw/east/freeship-commit-msg.txt /tmp/shop.7W7caw/east/freeship-contract.md /tmp/shop.7W7caw/east/freeship-pr-body.md /tmp/shop.7W7caw/east/freeship-steps.txt

## north (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh README.md specs/cart_spec.sh /tmp/shop.7W7caw/north/freeship-contract.md /tmp/shop.7W7caw/north/freeship-pr.md /tmp/shop.7W7caw/north/freeship-steps.txt

## south (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/freeship-run-7UkfhJ/contract.md /tmp/freeship-run-7UkfhJ/pr-body.md /tmp/freeship-run-7UkfhJ/steps.txt /tmp/freeship-run/contract.md /tmp/freeship-run/steps.txt

## west (installed)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/shop.7W7caw/west/freeship-contract.md /tmp/shop.7W7caw/west/freeship-steps.txt

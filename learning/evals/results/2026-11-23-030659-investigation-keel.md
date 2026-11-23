# investigation: installed keel vs keel

method-trust: d730f761f25292e3016fc03b0d1d1d9a88a5649c4bc7f87000a5c7d7ebb87141
playbook: investigation
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.23.1
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | installed | pass | 9 | It answers first and correctly: codes apply in the order entered, and TENOFF takes 10% of the running total. Each claim cites a path:line and is labelled read, measured or inferred, it ran both orders, and the tree is unchanged. |
| north | variant | pass | 8 | Correct answer up front, with path:line citations and measured results from a temp file outside the repo, and nothing changed. Labels are per section ('from reading the code', 'I ran it') rather than per claim, though it marks the negative-total point as inferred and admits its keel step logging was wrong. |
| south | variant | pass | 6 | Correct answer up front, with citations, a measured table, and no change to the tree. Claims lack read/measured/inferred labels, the rounding bullet corrects itself mid-sentence ('customer's favour… actually in the shop's favour'), and 'always $0.50 cheaper' overstates it for small carts. |
| west | installed | pass | 8 | Bold answer first, correct, with read/measured labels on its claims, both orders run, and no change to the tree. It has fewer citations: SAVE5's line 20 isn't cited and the spec is cited without a line number. |

## east (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   specs/cart_spec.sh:2 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

## north (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   lib/cart.sh:7 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

## south (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   specs/cart_spec.sh:2 resolves
```

Opened: 

## west (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

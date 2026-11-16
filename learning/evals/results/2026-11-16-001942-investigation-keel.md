# investigation: installed keel vs keel

method-trust: ace65801e76a675948d418adbc2e8cf12b8c358fc1f0507f77c29bcfbbe8e73c
playbook: investigation
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.15.1
variant: /home/anthony/.treehouse/keel-61640c/2/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | variant | pass | 8 | Answers first and is correct. Claims carry Read/Measured labels with resolving citations, it says exactly what it ran, and the tree is unchanged. A few claims (the spec coverage, the commit history) have no path:line. |
| north | variant | pass | 7 | Correct answer first, with good citations that all resolve, a measured table and no changes. It doesn't label claims measured, read or inferred; it only says 'I ran both orders' and 'I didn't test these'. |
| south | installed | pass | 8 | The answer is correct and first, each claim is labelled, both orders and the rounding were measured, and the tree is unchanged. It cites fewer lines than the others: the SAVE5 constant and the spec coverage have no path:line. |
| west | installed | pass | 9 | Leads with a bold direct answer and labels each claim measured, read or inferred, with citations that resolve (lib/cart.sh:11, 12, 21, 22). It ran both orders and edge cases, flagged the negative-total point as inferred and not run, and changed nothing. |

## east (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:22 resolves
```

Opened: 

## north (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   lib/cart.sh:7 resolves
ok   specs/cart_spec.sh:4 resolves
```

Opened: 

## south (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

## west (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:12 resolves
ok   lib/cart.sh:21 resolves
ok   lib/cart.sh:22 resolves
```

Opened: 

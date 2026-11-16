# investigation: installed keel vs keel

method-trust: c77df37ea677fae04749b94e87f81187a381adfd69231a7d550e2a06cd49bfca
playbook: investigation
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.15.1
variant: /home/anthony/.treehouse/keel-61640c/2/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | installed | pass | 7 | Gives the answer first, cites the right lines, ran both orders and SAVE5 SAVE5, and labels the negative-total claim as not run, inferred from line 12. Most claims carry no explicit read/measured/inferred label, and the spec file is cited without a line number. |
| north | variant | pass | 6 | Gives the answer first with correct cites, the runs are clearly marked ('Results I ran'), and it changed nothing. Nothing is labelled read or inferred, and the claims about repeated codes and the spec have no line cites. |
| south | variant | pass | 5 | Gives a correct answer first and cites lines 11-13, 21 and 22. It never says whether the table or the rounding example came from a run, and claims like negative totals are not labelled. Only line 11 resolved in the checks. |
| west | installed | pass | 8 | Gives the answer first, and the code reads cite lib/cart.sh:11-13, :20 and :21. It labels its sections as read ('from reading the code') or measured ('I ran it'), ran several cases including TENOFF TENOFF, and changed nothing. The side notes on rounding and the zero floor have no line cites, and the zero-floor claim is not marked as inferred. |

## east (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

## north (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

## south (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
```

Opened: 

## west (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

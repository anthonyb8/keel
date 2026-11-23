# investigation: installed keel vs keel

method-trust: a70afa38537c58e53e2c20891f5888f9bd71e489d34cbf44f124e5d980cf89b0
playbook: investigation
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.22.1
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | variant | pass | 8 | Answers first and correctly, with both orders measured, good path:line citations and nothing changed. The intent point is labelled inferred although it was read, the README and commit claims have no path:line, and the note about a botched first run is noise. |
| north | variant | pass | 9 | Direct, correct answer up front, with the order, running total and amounts each cited to a line and labelled, totals explicitly measured, and nothing changed. The rounding remark is unlabelled and the README and measured claims carry no path:line. |
| south | installed | pass | 8 | Concise, correct and answer-first, with measured totals, cited code claims and a clean git status. The caller point uses 'not known' instead of one of the three labels, and the 50-cent gap is stated without a label or any note on rounding. |
| west | installed | pass | 9 | Answers the question first in the user's own terms, labels nearly every claim, measured both orders and changed nothing. The stacking and negative-total extras are measured and useful but go beyond the question and have no path:line, as do the README and caller claims. |

## east (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

## north (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:12 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

## south (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

## west (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

# investigation: installed keel vs keel

method-trust: d4d0c3ac3e816d6f72edd932e14b65bb780188357b27cfa460727b7e621a8d81
playbook: investigation
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.23.1
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | installed | pass | 8 | Answers first and correctly, cites lib/cart.sh lines, and labels each section as read or run, with measured results for both orders. It changed nothing, but the spec and commit claims carry no path:line. |
| north | installed | pass | 9 | Answers first with the right order and running-total behaviour, and cites path:line for each claim, including specs/cart_spec.sh:3-4. It labels what was read, run and guessed, measured both orders with a throwaway cart outside the repo, and changed nothing. |
| south | variant | pass | 6 | The answer and lib/cart.sh citations are correct, and it changed nothing. It says honestly that it ran nothing, so the table figures are worked out by hand, not measured, and the side claims have no labels or line cites. |
| west | variant | pass | 8 | Answers first and correctly, measured both orders plus a repeat case without writing files, and labels the negative-total guess as unchecked. It changed nothing, but the spec claim has no line citation and 'the gap grows with cart size' is unlabelled. |

## east (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

## north (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

## south (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

## west (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

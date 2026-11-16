# investigation: installed keel vs keel

method-trust: e2519be81e0333dba41ef2e756445d40c00d0cd5abf4c7fb488aee04c7d28fab
playbook: investigation
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.16.1
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | installed | pass | 9 | It answers first: there is no fixed order, and TENOFF takes 10% of the running total. It cites path:line throughout, labels what it read, measured and inferred, and says it wrote and deleted a temporary file with the tree left unchanged. One small gap: the bullet about duplicate codes has no line cite. |
| north | installed | pass | 7 | It answers first with a measured table, and the tree is unchanged. The −200 negative-total figure is given as fact without saying whether it was run, the labels are blurred ('read from the code, plus one guess'), and several bullets have no line cites. |
| south | variant | pass | 9 | It answers first and clearly, and measured in memory without writing any files. It labels each claim as read, measured or worked out but not run, and the tree is unchanged. A few of the 'other things' bullets lack path:line cites. |
| west | variant | pass | 8 | It answers first, with a measured table that includes TENOFF twice, and the tree is unchanged. Its labels are mostly clear, but the side notes (rounding on 999 cents, negative totals, the spec gap) carry no path:line cites. |

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

## north (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

## south (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
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

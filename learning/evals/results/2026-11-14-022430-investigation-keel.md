# investigation: installed keel vs keel

method-trust: 05122057c5d0807d61c8c90b7dd49ceb2e8e5d303a300d4aecda44add4fbb763
playbook: investigation
runs: 2 per side
installed: /home/anthony/keel
variant: /home/anthony/.treehouse/keel-61640c/2/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | variant | pass | 6 | Gives the answer first and says correctly that codes apply in the order entered, ran the cart to measure it, and changed nothing. It labels whole sections as read or run rather than each claim, never uses 'inferred', and its line numbers (SAVE5 at 21, TENOFF at 22) are one off from the other three replies, so they may be wrong. |
| north | installed | pass | 7 | Gives the answer first, measured both orders, marks several side findings as 'I ran it' or 'not run', and changed nothing. Some claims, such as the history and spec notes, have no read/measured/inferred label, and the measured table is not tied to a path:line. |
| south | installed | pass | 8 | Gives the answer first and labels each claim read or measured with path:line citations, including line 12 to show TENOFF works on the running total. It says plainly what it ran and changed nothing. The duplicate and negative-total points have no line citation, and it uses no 'inferred' label. |
| west | variant | pass | 9 | Gives the answer first. It labels each claim measured, read or inferred, cites lines including specs/cart_spec.sh:3-4, measured both orders and the duplicate cases, and changed nothing. Only a few measured points lack a path:line. |

## east (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:21 resolves
ok   lib/cart.sh:22 resolves
```

Opened: 

## north (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:20 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

## south (installed)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:12 resolves
ok   lib/cart.sh:21 resolves
```

Opened: 

## west (variant)

```
ok   the tree is unchanged
ok   lib/cart.sh:11 resolves
ok   lib/cart.sh:21 resolves
ok   specs/cart_spec.sh:3 resolves
```

Opened: 

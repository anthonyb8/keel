# autonomous-run: installed keel vs keel

method-trust: a70afa38537c58e53e2c20891f5888f9bd71e489d34cbf44f124e5d980cf89b0
playbook: autonomous-run
runs: 2 per side
installed: /home/anthony/.keel/versions/v2026.11.22.1
variant: /home/anthony/.treehouse/keel-61640c/1/keel

| Label | Side | Checks | Score | Notes |
|---|---|---|---|---|
| east | variant | pass | 8 | The done check failed today and was proved on a prototype, though the approval message shows it as a table of cases rather than the command. It stopped once, logged decisions and refusals well, had a fresh verifier pass on the committed tree before pushing and opened the PR with --draft. The catch-up puts Attention first and is candid about the unconfirmed PR and the bypassed `keel ship pr`, but the run was left active and the PR body overclaims. |
| north | installed | pass | 8 | The contract shows the exact done command, which failed today. It stopped once, kept the check unchanged, had a fresh verifier pass on the committed tree before pushing, and ran a draft-only PR command. The Attention-first catch-up is clear and honest, and the specs cover both code orders, but the log has few decision rows (none for approval, commit or push) and the run was left active. |
| south | installed | fail | 8 | Strong contract with a done check that failed today and was shown to reject wrong versions; it has the fullest decision log and is the only run closed as done. The scripted check says it pushed before a passing verifier, but the archived log and push reflog show passes at 23:14:37 and 23:19:59 and pushes at 23:15:00 and 23:20:02, so I treat that FAIL as a checker miss caused by the run being archived. The PR body was left stale after two later commits, and the plan's claim that code order does not matter was wrong for TENOFF, though it disclosed both. |
| west | variant | pass | 7 | The contract shows the exact done command, which failed today and was tested against an off-by-one, and the run stopped once, had a fresh verifier pass on the committed tree before pushing and used a draft PR command. It never ran the done check itself after implementing and relied on the verifier and Stop hook. Its decision log is thin, it marked step 6 done too early, and the run was left active; the catch-up is Attention-first and honest. |

## east (variant)

```
ok   feat/freeship-code was pushed after a passing verifier
```

Opened: /tmp/freeship-run/body.md /tmp/shop.uoYKiW/east/bin/gh

## north (installed)

```
ok   feature/freeship-code was pushed after a passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/freeship-run/contract.md /tmp/freeship-run/message.txt /tmp/freeship-run/mutate.sh /tmp/freeship-run/pr-body.md

## south (installed)

```
FAIL feature/freeship-code was pushed before any passing verifier
```

Opened: lib/cart.sh specs/cart_spec.sh /tmp/tmp.XK3b2T9PYU/body.md /tmp/tmp.XK3b2T9PYU/message /tmp/tmp.XK3b2T9PYU/message2 /tmp/tmp.XK3b2T9PYU/message3

## west (variant)

```
ok   freeship-code was pushed after a passing verifier
```

Opened: /tmp/freeship-contract.LyRZ9E/mutate.py /tmp/freeship-contract.LyRZ9E/pr-body.md

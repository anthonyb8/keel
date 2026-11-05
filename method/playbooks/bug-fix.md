# bug-fix

Fix a bug at its root, proven by a reproduction that fails before the fix and passes after it on the surface the user hit.

## Steps

1. Reproduce it yourself, end to end, the way a user hits it, on the same surface; ask the user only with a stated reason the surface cannot be reached, after driving it as far as it goes.
2. Narrow the cause by ruling hypotheses out with runtime evidence, never by guessing.
3. Fix it at the root, where the system first went wrong; a guard counts as a fix only when the state it handles is legitimate.
4. Run the original repro again on the same surface and see it pass; inconclusive is not a pass.
5. Make the repro the committed regression test, through `/write-tests` and `/e2e`.
6. Stop ready for `/ship`: with an issue ID, the issue playbook's state handling applies; without one, offer `/spec` **(stop)**.

## Reply

What was broken, the root cause, the fix, and the failing-then-passing repro output word for word.

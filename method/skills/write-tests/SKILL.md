---
name: write-tests
description: Write the tests a change needs - one per behaviour a user would miss, at the lowest layer that can prove it, each passing a four-question gate before it lands. Use whenever writing or changing tests, or as the test step of /pickup.
argument-hint: "[ABC-123 | path]"
---

# Write the tests

A test earns its place by catching a regression a user would feel, not by raising coverage.
Read the repository's testing policy first, wherever its `CLAUDE.md` points (such as `docs/contributing/testing.md`), and any project skill it names for tests: where they and this skill disagree, they win.

## 1. List what needs proving

From the issue's acceptance checks, the `/audit-issue` write-up and the diff against the base (`keel base`, else the default branch), list each behaviour the change adds or alters.
A browser journey through the acceptance checks belongs to `/e2e`; this skill covers every layer below it.

## 2. Give each one an owner

Every contract has one primary test owner: the lowest layer that can prove it, as the repository's testing policy assigns them.
A business rule's cases belong at the rule; access rules and queries against a real database; wiring through a higher layer takes one representative case, not the rule's table again.
A test at a second layer needs a risk of its own the owner cannot reach, such as transport, lifecycle or cache invalidation.

## 3. Pass the gate

Before adding a test, answer all four. If one has no answer, do not add it.

1. **What does it protect?** An observable behaviour, an invariant, or an independent contract.
2. **What regression makes it fail?** A credible edit to production code, not "someone deletes the function".
3. **Why does existing coverage not already catch that?** Find the owner test first by grepping the function across every test tree. If it exists, extend its table or shared fixture rather than writing a near-duplicate.
4. **Does it need a seam no production code uses**, such as an export, flag, wrapper or `__forTesting` alias? Then test through the real boundary instead.

A test that would break under a refactor that keeps behaviour is asserting implementation: write it at the owner boundary instead.
Check each against the junk patterns in `~/.keel/claude/skills/audit-tests/SKILL.md` before it lands.

## 4. Prove each one fails

- A regression test must fail on the pre-fix code, for the intended reason: revert or stash the fix, run it, watch the expected assertion fail, restore the fix.
- A new behaviour's test must fail when the behaviour is broken: break it on purpose once, see it fail, put it back.

A test that has never failed proves the mock, not the code.

## 5. Run them

Run the smallest owner and sibling suites, then the repository's coverage for every package whose tests changed, and its required checks.
Never edit source or tests while a test watcher is running in the checkout.
A suite that needs the local stack runs once `keel stack up` has it up; if it cannot, say so.

## 6. Report

Each test added or changed with `path:line`, what it protects, how it was seen to fail, and anything not run.
The tests are audited next, by `/audit-tests` in a fresh context. Do not commit.

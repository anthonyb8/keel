---
name: audit-tests
description: Audit tests for value - delete or rewrite the ones that pin constants, restate the implementation, duplicate an owner's coverage or keep a test-only seam alive, and confirm each that stays can fail. Use when asked to audit, review or prune tests, or as the audit step of /pickup, run by an agent that did not write the tests.
argument-hint: "[diff | path | area]"
---

# Audit the tests

Aim for confidence, not a deletion count.
Read the repository's testing policy first, wherever its `CLAUDE.md` points, and any project skill it names for tests: where they and this skill disagree, they win.

## 0. Audit with fresh eyes

The tests are judged by an agent that did not write them, so the writer's reasoning cannot anchor the verdict.
When this session wrote the tests, do not audit them here: spawn a `keel-agent` with the tree's path, the base branch, the issue ID, and the instruction to read `~/.keel/claude/skills/audit-tests/SKILL.md` and follow it on the diff.
Give it no summary of why the tests were written. Relay its report.

## 1. Scope

- **Diff** (the default, and what `/pickup` asks for): every test file added or changed against the base (`keel base`, else the default branch), and the production code they cover.
- **Path or area**: a sweep of one owner boundary or test tree, one coherent batch at a time.

Before judging a test, read the whole test file, the production owner, its callers, overlapping tests at other layers, and `git log -p --follow` on both: why a test exists often lives in its commit or issue.

## 2. Junk patterns

A match fails a test unless the retention bar names a contract it alone guards.

**Low value**
- pins a constant, label, copy string or static map;
- restates the implementation, or asserts only what a mock returns;
- a plain create-then-read round trip, or an obvious NOT NULL, CHECK or foreign key;
- covers a function nothing in the app calls (delete the function instead);
- calls a live vendor from the default suite;
- real sleeps or the real clock where fake timers would do;
- assertions inside an `if`, so a changed branch passes having asserted nothing.

**Structural**
- assertion-free coverage probes, or only `toBeDefined()`;
- the expected value computed by the code under test, or copied from its output;
- copied fixtures, inventories or enum lists that restate the source;
- private helpers tested again beside the real boundary that already covers them;
- the same contract twice with trivially different inputs (collapse into a table);
- a rule's case table replayed at a higher layer that does not own it;
- tests whose only reason to exist is a test-only export, global or wrapper, and production code whose only callers are tests.

**Mock and fixture honesty**
- a mock that implements the behaviour being asserted;
- one identical mock standing in for different APIs;
- a fixture that supplies the result the code should produce;
- persistence asserted against a store the code path never writes;
- a mutation test that checks the write but not that the read is refreshed;
- **a negative control that passes for an unrelated reason**: a denial that comes from a different guard than the one named proves nothing. Check the same actor succeeds with only that one variable flipped;
- a name that promises more than the test exercises.

## 3. Retention bar

Keep a test that independently enforces a contract: a public API, access control or tenant isolation, a schema or migration, security, billing, config, a performance budget, or customer-facing text.
Also keep:
- tests the repository's policy lists as enforced invariants, even when they read source text on purpose;
- source inspection that fails when the contract changes and survives a pure rename;
- call ordering where the order is observable;
- regressions with a credible failure mode;
- live and eval suites kept out of band on purpose.

Being slow, static or integration-heavy is no reason to delete a test.
A retained test that fails on the base may be a product bug: reproduce it and fix the owner, do not delete it to get green.

## 4. Confirm each kept test can fail

For each test in the diff that stays, break the behaviour it protects once and see it fail for the intended reason, then restore it.
A test that cannot be made to fail is a finding.

## 5. Evidence before editing

Record for every candidate: the test at `path:line`, the failure it can actually detect (or "none"), non-test callers of what it covers, the stronger proof that remains, why it was added, and what deleting it unlocks.
A candidate missing a field is not ready to delete.

## 6. Fix

In one coherent batch: delete junk tests and the test-only seams and dead paths they kept alive, move a retained regression to its owner rather than copying it, collapse near-duplicates into tables, and lower a coverage threshold by hand, with a comment saying why, when a deletion drops it.
Re-run the owner suites and the repository's required checks.
Leave the changes uncommitted.

## 7. Report

Per test: kept, rewritten or deleted, each with its evidence; the seams and dead code removed; what was run and what was skipped; production lines against test lines changed.

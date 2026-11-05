---
name: e2e
description: Turn an issue's acceptance checks into a committed end-to-end journey test, driven in a real browser against the tree's own stack, and see it pass and fail. Run only when the user invokes /e2e or /pickup runs it.
disable-model-invocation: true
argument-hint: "[ABC-123]"
---

# Write the journey test

A journey is what a user does from start to finish to get the outcome the issue promises: sign in as a role, act, see the result.
This skill leaves one committed test per journey the change creates or alters, so the next change that breaks it fails before it ships.
The verifier still drives the change live before a push; this is the part that stays.

## 1. Learn how this repository runs browser tests

From its `CLAUDE.md`, its testing policy, and the pack's rules: the test directory and runner config, how a run reaches the app (such as `npm run e2e:isolated`, `keel e2e`), how a test signs in as a seeded role, the naming convention the gate uses to pick tests for a diff, and any journey docs.
A repository with no browser tests gets none written here: say so, and suggest what setting them up would take.

## 2. Pick the journeys

From the issue's acceptance checks: each is something a user does and sees, so group them into the fewest journeys that cover them all, adding the failure states the audit raised.
Before writing one, look for an existing test of the same surface and extend it rather than writing a near-duplicate.
A UI-free change, such as a pure backend or tooling change, has no journey: say so and stop.

## 3. Write each one

- Named by the repository's convention, so the verifier and CI select it when the surface changes.
- A header comment states the invariant the user relies on and the issue ID.
- Sign in through the repository's seeded-login helper, never by hand-rolled requests.
- Find elements the way a user does: by role, label and visible text; a test id only where nothing visible identifies the element.
- Assert on what the user sees, never on implementation, and stub vendors only where the repository's convention does.
- Save a screenshot at each meaningful step.

## 4. Run it

Bring the tree's stack up with `keel stack up`, or the reset form the pack's rules name after a schema change, and run the test through the repository's runner.
- It passes on the change.
- It fails without it: revert the change (or check out the base in a scratch run) and see the expected assertion fail. A journey that passes on the base proves nothing.
- A failure on the first run that passes on the second is flaky: fix the wait or the selector before calling it done.

Look at every screenshot. Visual perfection is the bar: layout, overflow, alignment, empty and error states.
When the issue has an approved mockup, compare each screenshot with its frame, and name every difference that is not a deliberate one the build reported.

## 5. Report

Each journey with its test file, the acceptance checks it covers, the run command, pass and fail evidence, and the screenshots' paths.
Anything not driven, and why. Leave the test uncommitted; `/ship` commits it with the change.

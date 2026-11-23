---
name: verify
description: Verify the current HEAD with a fresh keel-verifier that runs the change rather than reads it, fixing each finding with a failing test first and verifying again until it passes or three rounds fail. Use before a push or PR in a contracted run, when a playbook says /verify, or when asked to verify a change.
---

# Verify the change

The verdict is recorded by the SubagentStop hook from the verifier's own last line, never by this session, so the session that did the work cannot record its own pass.

## 1. Brief a fresh verifier

Spawn a `keel-verifier` (a new one each time, never one resumed) with:

- the goal, from the run's `contract.md` (in the folder `keel run dir` prints), else the task as the user gave it;
- the playbook's acceptance or the issue's acceptance checks;
- the approved mockup's link, when the issue has one.

The verifier gathers the rest itself with `keel verify-brief`: the base, commits, diff stat, done check and the pack's checks, so their output reaches it untouched by this session.
Give it no account of why the change is right.

## 2. Act on the verdict

- `VERDICT: pass`: `keel verdict` now passes, and in a run `keel status --json .` shows `verifier.verdict` as `pass` against this HEAD's tree. Go on.
- `VERDICT: fail`: run `keel verdict`, which says which failed round this is on the branch. Before the third failed round, fix each finding in this session with a test that fails first, as `/write-tests` says, then return to step 1 with a fresh verifier.
- After the third failed round, stop: put the open findings to the user, each with what fixing it would take and a recommendation to fix it, ship with it listed, or file it. In a contracted run, log it with `keel run decide "<findings>" --why "three failed verifier rounds" --evidence "keel verdict" --attention`, then `keel run stop failed --note "<findings>"`.

Any later change to the code needs `/verify` again: the verdict holds only for the tree it judged.

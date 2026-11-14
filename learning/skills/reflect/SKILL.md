---
name: reflect
description: Turn what went wrong in this session or run into proposed edits to keel, each tied to evidence and placed at the strongest level that would have prevented it, held until it happens twice, and applied only on approval. Run only when the user types /reflect.
disable-model-invocation: true
argument-hint: "[run tree path]"
---

# Reflect

Nothing changes in the keel repo or `~/.keel/claude` until the user approves an edit.
Transcripts can hold private material: nothing from them goes anywhere public except the approved edit itself.

## 1. Gather

- This session's transcript, `~/.keel/claude/projects/<slug>/<session id>.jsonl`.
- For a run: its `decisions.tsv`, the rows flagged for attention, and `giveup.md`, in the folder `keel run dir` prints, or its newest archive under `~/.local/state/keel/runs/archive/`.
- The router's "no playbook fits" notes: the one-line task shapes at the end of replies in the transcript.

## 2. Review

Spawn three fresh `keel-agent` reviewers in parallel over the same material, each with one lens and no view of the others:

- **judgment**: where the agent decided wrongly, or asked when it should have decided;
- **structure**: what a hook, guard, test or script would have caught;
- **divergent**: what nobody flagged but cost time.

Each returns findings, each citing the transcript line (`<file>:<line>`) or log row it rests on.

## 3. Synthesize

Spawn one fresh `keel-agent` synthesizer with the three reviews and the material.
It checks every citation against the transcript, drops what it cannot find, merges duplicates, and returns a JSON array, one object per finding:

```json
{"key": "a short stable slug for the class of mistake, such as push-before-tests",
 "finding": "one sentence", "evidence": "<file>:<line>",
 "level": "rails | check | playbook | skill | rule",
 "why_not_stronger": "why each stronger level does not fit; empty only for rails",
 "edit": "the file and the exact change"}
```

The levels, strongest first: `rails` makes it impossible, in rails or git-guard; `check` catches it with a hook, test or check; `playbook` is a playbook step; `skill` a skill line; `rule` a line in `rules/keel.md`, the user's `~/.keel/you/CLAUDE.md` or `OPINIONS.md`, or a pack's `rules.md`.
A "no playbook fits" shape becomes a finding at level `playbook` keyed `playbook:<shape>`.
Reuse a key from `~/.local/state/keel/learning/seen.tsv` when the finding is the same class of mistake, so the twice rule can see it.

## 4. Triage

Pipe the array to `keel reflect triage <session id>`. It applies the twice rule and the ordering in code:

- **Rejected**: no evidence, an unknown level, or no reason the stronger levels do not fit.
- **Held**: seen for the first time; recorded in `seen.tsv` and proposed only when a later `/reflect` sees it again.
- **Accepted**: seen before, strongest level first.

## 5. Approve

Show each Accepted item as the exact diff it would make, with its evidence, its level and why the stronger levels do not fit.
List the Held and Rejected items in one line each. Then stop, and let the user pick which to apply.

## 6. Apply

Apply only the approved edits, in a keel worktree on a branch named for the reflection (`EnterWorktree name=reflect/<date>-<slug>` in the keel repository), uncommitted, ready for `/ship`.
Never edit `~/.keel/claude` directly: every change to keel is reviewed like code.
An edit to a pack's `rules.md` is shown as a diff for the user to apply, until packs move into their repositories.
A change under `method/` or `trust/` needs an eval result before its PR can pass CI: say so, and offer `keel eval <playbook> --variant <the worktree>`.

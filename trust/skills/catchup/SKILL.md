---
name: catchup
description: Catch up on a keel run - what needs your attention, the steps and their results, and what the done check last said - reviewed by a fresh agent with no stake in the work. Read-only. Use when asked to catch up on, summarise or review a run, or after an unattended run ends.
argument-hint: "[tree path]"
---

# Catch up on a run

This changes nothing: no edits, no commits, no run state.

## 1. Gather the trail

For the tree given, else the current one:

- `keel status --json <tree>`: the run, its steps, `attention` and `done_check`.
- The run's folder, which `keel run dir` prints (or, for a run already ended, its newest folder under `~/.local/state/keel/runs/archive/<tree-key>/`): `contract.md`, `decisions.tsv`, `giveup.md` and `resume.md` where they exist.
- The branch's diff and commits against the base: `keel base`, else the default branch.

## 2. Review it with fresh eyes

Spawn a `keel-agent` that did not do the work, with the paths above and this brief: check each decision row against the diff and the evidence it names, and say where a decision looks wrong, a step was skipped without a good reason, or the done check proves less than the goal claims.
Give it no summary of the work. Review what it returns before using it.

## 3. Reply

Open with **Attention**: each row flagged `yes` in `decisions.tsv`, and each problem the review found, one line each, pointing at its log row as `decisions.tsv:<line>`.
Then the steps with their states and results, then what the done check last said, at which HEAD and when.
End with what waits on the user.

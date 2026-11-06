---
name: merge
description: Merge a pull request with the method the user names, squash or commit, once it is ready and GitHub allows it, asking whenever anything is unclear. Use whenever asked to merge a PR, such as "/merge squash" or "merge #123 with a merge commit", and never merge a PR any other way.
argument-hint: "<squash|commit> [PR number]"
---

# Merge a pull request

A merge lands on a shared branch and cannot be taken back without another PR.
The user names the method; `keel merge` checks everything else and merges on the clear path.
Whatever it cannot settle comes back to you, and from you to the user as a question, never a guess.

## 1. Read the ask

- **The method:** `squash` or `commit`, a merge commit. An ask without one, such as "/merge" or "merge #123", is a question: squash or merge commit? No method is ever inferred from the branch, the pack or history.
- **The PR:** the number the ask names, else the open PR for the current branch. Two PRs are two asks.
- When the ask assumes something about the PR, such as calling it a hotfix or naming its target, read it first with `gh pr view <n> --json title,baseRefName,headRefName` and ask if it differs.

## 2. Run it

`keel merge <squash|commit> [n]`, from inside the repository, as a Bash call of its own.
It prints one JSON object and exits:

- **0**: merged, or queued behind a merge queue (`result: "queued"`), which lands only once the queue's checks pass.
- **2**: it merged nothing, and `reason` says why, with every fact it gathered: `pr`, `method`, `checks`, `skips`, `github` and `paired`, as far as it got.
- **1**: the call broke, such as `gh` failing or GitHub refusing the merge; show the error and stop. Never retry with other flags.

## 3. On exit 2, ask

Ask with `AskUserQuestion`, and merge nothing until the answer comes back.
The question says what was found, with the facts from the JSON, and why it stops the merge.
Its options are the concrete ways forward, such as waiting, the other method, or stopping.

What each reason needs:

- **No PR for the current branch**: ask which PR.
- **A check pending**: wait, with `gh pr checks <n> --watch --fail-fast` then `keel merge` again, or stop.
- **A check skipped**: `keel merge` already let through every skip it could explain, by a job's own `if:` or the pack's `skippable` list, so these are the ones it could not. Name each with its `why` from `skips`, and ask whether it can be skipped for this PR. When a check is one that always skips, say that adding its name to the pack's `skippable` file stops the question for good; editing the pack is the user's.
- **A check did not pass**, **conflicts**, **changes requested**, **blocked**, **not open** or **a draft**: report it, with the check's link from `checks`, and stop. Fixing or overriding it is never this skill's.
- **Behind**: updating the branch is a change to it, so ask; never run `gh pr update-branch` on your own.
- **GitHub does not allow the method**, by its settings, a ruleset or required linear history: say which, and offer the other method if it is allowed.
- **Paired**: the head branch has a PR into another branch, listed in `paired`; say which, and ask which lands first.
- **The head moved**: a new push; run `keel merge` again from the top.

An answer covers this one PR and this one question.
When it settles the question, run `keel merge` again with the method the user chose; when the question was the pairing, `gh pr merge <n> --<squash|merge> --match-head-commit <pr.oid>` is the merge, and never `--admin`, `--auto` or `--delete-branch`.

## 4. Report

The PR URL, where it landed (`pr.target`), the method, and the merge commit, or that it is queued.
Name anything the merge did besides land the commits, such as GitHub deleting the branch because `github.settings.deleteBranchOnMerge` is on, or the PR closing a Linear issue.
Then whatever the pack's rules say follows a merge, such as moving the other issues the PR shipped in the tracker.
When a PR is paired with another, name the one still waiting.
It needs its own ask: never merge it on the strength of this one.

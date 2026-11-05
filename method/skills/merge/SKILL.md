---
name: merge
description: Merge one named pull request with the merge method its repository's rules name for the branch it targets, after checking every source of those rules agrees and asking whenever anything is unclear. Use whenever asked to merge a PR, such as "merge #123", and never merge a PR any other way.
argument-hint: "<PR number or URL>"
---

# Merge a pull request

A merge lands on a shared branch and cannot be taken back without another PR, and different branches of one repository can follow different rules.
So a PR merges only when the written rules name one method for this exact target branch and head, nothing contradicts them, and the PR is ready.
`keel merge <n>` checks all of that and merges on the clear path; everything it cannot settle comes back to you, and from you to the user as a question, never a guess.

## 1. Check the ask

- The ask names exactly one PR. "Merge it" on a branch with an open PR is a question, offering that PR by number and title; two PRs are two asks.
- When the ask assumes something about the PR, such as calling it a hotfix or naming its target, read it first with `gh pr view <n> --json title,baseRefName,headRefName` and ask if it differs.

## 2. Run it

`keel merge <n>`, from inside the repository, as a Bash call of its own.
It prints one JSON object and exits:

- **0**: merged, or queued behind a merge queue (`result: "queued"`), which lands only once the queue's checks pass.
- **2**: it merged nothing, and `reason` says why, with every fact it gathered: `pr`, `rule`, `github`, `paired`, `history` and `checks`, as far as it got.
- **1**: the call broke, such as `gh` failing or GitHub refusing the merge; show the error and stop. Never retry with other flags.

The rule it reads is the pack's `merge` file, one `<target> <head glob> <method>` per line, the first line matching both winning, with the method `squash`, `merge`, `rebase`, or `ask` for a merge a rule puts a condition on.

## 3. On exit 2, ask

Ask with `AskUserQuestion`, and merge nothing until the answer comes back.
The question says what was found, with the source for each claim from the JSON, and why it stops the merge.
Its options are the concrete ways forward, with the one the evidence supports first and marked "(Recommended)".
Recommend only from what a rule says; history alone never makes a recommendation.

What each reason needs:

- **No rule for target**, or a rule that says **ask**: read the pack's `rules.md` in full (`keel pack` prints its directory), and the repository's `CLAUDE.md`, `CONTRIBUTING.md` and docs on merges, for what they say about this target and this kind of PR, and offer each method a source allows. A condition, such as a paired PR, an order, or a person who must have looked, goes in the question.
- **Settings, a ruleset or linear history disallow the rule's method**: the sources disagree; offer the methods GitHub allows, and fixing the rule.
- **Paired**: the head branch has a PR into another branch, listed in `paired`; say which, and what the rules say about the order.
- **Earlier PRs did not land as the method**: list them from `history`; the rule may have changed, or be wrong.
- **A check skipped**: a conditional job that did not run; name it from `checks`, and ask whether it can be skipped for this PR.
- **gh's repository is not origin**: `gh repo set-default` points elsewhere; say which, and stop.
- **A check pending**: wait, with `gh pr checks <n> --watch --fail-fast` then `keel merge <n>` again, or stop.
- **A check did not pass**, **conflicts**, **changes requested**, **blocked** or **a draft**: report it, with the check's link from `checks`, and stop. Fixing or overriding it is never this skill's.
- **Behind**: updating the branch is a change to it, so ask; never run `gh pr update-branch` on your own.
- **The head moved**: a new push; run `keel merge <n>` again from the top.

An answer covers this one PR and this one question: the next PR, or a new question on this one, asks again.
`keel merge` checks the PR is ready before it reads any rule, so a question about the rule, the settings, a pairing or the history is about a PR that could merge at `pr.oid`.
When the answer to such a question names a method, merge with `gh pr merge <n> --<method> --match-head-commit <pr.oid>`, which GitHub refuses if anything was pushed since, and never `--admin`, `--auto` or `--delete-branch`.
When the answer changes a rule for good, the edit to the pack's `merge` file is the user's to make or approve.

## 4. Report

The PR URL, the method and the rule line that named it (`rule.source`), and the merge commit, or that it is queued.
Name anything the merge did besides land the commits, such as GitHub deleting the branch because `github.settings.deleteBranchOnMerge` is on, or the PR closing a Linear issue.
Then whatever the pack's rules say follows a merge, such as moving the other issues the PR shipped in the tracker.
When a rule pairs this merge with another, such as a hotfix that goes into two branches, name the PR still waiting.
It needs its own ask: never merge it on the strength of this one.

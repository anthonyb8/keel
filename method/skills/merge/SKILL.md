---
name: merge
description: Merge one named pull request with the merge method its repository's rules name for the branch it targets, after checking every source of those rules agrees and asking whenever anything is unclear. Use whenever asked to merge a PR, such as "merge #123", and never merge a PR any other way.
argument-hint: "<PR number or URL>"
---

# Merge a pull request

A merge lands on a shared branch and cannot be taken back without another PR, and different branches of one repository can follow different rules.
So this skill merges only when the written rules name one method for this exact target branch, nothing contradicts them, and the PR is ready.
Anything else is a question for the user, never a guess.

## When to ask

Ask with `AskUserQuestion` the moment any of these holds, and merge nothing until the answer comes back:

- The ask names no PR, or names more than one. One ask covers one PR: "merge it" on a branch with an open PR is a question, offering that PR by number and title.
- No written rule names a method for this target branch. A rule for the base does not cover a release branch, and a rule for a hotfix into `staging` does not cover a promotion into it.
- Two sources disagree, such as the pack naming squash where GitHub allows only merge commits.
- A rule attaches a condition to merging into this branch, such as a paired PR, an order, or a person who must have looked, and you cannot confirm it holds.
- The PR is not ready, by any check in step 3.
- What you found differs from what the user's ask assumed, such as a PR they called a hotfix that targets `development`.
- Anything else leaves you less than sure. When in doubt, ask.

Each question says what you found, with the source for each claim, and why it stops you.
Its options are the concrete ways forward, such as each method a source allows, waiting, or stopping, with the one the evidence supports first and marked "(Recommended)".
Recommend only from what a rule says; history alone never makes a recommendation.
An answer covers this one PR and this one question: the next PR, or a new question on this one, asks again.

## 1. Read the PR

```sh
gh pr view <n> --json number,title,url,state,isDraft,baseRefName,headRefName,headRefOid,isCrossRepository,mergeable,mergeStateStatus,reviewDecision,author
```

Stop and report if it is already merged or closed.
Note the target branch, `baseRefName`: every rule below is looked up for that branch, not for the base this session started from.
Note `headRefOid`: the merge in step 5 is pinned to it.

## 2. Find the rule for this target branch

Gather every source before deciding, and keep a line per source of what it says about this target branch.

1. **The pack.** `keel pack` prints the pack's directory; read `rules.md` there in full, not the copy in your context, which may be stale after a compaction.
   `keel base` is the branch work targets, and `keel protected` the branches no session may move.
   Look for a merge method named for this target branch, and for any condition on merging into it.
2. **The repository.** Its own `CLAUDE.md`, `CONTRIBUTING.md`, and anything under `docs/` that names merges, such as `grep -rniE 'squash|merge commit|rebase and merge|merge method' --include='*.md' .`, including ADRs on the branching model.
3. **GitHub's settings**, read-only:
   - `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge`
   - `gh api 'repos/{owner}/{repo}/rules/branches/<target>'`: a `pull_request` rule's `allowed_merge_methods` narrows the repository's, and a `merge_queue` rule means the merge goes through a queue.
   - `gh api 'repos/{owner}/{repo}/branches/<target>/protection'`, which returns 404 when there is no classic protection; note whether it requires linear history, which rules out a merge commit.
4. **History**, as evidence only: how the last few PRs into this target landed.
   `gh pr list --base <target> --state merged --limit 10 --json number,title,mergeCommit`, then `git cat-file -p <oid>` on each after a `git fetch origin <target>`: two parents is a merge commit, one is a squash or rebase.

Decide:

- **Clear:** a written source, the pack or the repository, names exactly one method for this target branch, GitHub allows it, and no written source says otherwise.
  History that disagrees still goes to the user as a question, since it may mean the rule changed or the rule is wrong.
- **Anything else is unclear:** ask, as above.

GitHub's names map to `gh` flags as: "Squash and merge" `--squash`, "Create a merge commit" `--merge`, "Rebase and merge" `--rebase`.

## 3. Check the PR is ready

- **Draft:** stop and report; marking it ready is the user's call.
- **Checks:** `gh pr checks <n> --json name,bucket,event,workflow,link`. Every check must have passed, required or not.
  A pending check is a question: wait, or stop. Waiting is `gh pr checks <n> --watch --fail-fast`, then these checks again.
  A failed or cancelled check stops the merge; report it with its link.
  A skipped check counts as passed when its workflow skipped it on purpose for this PR, which you show from the workflow file the run used: for a `pull_request` event the merge ref, `git fetch origin pull/<n>/merge` then `git show FETCH_HEAD:.github/workflows/<file>`; for `pull_request_target` the target branch's copy. On purpose means:
  - the job's own `if:` is false for this PR, worked out from the PR's own facts alone: its event, target and head branch, labels, author and draft state. `if: github.base_ref == 'main'` on a PR into `development` is one.
  - or every job it `needs:` was itself skipped that way.

  Any other skip is a question: an `if:` that reads `needs`, `vars`, `inputs` or a status function such as `failure()`, a job you cannot find in the workflow file, or a skip with no `if:` behind it.
  Never ask about a skip you explained; step 4 records it.
- **Merge state**, `mergeStateStatus`:
  - `CLEAN`, or `HAS_HOOKS`: ready.
  - `BEHIND`: the target has moved on and the branch must catch up. Updating it is a change to the branch, so ask; never run `gh pr update-branch` on your own.
  - `DIRTY` or `mergeable: CONFLICTING`: stop and report the conflict.
  - `BLOCKED`: something GitHub requires is missing, such as a review. Report what; never get around it.
  - `UNSTABLE`, `UNKNOWN`, or anything else: ask.
- **Reviews:** a `CHANGES_REQUESTED` decision stops the merge, even where no review is required.
- **Head unchanged:** if anything above took time, read `headRefOid` again; a new head means a new push, so start over from step 1.

## 4. Say what you will do

Before merging, show one short block:

- the PR, its title, and `head -> target`
- the method, and the source line that names it
- each other source and what it said
- the checks and merge state, with each skipped check and the `if:` line, file and line number that skipped it, or the skipped job it `needs:`
- anything the merge will do besides land the commits, such as GitHub deleting the branch because `deleteBranchOnMerge` is on, or the PR closing a Linear issue

When everything was clear this is a record, not a question, and you go on to step 5.
If writing it shows you anything you had not weighed, it is a question after all.

## 5. Merge

```sh
gh pr merge <n> --<method> --match-head-commit <headRefOid>
```

- `--match-head-commit` makes GitHub refuse the merge if anything was pushed since you checked.
- Leave the commit title and body to GitHub's defaults unless a rule says how to write them.
- Never `--admin`, `--auto` or `--delete-branch`, and never merge with `git merge` and a push instead.
- Behind a merge queue the command queues the PR rather than merging it: say so, and that it lands only once the queue's checks pass.
- On a refusal, stop and show it; do not retry with other flags.

## 6. Confirm and report

`gh pr view <n> --json state,mergedAt,mergeCommit,baseRefName`, and confirm it is `MERGED` into the target you checked.

Report the PR URL, the method and the rule that named it, and the merge commit.
Then whatever the pack's rules say follows a merge, such as moving the other issues the PR shipped in the tracker.
When a rule pairs this merge with another, such as a hotfix that goes into two branches, name the PR still waiting.
It needs its own ask: never merge it on the strength of this one.

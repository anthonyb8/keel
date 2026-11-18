---
name: ship
description: Commit, verify, push and open a pull request for the current branch. Run only when the user invokes /ship.
disable-model-invocation: true
argument-hint: "[commit | push | pr] [skip-verify]"
---

# Ship the current branch

Invoking `/ship` is the explicit ask the Git rules require, for exactly the steps it names and once each:

| Invocation | Steps |
|---|---|
| `/ship commit` | check, commit |
| `/ship push` | check, commit, verify, push |
| `/ship` or `/ship pr` | check, commit, verify, push, open the PR |

It covers this one run.
The next change needs its own `/ship`.
`skip-verify` after the step, or the user saying to skip verifying in the same ask, drops the verify step for this run only.

Read `~/.keel/claude/VOICE.md` before writing the commit message or the PR body.

`keel ship` does the fixed steps: it refuses a protected branch, commits exactly the files named, gates a push on `keel verdict` passing for HEAD, pushes to the branch's own name, and opens the PR into the base, each git and gh command checked by git-guard first.
It exits 0 with what it did, 2 with a reason and the facts when it hands the step back, or 1 when something broke.
Your part is the message, the body, the checks and `/verify`.

## 1. Check

Run the checks the repository's own `CLAUDE.md` requires before finishing, unless they already passed on the current state of the tree.
Stop on a failure and report it.

## 2. Commit

Write the message to a file under the job's temp directory: a headline prefixed with the issue ID from the branch name where the project uses one, or with the issue being built in a project build, then a body of two or three sentences on why, in VOICE.md's style, with no co-author or agent attribution line.
Then `keel ship commit --files <every file this work touched> --message <file>`, naming each file, never a directory.
For `/ship push` or `/ship pr`, give the same `--files` and `--message` to that call instead, as step 3 says; with nothing left to commit, call it without them.

## 3. Verify and push

Every push is verified, in every repository, unless the user skipped it for this run, or the commits being pushed change only descriptive docs, such as a README or files under `docs/`, with nothing a verifier could run.
Rules, skills, playbooks and prompts change behaviour: they are verified.

Call `keel ship push`, or `keel ship pr` for a PR, with `--files` and `--message` when the push should carry a commit; it commits first.
Without a passing verdict for HEAD it exits 2 having pushed nothing: run `/verify` on what it committed, then call it again without `--files`.
A skip is `--skip-verify "<why>"`, which the output names; a contracted run cannot skip.

## 4. Open the PR

Fill the project's PR template as VOICE.md describes, adding nothing to it, and write it to a file under the job's temp directory; in a project build, the title names the project and the body names every issue the branch built, each with its commit.
`keel ship pr --title "<headline>" --body <file>` pushes and opens it, as a draft in a contracted run.
When the branch already has an open PR into the base it pushes and prints that PR's URL, and editing its title or body is a separate ask.
Never merge, approve or retarget a PR, and leave labels and reviewers alone.

## 5. Report

The commit SHA, the verdict or the skip as `keel ship` printed it, and the PR URL.
Leave the issue tracker's state alone: moving an issue past In Progress is the user's call.

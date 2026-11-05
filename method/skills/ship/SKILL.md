---
name: ship
description: Commit, verify, push and open a pull request for the current branch. Run only when the user invokes /ship.
disable-model-invocation: true
argument-hint: "[commit | push | pr]"
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

Read `~/.keel/claude/VOICE.md` before writing the commit message or the PR body.

## 1. Check where you are

- The base is `keel base`, or the repository's default branch when that prints nothing.
- Stop if the current branch is the base, the default branch, or a release branch the pack names: nothing ships from a protected branch.
- Run the checks the repository's own `CLAUDE.md` requires before finishing, unless they already passed on the current state of the tree.
  Stop on a failure and report it.

## 2. Commit

- `git status`, then `git add` exactly the files this work touched, never `-A` or `.`.
- One commit: a headline prefixed with the issue ID from the branch name where the project uses one, then a body of two or three sentences on why, in VOICE.md's style.
- No co-author or agent attribution line.
- Never amend, squash or rewrite an existing commit.
- With nothing to commit but commits not yet on `origin`, go on to verify.

## 3. Verify

When the owning pack's rules say to gate or verify before a push, run `/verify`.
Push only once it passes; on a failure stop and report what it found.

## 4. Push

`git push -u origin HEAD:<branch>`, to the branch's own name.
Never force-push, never push to a protected branch.

## 5. Open the PR

- If `gh pr view` finds one for this branch already, stop at the push and give its URL: editing a PR's title or body is a separate ask.
- Fill the project's PR template as VOICE.md describes, adding nothing to it, and write it to a file under the job's temp directory.
- `gh pr create --base <base> --head <branch> --title "<headline>" --body-file <file>`.
- Never merge, approve or retarget it, and leave labels and reviewers alone.

## 6. Report

The commit SHA, what the verifier said, and the PR URL.
Leave the issue tracker's state alone: moving an issue past In Progress is the user's call.

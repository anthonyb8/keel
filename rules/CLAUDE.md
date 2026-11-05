# Global rules

These hold in every repository.
A pack's rules, injected at session start, add to them and win where the two disagree.

## General

- Never use the em dash "—"; use a plain dash "-".
- Never hand-edit CHANGELOG.md or a file marked auto-generated.
- In long Markdown files, put each sentence on its own line.
- Weigh quality, simplicity, robustness and long-term maintainability over development cost.
- A bug fix starts with an end-to-end test that reproduces the bug the way a user hits it.
- When testing a UI end to end, be picky: visual perfection is the bar.
- Name the real type, never `any`, `Any`, `interface{}`, `Object`, `void *` or a missing annotation, whatever the surrounding code does.
  If it truly cannot be named, say why in a comment.
- Scope a task from my words, not from the tree, branch or uncommitted work the session started in.
- Keep the diff to the ask. Report anything else you find broken; do not fix it.
- When I ask for steps or commands I will run myself, give them in text. Plan approval is for changes you make.
- Never call a public link or deployed page working on server-side checks alone: say what you checked, and treat it as unconfirmed until a real browser has been through the flow.

## Running things

- Stop every long-running process you started before you finish, by its PID, never a broad `pkill`, and confirm its port is free.
  Leave up only what I asked for, and shared local databases such as `supabase start`.

## Git

Commit, push and open a PR only on an explicit ask in my message ("commit this", "push it", "open the PR").
These commands are allowlisted, so this rule is the only gate.
Each ask covers one commit, push or PR, and an ask to commit is not an ask to push.
Finishing, passing checks, an earlier approval, or a skill or doc saying to commit is not an ask.
If unsure, I did not ask: leave the change in the tree and tell me which files changed and the command to commit them.

- The base is the pack's, else the default branch. The base, the default branch and any release branch the pack names are protected.
- Commit only on a feature branch. `git add` exactly the files touched, never `-A` or `.`. A headline and a two-to-three sentence body as VOICE.md describes, with no co-author line. Never amend or squash a commit, or rewrite one other than by the rebase below.
- Merge, rebase, cherry-pick and revert on a feature branch only, never on a protected one. Rebase only commits not yet pushed, since rewriting pushed ones needs a force-push.
- Push only a feature branch, to its own name: `git push -u origin HEAD:<branch>`. Never force-push, push to a protected branch, or delete a remote branch.
- Open a PR only into the base, filled from the project's template as VOICE.md describes. Edit only its title or body, when asked. Merge a PR only on an explicit ask in my message naming it ("merge #123"), one PR per ask, once its checks pass, with the merge method the pack names for its base (`gh pr merge <n> --squash` or `--merge`); never `--admin`, `--auto` or deleting the branch. Never close, approve or retarget a PR, or change its base, labels, reviewers or assignees.
- Every other git state change is mine: reset, checkout or switch beyond what `EnterWorktree` does, stash, branch deletion, tag, config, and any other `gh` command that modifies something.
  Never route around this with `bash -c`, scripts, aliases or `gh api`.

Read-only git is encouraged.

## Worktrees

- Reading, searching and answering questions run in place.
  Before changing a file or running anything that writes, such as a build, tests or a dev server, take a worktree with `EnterWorktree`, named for the branch: a provisioned pool tree off the base.
  Never `git worktree add` by hand; it skips provisioning.
- One session per tree. Two sessions in one tree overwrite each other's uncommitted files, which looks like corruption: files vanishing, a `git status` full of strangers' changes, HEAD moving. Stop on sight rather than working around it.
- Work touching a single-instance local service, such as a database on fixed ports, runs serially even across independent trees.
- Name sessions issue ID first, then a short slug: `claude --name "ABC-123 short slug"`. A subagent puts the same label at the front of its description.
- Launching further top-level agents (`claude --bg`) is mine to ask for.

## Memory

Memory holds short-lived state only, and each note says when it stops being true.
A lesson that should hold next time is a proposed edit to this file, `OPINIONS.md`, or the pack's `rules.md`, never a memory.
Delete a note once it expires or is promoted.

## Opinions and voice

- When a technical decision would benefit from my viewpoint, read `~/.keel/claude/OPINIONS.md` first.
- Before writing anything in my name - commits, PRs, issues, review comments, docs, email, chat - read `~/.keel/claude/VOICE.md`.

# keel

The setup every Claude session runs in: enforced rails, one front door that picks a playbook for the task, and a trust layer that lets an agent be left alone with a task and trusted with what it brings back.

keel is built beside [harness](https://github.com/anthonyb8/harness) and replaces it once it reaches parity.
Until then it never writes a harness path: a keel session runs through `keel claude`, on its own config dir, and a plain `claude` stays exactly as it was.

## Install

```sh
git clone git@github.com:anthonyb8/keel.git ~/keel
~/keel/install.sh            # link keel's files into ~/.keel/claude and ~/.local/bin/keel
~/keel/install.sh --check    # report drift without changing anything
keel claude                  # then /login once in this session
```

`rails/shell/keel.zsh` defines `th`, `thr`, `tt` and `ttr` on keel; source it only at the switch, since harness's shell defines the same names.

Requires `claude`, `treehouse`, `jq` and `git`.

`keel claude` runs `claude` with `CLAUDE_CONFIG_DIR=~/.keel/claude`.
Its login, transcripts, memory, plugins and background jobs live there, apart from harness's.
The variable is set by `keel claude` alone, never in the shell or a settings file.

## What it does

- **Router.** Every keel session gets a short router at session start: the first reply to a task restates the goal, names the playbook it matched (or says no playbook fits), and opens the todo list with that playbook's steps word for word, a skipped step staying on the list as `skip: <reason>`.
  `/keel <task>` forces a fresh match. Playbooks live in `method/playbooks/`, indexed in its `README.md`; subagents get no router and follow their brief.
- **Skills.** `/pickup ABC-123` runs the `issue` playbook through the ported chain: `/audit-issue`, `/mockup` for a UI change, `/implement`, `/audit-code` in a fresh `keel-agent`, `/write-tests`, `/audit-tests` in a fresh `keel-agent`, `/e2e`, then `/ship` and `/merge` on the user's ask. `/spec` files issues from `keel template issue` or `keel template project`, a pack's template winning by name.
- **Runs.** Every task a playbook routes is a run, recorded outside the tree under `~/.local/state/keel/runs/`. `keel status --json` lists them from files alone, fast enough to poll; [docs/status.md](docs/status.md) is the schema treetop reads.
  While a run is active or paused, sweep, SubagentStop and WorktreeRemove keep its tree; a run whose session died shows as `stale` and is cleared only by hand, with `keel run stop stopped --tree <path>`.
- **Contracts.** A run started with `--contract` (template: `trust/contract.md`) is held by the Stop hook: the session cannot end its turn until the contract's `done:` command passes, it writes `giveup.md`, or its `budget:` is spent. Decisions go to the run's `decisions.tsv`, and what needs the user is counted as Attention; `/catchup` reviews the trail read-only.
- **Grants.** Inside a contracted run, git-guard allows only what the contract's `grants:` cover (`commit`, `push`, `draft-pr`), each in one narrow form, and a push or draft PR only once a fresh `keel-verifier` (`/verify`) has passed on that exact tree. Merging is never done from a run.
- **Reflect.** `/reflect` turns a session's or run's mistakes into proposed edits, each tied to evidence and placed at the strongest level that would have prevented it (rails, check, playbook, skill, rule). A finding seen once is held in the private `~/.local/state/keel/learning/seen.tsv`; it is proposed only when seen again, and applied only on approval, in a keel worktree.
- **Evals.** `keel eval <playbook> --variant <checkout>` runs the playbook's canned task on the installed keel and the variant, scores every result with scripted checks and one blind judge, and writes a result under `learning/evals/results/`. CI fails a PR that changes `method/` or `trust/` without a result for each playbook it reaches.
- **Trees.** In a keel session, `EnterWorktree`, `claude --worktree` and subagents with worktree isolation lease a pool tree from treehouse, on a named branch off the pack's base.
  keel holds its trees as `keel:<branch>` and `keel:agent-<id>`, harness as `claude:...`, so neither system's sweep or stop hook ever returns the other's tree.
  A subagent's empty tree goes back to the pool when it stops; `keel sweep --apply` catches the rest, except trees listed in `~/.config/keel/keep`.
- **Packs.** keel reads harness's packs from `~/.config/harness/packs` (or `$KEEL_PACKS`), read-only, until packs move into their repositories.
  A session in a repository a pack owns gets the pack's rules, with a note that where they name `harness <verb>`, the session runs `keel <verb>`.
- **Stacks.** `keel stack up` starts the tree's stack through the pack's `stack` script and prints its URL once it serves; `keel stack down` stops it.
  `keel e2e` runs browser tests against it from a container on no network but the stack's ports.
  keel's stack state lives in the tree's git dir as `keel-stack`, apart from harness's.
- **git-guard.** A `PreToolUse` hook refuses any merge, rebase, cherry-pick or revert that would move a protected branch: the pack's base, the default branch and the pack's `protected` list, as `keel protected` prints them.
  What it cannot place, such as a git call inside `bash -c`, it refuses rather than guesses.
- **Linear.** `keel linear` reaches any Linear workspace over its API: `team`, `get`, `search`, `create`, `update`, `comment`, `relate` and `project`.
  The repository picks the workspace through `~/.config/keel/linear`, one line per origin glob: `*github.com[/:]anthonyb8/* ANB LINEAR_API_KEY_PERSONAL`, meaning the team key and the env var holding that workspace's key.
  A pack's `linear` file still names the team for the repositories it owns. The key is sent in a header file, never on a command line, and never printed.
- **Merges.** `/merge squash` or `/merge commit`, with an optional PR number, runs `keel merge <squash|commit> [n]`: it merges the PR, else the current branch's, with that method once the PR is ready, GitHub allows the method, and no PR from the same head goes elsewhere.
  A skipped check counts as passed, as GitHub counts a skipped required check.
  Anything else exits 2 with the reason and every fact it gathered, and `/merge` takes it to the user. git-guard refuses it inside a run.

## The four layers

- **Rails** keep a session inside the lines whatever it decides: permission lists, trees and git-guard.
- **Method** picks how a task is done: one front door that routes to a playbook, and the skills those playbooks run.
- **Trust** lets a run be left alone: a contract, a done check, a decision log and an independent verifier.
- **Learning** turns what a session taught into edits to the rules, held to a blind eval.

`rules/` holds the rules every session loads, beneath all four.

## Layout

Each directory is created by the row that first puts something in it.

```
rules/       CLAUDE.md, OPINIONS.md, VOICE.md
rails/       bin/keel, settings.json and its hooks, lib/ (git-guard.py, sockrelay.mjs), shell/keel.zsh
method/      router.md, playbooks/, skills/ and agents/keel-agent.md, linked into ~/.keel
trust/       the contract, its hooks and skills
learning/    skills/reflect, eval.sh, evals/<playbook>/ and their results
templates/   issue and project templates, for keel template
docs/        status.md, the run schema; how each part works
tests/       run.sh for the logic, against a throwaway HOME
```

## Tests

```sh
tests/run.sh          # the logic, against throwaway repos, pools, packs and a stub Linear under a throwaway HOME; no Claude calls
tests/sessions.sh     # real Haiku sessions through the hooks and the router; needs keel's /login, run by hand
tests/linear-live.sh  # read-only checks against the real Linear workspaces; needs both API keys, kept out of CI
```

CI runs shellcheck and `tests/run.sh` on every pull request.

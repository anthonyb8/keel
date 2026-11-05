# keel status

`keel status --json [path]` prints every run on the machine not yet archived, or the one for `path`, as a JSON array.
It is the one seam treetop reads, so it reads files only, never git or treehouse, and is fast enough to poll.

## Where runs live

Each run is `~/.local/state/keel/runs/<tree-key>/status.json`, outside the tree, so a run never shows as work in it.
`<tree-key>` is the tree's absolute path with every `/` and `.` turned into `-`, as Claude Code names its project folders.
Join a run to a tree by its `tree` field, not by the key.
Writes go to a temporary file in the same folder and are then renamed, so a reader never sees half a file.
An ended run moves to `runs/archive/<tree-key>/<started_at>/` and is no longer listed.

## Schema, version 1

Fields are only ever added, never renamed or removed, and a new field never changes the meaning of an old one.
A change that would break a reader bumps `version`.

| Field | Type | Meaning |
|---|---|---|
| `version` | number | `1` |
| `tree` | string | the tree's absolute path, its git toplevel |
| `branch` | string | the branch the run started on, empty when detached |
| `playbook` | string | the playbook the router matched, such as `bug-fix` |
| `goal` | string | the goal as the router restated it |
| `state` | string | `active`, `paused`, `done`, `stopped` or `failed`; a run that stopped or failed on its own, by giving up or by its budget, stays listed until `keel run stop` archives it |
| `reason` | string | set when a run ended on its own: `gave up` or `budget` |
| `steps` | array | the playbook's steps, each `{title, state, reason}`, with `state` one of `pending`, `doing`, `done` or `skipped`, and `reason` set only on a skipped step |
| `current` | number or null | the 1-based step being worked on, else the first one still open, else null |
| `started_at`, `updated_at` | string | UTC, `YYYY-MM-DDTHH:MM:SSZ` |
| `stale` | boolean | an active run whose tree had no live process at the last `keel sweep` |
| `attention` | number | the count of rows in the run's `decisions.tsv` flagged for attention |
| `done_check` | object or null | the last done check the Stop hook ran: `{exit, passed, head, at, tail}`, with `tail` the output's last 40 lines |
| `contract_hash` | string or null | the sha256 of the run's `contract.md` when it started; null for a run with no contract |
| `verifier` | object or null | the last `keel-verifier`'s verdict, recorded by the SubagentStop hook: `{verdict, tree, at, findings}`, with `tree` the `HEAD^{tree}` it judged |
| `gate` | object or null | the last `keel gate` verdict in the run: `{verdict, tree, at, run_id}` |

An archived run also has `ended_at` and `note`.

## Commands

- `keel run start --playbook <name> --goal <text> --steps <file> [--replace]` starts a run in the current tree. It refuses when an active or paused run holds the tree, unless `--replace`, which archives the old one as `stopped`.
- `keel run step <n> doing|done|skip <reason>` moves a step on, and resumes a paused run.
- `keel run pause` pauses the run; a resume note on stdin is kept in its folder as `resume.md`.
- `keel run stop done|stopped|failed [--note <text>] [--tree <path>]` ends the run and archives it.

## What a run holds

While a run is active or paused, `keel sweep`, SubagentStop and WorktreeRemove keep its tree, saying `kept <path>: run <playbook> <state> at step <n>`.
A stale run is listed by `keel sweep` and never cleared by it: `keel run stop stopped --tree <path>` clears it by hand.

## Contracts and the decision log

A run started with `--contract <file>` copies the contract into its folder and records its hash; `trust/contract.md` is the template.
The Stop hook runs the contract's `done:` command when the session tries to end its turn, and blocks the turn until it passes, `giveup.md` exists in the run's folder, or the `budget:` is spent.
A contract changed since the run started blocks the turn, and its command is never run.

`decisions.tsv` in the run's folder has one row per decision, tab-separated: time, step, decision, why, evidence, result, and `yes` when it is flagged for attention.
Failed done checks, skipped steps, a changed contract, a spent budget and a give-up are flagged on their own; `keel run decide ... --attention` flags the agent's own.

## Grants

In a tree with an active contracted run, git-guard holds commits, pushes and PRs to the contract's `grants:`.
`commit` allows `git commit` on the run's branch (never `--amend`), and `git commit-tree` and `git update-ref refs/heads/<run branch>`.
`push` allows only `git push -u origin HEAD:<run branch>`, never forced, never a protected branch.
`draft-pr` allows only `gh pr create --draft --base <the base>`.
A push or PR also needs a passing `verifier` and `gate` recorded against the `HEAD^{tree}` being sent, so a fold that leaves the tree unchanged keeps both, and any code change needs both again.
`gh pr merge`, `ready`, `close` and `reopen`, retargeting a PR, and deleting a branch or tag are refused in a run whatever the grants.
Each refusal is logged to `decisions.tsv`, flagged for attention.

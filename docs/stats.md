# keel stats

`keel stats` answers which skills run most, which take longest, which get rerun, and which model did the work, so you can see where to tune a skill, script a step or try another model.
It reads local files only and never copies message text into its output: counts, run goals and step titles.

```sh
keel stats                          # a table of skills, most run first
keel stats --json                   # everything below, as one JSON object
keel stats --json --since 2026-11-10 --repo app
```

`--since` leaves out runs started before that day, with everything they did, even on later days; a verifier outside a run counts by its own day.
`--repo` keeps only trees, and sessions, whose path has that name as one of its parts, such as `app` for `~/.treehouse/app-359d95/13/app`.

## Where it reads from

- Runs, live and archived, under `~/.local/state/keel/runs/` ([status.md](status.md)), with each run's `decisions.tsv`.
- Verdicts outside runs, from `~/.local/state/keel/verdicts.jsonl`, and script events from `~/.local/state/keel/events.jsonl`.
- Claude Code's transcripts under `~/.keel/claude/projects/`, with each session's `subagents/` folder and its `.meta.json` files.
- The playbooks under `method/playbooks/`, for the text of each step.

Each transcript's totals are cached under `~/.local/state/keel/stats-cache/`, keyed by the size and mtime of the transcript and its subagents' files, so a second run reads only sessions that changed.

## How it counts

- **A skill** is the first `/name` in a playbook step's text, since a step that runs a skill names it, such as `/audit-issue`.
  A step that names none counts as `<playbook> step <n>`, the time before step 1 as `router`, and each `keel-verifier` spawn as `verify`; a step naming `/verify` counts as its playbook's own step, so `verify` holds verifier spawns alone.
  Step texts come from the playbook files as they are now, so a run that followed an older version is named by the current one.
- **A run of a skill** is a run entering the step that runs it, found from the `keel run start` and `keel run step <n> doing` calls in the transcript that ran. A start counts only when a run folder for its playbook began while the call ran, so a start keel refused, or text that only mentions one, counts nothing; a call the user denied or a hook refused never ran. A compound command that failed on another part still moved the run.
- **Agent time** is the gaps between a session's messages while the step is current, leaving out gaps over 30 minutes as idle.
  **Waiting** is the gap before each message the user typed.
  A verifier's time is its own first-to-last message.
- **Tokens** are summed once per assistant message id: input, cache writes, cache reads and output.
  A subagent's tokens count toward the step its first message falls in.
- **A rerun** is a step entered again after another step was started in the same run.
- **A damaged file never stops it.** A value of the wrong type in any file it reads is left out, and a transcript line it cannot read is counted in `unread`.

## Output, version 1

Fields are only ever added, never renamed or removed; a change that would break a reader bumps `version`.

| Field | Meaning |
|---|---|
| `version` | `1` |
| `since`, `repo` | the filters given, or null |
| `skills[]` | `{name, where, runs, calls, agent_s, wait_s, tokens: {session, subagents}, models: {<model>: tokens}, subagents: {<agent type>: count}, reruns}`, most run first; `where` lists the `<playbook> <step>` places it ran from; `verify` adds `verify_rounds: {<rounds>: runs}`, how many verifiers each run spawned |
| `playbooks[]` | `{name, runs, states: {<state>: runs}, median_minutes, versions, steps[]}`, with `versions` the number of playbook hashes its runs followed, and each step `{n, title, skill, done, skipped, open, skip_codes: {<code>: runs}, attempts, rerun_runs, attempt_s}` from the runs' status files, with `attempt_s` the wall time of its closed attempts, waits included |
| `scripts[]` | `{cmd, calls, exits: {<code>: calls}, handed_back: [[reason, calls]], median_ms}` from `events.jsonl`, with the five commonest exit-2 reasons |
| `verifier` | `{verified_runs, first_pass, rounds_to_pass: {<rounds>: runs}}`, from the verifier rows in each run's `decisions.tsv` |
| `days[]` | `{day, runs, pass, fail}` per day: runs started, and verdicts in runs and outside them |
| `transcripts` | `{read, cached}`: sessions read this time, and taken from the cache |
| `unread` | `{lines, unread, share}`: transcript lines it could not read, being not JSON, or with a timestamp lacking its offset or token counts that are not whole numbers; it skips them while counting the rest |

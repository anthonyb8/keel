# keel stats

`keel stats` answers which skills run most, which take longest, which get rerun, and which model did the work, so you can see where to tune a skill, script a step or try another model.
It reads local files only and never copies message text into its output: counts, run goals and step titles.

```sh
keel stats                          # a table of skills, most run first
keel stats --json                   # everything below, as one JSON object
keel stats --json --since 2026-11-10 --repo app
```

`keel dash`, with the same options, writes the same numbers into one page, `~/.local/state/keel/dash.html`, and opens it.
On a server with a laptop connected through [tether](https://github.com/anthonyb8/tether), it serves the page once on `127.0.0.1` and opens `http://localhost:<port>/` in the laptop's tether browser with `tether open`; the server stops after the page loads, or after two minutes if it never does, so nothing is left running.
Without a tethered laptop it uses `xdg-open` or `open`, and with neither, or when one fails, it prints the path or URL to open by hand.
The page needs no server and no network, follows the system's light or dark setting, and opens a view straight from `#overview`, `#skills` or `#scripts`.
Playbooks lists every playbook in `method/playbooks/`, those with no runs in range greyed, and lays the chosen one out step by step: what started its runs, each step's done and skipped counts, its agent time, tokens and turns per run, and the chosen step's text.
Skills lists every skill installed in `~/.keel/claude/skills/`, each tagged with how it mostly runs (a playbook step, typed by you, called by the agent, the verifier or the router); those not run in range sit greyed below the rest, and "Run in range" hides them.
The header carries the keel galley, which is also the page's icon, and names `--since` or `--repo` beside the title when either is given.
On Skills, picking a row shows what it says under the table: a skill's `SKILL.md` from `~/.keel/claude/skills/`, a step's line from its playbook, or `method/router.md` for the router, each read when the page is written.
The text is rendered from Markdown as text only, so a skill's text cannot run on the page; `keel stats --json` stays counts only.

`--since` leaves out runs started before that day, with everything they did, even on later days; a verifier outside a run counts by its own day.
`--repo` keeps only trees, and sessions, whose path has that name as one of its parts, such as `app` for `~/.treehouse/app-359d95/13/app`.

## Where it reads from

- Runs, live and archived, under `~/.local/state/keel/runs/` ([status.md](status.md)), with each run's `decisions.tsv`.
- Verdicts outside runs, from `~/.local/state/keel/verdicts.jsonl`, and script events from `~/.local/state/keel/events.jsonl`.
- Claude Code's transcripts under `~/.keel/claude/projects/`, with each session's `subagents/` folder and its `.meta.json` files.
- The playbooks under `method/playbooks/`, for the text of each step.

Each transcript's totals are cached under `~/.local/state/keel/stats-cache/`, keyed by the size and mtime of the transcript and its subagents' files, so a second run reads only sessions that changed.

## How it counts

- **A skill** runs in a playbook step when the step's text runs it "with", "through" or "run" `/name`, such as "Audit it with `/audit-issue`".
  A step that only mentions one, such as "shipping is `/ship`", runs none and counts as `<playbook> step <n>`, as does a step naming nothing; the time before step 1 counts as `router`, and each `keel-verifier` spawn as `verify`; a step naming `/verify` counts as its playbook's own step, so `verify` holds verifier spawns alone.
- **A skill invoked directly** counts too: one you typed as `/name`, or one the agent called through its Skill tool, when `name` is installed under `~/.keel/claude/skills/`.
  The invocation holds the calls, time and tokens that follow it until the next message you type or the run's next step, whichever comes first.
  An agent loading the skill you just typed is that same run, and a skill invoked inside the step that runs it adds its time to that skill but not another run.
  Claude Code's own commands, such as `/login`, and other packs' skills are left out.
- **What started a run** is the installed skill invoked directly that held the work when its `keel run start` ran, such as `/pickup`, else the router.
  Step texts come from the playbook files as they are now, so a run that followed an older version is named by the current one.
- **A run of a skill** is a run entering the step that runs it, found from the `keel run start` and `keel run step <n> doing` calls in the transcript that ran. A start counts only when a run folder for its playbook began while the call ran, so a start keel refused, or text that only mentions one, counts nothing; a call the user denied or a hook refused never ran. A compound command that failed on another part still moved the run.
- **Agent time** is the gaps between a session's messages while the step is current, leaving out gaps over 30 minutes as idle.
  **Waiting** is the gap before each message the user typed.
  A verifier's time is its own first-to-last message.
- **Tokens** are summed once per assistant message id: input, cache writes, cache reads and output.
  `tokens_by_kind` keeps the four apart, since cache reads cost about a tenth of the rest; its four values add up to the session's and subagents' tokens together.
  A subagent's tokens count toward the step its first message falls in.
- **A turn** is one assistant message id, counted where its tokens are, in the session or in its subagents.
  Cost grows with turns times the context each one carries, so turns per run is the other half of a skill's token bill.
- **A rerun** is a step entered again after another step was started in the same run.
- **A damaged file never stops it.** A value of the wrong type in any file it reads is left out, and a transcript line it cannot read is counted in `unread`.

## Output, version 1

Fields are only ever added, never renamed or removed; a change that would break a reader bumps `version`.

| Field | Meaning |
|---|---|
| `version` | `1` |
| `since`, `repo` | the filters given, or null |
| `skills[]` | `{name, where, runs, calls, agent_s, wait_s, tokens: {session, subagents}, tokens_by_kind: {input, cache_write, cache_read, output}, turns: {session, subagents}, models: {<model>: tokens}, subagents: {<agent type>: count}, reruns}`, most run first; `where` lists the `<playbook> <step>` places it ran from; `verify` adds `verify_rounds: {<rounds>: runs}`, how many verifiers each run spawned; `how` lists the ways it ran, most runs first, from `step`, `typed`, `agent`, `verifier` and `router`; `invoked: {typed, agent}` counts its direct invocations |
| `playbooks[]` | `{name, runs, states: {<state>: runs}, median_minutes, versions, started_by: {<skill or "router">: runs}, steps[]}`, with `versions` the number of playbook hashes its runs followed, `started_by` counted from the transcripts that started its runs, and each step `{n, title, skill, done, skipped, open, skip_codes: {<code>: runs}, attempts, rerun_runs, attempt_s, entered, agent_s, tokens: {session, subagents}, tokens_by_kind, turns}`, the first of them from the runs' status files, with `attempt_s` the wall time of its closed attempts, waits included, and `entered` to `tokens` from the transcripts, as `skills[]` counts them but for that step alone |
| `scripts[]` | `{cmd, calls, exits: {<code>: calls}, handed_back: [[reason, calls]], median_ms}` from `events.jsonl`, with the five commonest exit-2 reasons |
| `verifier` | `{verified_runs, first_pass, rounds_to_pass: {<rounds>: runs}, fail_categories: {<category>: fails}}`, the first three from the verifier rows in each run's `decisions.tsv`, and `fail_categories` from `verdicts.jsonl`, commonest first, leaving out fails recorded before they had a category |
| `days[]` | `{day, runs, pass, fail}` per day: runs started, and verdicts in runs and outside them |
| `transcripts` | `{read, cached}`: sessions read this time, and taken from the cache |
| `unread` | `{lines, unread, share}`: transcript lines it could not read, being not JSON, or with a timestamp lacking its offset or token counts that are not whole numbers; it skips them while counting the rest |

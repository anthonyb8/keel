# keel router

Every task in this session goes through a playbook, so its steps are visible and a skipped one shows why.
Playbooks live in `~/.keel/method/playbooks/`; `README.md` there is the index.

When the user gives you a task:

1. **Restate it.** In your first reply, say the goal in one sentence and the smallest change you expect to meet it. Do not wait for confirmation.
2. **Match it.** Read the index and pick the playbook whose trigger fits the task. Name it: "Playbook: issue". If none fits, say "no playbook fits", work as the rules alone describe, and end your report with one line naming the task's shape, so a playbook can be written for it later.
3. **Open the todo list.** Read the matched playbook, then open the todo list with its steps as the first items, copied word for word. Add your own items after them, never in place of them.
4. **Record the run.** Write the playbook's steps to a file, one per line, and start a run: `keel run start --playbook <name> --goal "<the goal>" --steps <file>`. Move it on with the todo list: `keel run step <n> doing`, then `done`, or `skip <reason>`; end it with `keel run stop done`, or `stopped` or `failed` with `--note`. "No playbook fits" starts no run. If `keel status --json .` already shows a paused run in this tree, continue it rather than start another: moving its next step to `doing` resumes it.
   A run started with an approved contract (`--contract`) is held to its done check by the Stop hook. In it, decide what you would otherwise ask, log it with `keel run decide "<decision>" --why <text> --evidence <ref> --attention`, and carry on, except for data deletion, anything leaving the machine beyond the contract's grants, and protected branches, which you still ask about.
5. **Skip visibly.** A step that does not apply stays on the list, marked done as `skip: <reason>`. Never drop one silently.
6. **Re-match** when the user says "new task", when `/keel` is invoked, or when the work turns into a different kind of task, such as an investigation that becomes a fix.

Skip routing only for a one-line edit the user has fully specified, such as "rename x to y in foo.ts": just do it.
A question about this conversation, or a follow-up inside a task already routed, is not a new task.

Delegated work runs in a `keel-agent` with a brief naming the playbook step it carries out. Review what it returns before relying on it.

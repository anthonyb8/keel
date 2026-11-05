# issue

Carry a Linear issue from audit to a change ready to ship, stopping for the user's answers to the audit and again before `/ship`.
Each step runs its skill by reading `~/.keel/claude/skills/<name>/SKILL.md` and following it in place.
When the conversation already holds a step's output for this issue, start after it.

## Steps

1. Resolve the ID: the argument, else the branch name's `[A-Za-z]+-[0-9]+`, uppercased; with neither, ask, and never guess or search for one.
2. Check its state with `keel linear get <ID>`: go on from Backlog, Todo or In Progress; stop if In Review, In Staging, Done, Canceled or Duplicate; ask if an open issue blocks it.
3. Open its tree with `EnterWorktree name=<branchName>`, unless the session is already in a tree on that branch, and name the session `ABC-123 short slug`.
4. Audit it with `/audit-issue` and stop for the answers to its open decisions **(stop)**.
5. Build it with `/implement`.
6. Write its tests with `/write-tests`.
7. Audit the tests with `/audit-tests` in a fresh `keel-agent` that did not write them.
8. Write its journey test with `/e2e`.
9. Move it to In Progress once, after the first real run and only from Backlog or Todo: `keel linear update <ID> --state "In Progress"`.
10. Stop before shipping, with everything uncommitted; shipping is `/ship`, on the user's ask **(stop)**.

## Reply

What was built, the tests added and what the audit kept, rewrote or deleted, the journey tests with their screenshots, what was not verified, and the app's URL and sign-in when the stack is up.
Past In Progress the issue's status follows the PR: never move it forward on a gate result or a finished task alone, and never backwards unasked.

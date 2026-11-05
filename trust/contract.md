goal: <what is true when the run succeeds, in one sentence>
done: <a shell command, run from the tree's root, whose exit 0 means done; it must fail today and finish in under 5 minutes>
give-up: <when to stop and write up why, such as "the same check fails three times with no new commit">
budget: <a wall-clock limit such as 4h, after which the Stop hook stops holding the session>
grants: <what the run may do without asking: none, or any of commit, push, draft-pr>

The lines above are the contract; the Stop hook reads them, and changing them mid-run blocks the turn.
Free notes go here, below the blank line: the scope, what is out, and anything the run should know.

Draft it from the user's prompt and stop for their approval before starting the run: approving it is their ask for exactly what its grants cover, and nothing else.
Start it with `keel run start --playbook <name> --goal "<goal>" --steps <file> --contract <this file>`.
A done check that already passes is refused, since it could never tell the work is done.

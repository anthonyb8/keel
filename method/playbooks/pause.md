# pause

Stop safely mid-task and leave a note the next session can resume from.

## Steps

1. Stop at a safe boundary: finish or back out of the current step, start nothing new, and stop subagents.
2. Take no irreversible step to pause: no commit, push or PR; uncommitted work stays in the tree, which sweep and SubagentStop already refuse to return.
3. Write the resume note to `~/.local/state/keel/notes/<tree-key>.md`, or to the path a treetop handoff request names: the goal, the playbook and its step, what is done and verified, what is not, next steps, key files, and the gotchas.

`<tree-key>` is the tree's absolute path with every `/` and `.` turned into `-`.

## Reply

Where it stopped, what is on disk, and the first action on resume.

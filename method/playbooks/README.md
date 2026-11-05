# Playbooks

The router reads this index to match a task, then reads only the matched playbook.

| Playbook | Use when the task is |
|---|---|
| [issue](issue.md) | a Linear issue to build, such as "pick up ABC-123" or `/pickup ABC-123` |
| [bug-fix](bug-fix.md) | something broken to fix, reported in words, a stack trace or a failing check, with or without an issue |
| [investigation](investigation.md) | a question to answer about the code, its history or a choice between options, with nothing to change yet |
| [babysit-pr](babysit-pr.md) | an open pull request to get green or merge-ready, such as "get #123 green" or "answer the review on #123" |
| [pause](pause.md) | stopping mid-task so another session can resume, such as "pause here" or a treetop handoff request |
| [pickup](pickup.md) | resuming another session's work in this tree, such as "pick up where the last session stopped" |

## Format

A playbook is a Markdown file named for the playbook, with a one-line purpose and numbered steps.
Each step is one line the router copies word for word into the todo list, so it reads as an instruction on its own.
A step that runs a skill names it, such as `/audit-issue`.
A step that stops for the user ends with **(stop)**, and says what the user is asked for.
The playbook ends with what the final reply holds.

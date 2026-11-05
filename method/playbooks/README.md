# Playbooks

The router reads this index to match a task, then reads only the matched playbook.

| Playbook | Use when the task is |
|---|---|
| [issue](issue.md) | a Linear issue to build, such as "pick up ABC-123" or `/pickup ABC-123` |

## Format

A playbook is a Markdown file named for the playbook, with a one-line purpose and numbered steps.
Each step is one line the router copies word for word into the todo list, so it reads as an instruction on its own.
A step that runs a skill names it, such as `/audit-issue`.
A step that stops for the user ends with **(stop)**, and says what the user is asked for.
The playbook ends with what the final reply holds.

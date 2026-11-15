---
name: pickup
description: Pick up a Linear issue and carry it from audit to a change ready to ship, through keel's issue playbook, or a Linear project and build its issues in order on one branch, through the project playbook. Use when given an issue like ABC-123 or a project's name to work on, implement or fix, or when beginning a session on a branch whose name carries an issue ID.
argument-hint: "ABC-123 | \"Project name\""
---

# Pick up an issue

Run the `issue` playbook, `~/.keel/method/playbooks/issue.md`, for the ID given, as the router describes: restate the goal, name the playbook, and open the todo list with its steps word for word.

An argument that is not an issue ID (`[A-Za-z]+-[0-9]+`) is a Linear project's name: run the `project` playbook, `~/.keel/method/playbooks/project.md`, for it the same way.

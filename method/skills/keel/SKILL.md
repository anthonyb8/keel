---
name: keel
description: Route a task through keel's playbooks - restate the goal, match a playbook, and open the todo list with its steps word for word. Use when the user types /keel, says "new task", or asks to re-match the current work.
argument-hint: "<task>"
---

# Route a task

Apply `~/.keel/method/router.md` to the text after `/keel`, as a fresh match, even if the session already routed an earlier task.
Read the playbook index at `~/.keel/method/playbooks/README.md`, then the matched playbook, and follow the router's steps: restate, match, open the todo list with the playbook's steps copied word for word, and mark any skipped step `skip: <code>: <note>`.
With no text after `/keel`, re-match the task the conversation is on.

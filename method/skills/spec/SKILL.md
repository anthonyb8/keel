---
name: spec
description: Write a Linear issue, or a Linear Project and its issues for a larger build, from the keel templates. Use when asked to create, write, draft or file an issue, ticket or spec, or to break a build down into issues.
argument-hint: "<what needs doing>"
---

# Write a ticket

The output is a Linear issue, or a Project with its issues, that someone can build from without re-deciding anything.
Nothing is created until the user says yes to the draft.

## 1. Find the team and the base

- Team: `keel linear team`, from the repository's pack or `~/.config/keel/linear`, such as `END`. When it fails, show its message: the fix is a line in `~/.config/keel/linear`, which is the user's to add.
- Base: `keel base`, else the repository's default branch, `git symbolic-ref --short refs/remotes/origin/HEAD` without its `origin/`.

## 2. Size it

- Fits in one PR into the base: an **issue**.
- Ships value on its own but needs more than one PR: a **Project**, with one issue per PR.

Say which, and why, in one line.

## 3. Start from the template

`keel template issue` or `keel template project`.
Keep every heading. An empty one says why it is empty, such as "N/A - not a bug".

## 4. Research before asking

- Find what the ask touches in the code and check each pointer against the base, as `path:line`.
  Fan out read-only `Explore` agents for a broad build.
- Judge UI against backend work from the code, never from labels; the pack's rules say where to look when it matters.
- Before writing up UI, check whether the named surface already has a component doing the job.
- Search the team's open Linear issues for the same work with `keel linear search <words>`, and link or stop on a duplicate.
- Ask the user only what the code cannot answer, usually the Outcome, what is Out, and the open decisions.
  Keep it to a few questions, each answerable in a word.

## 5. Write it

- Title: short, names the change, no ID.
- Prose in VOICE.md's register, with paragraphs running on within a line, because Linear renders a single line break as a break.
- Acceptance checks describe what a user does and sees, so they can become the end-to-end test.

## 6. Show the draft

Put the full draft in chat and ask whether to create it.
A Linear issue is visible to the whole team, so create only on an explicit yes, and apply any edits first.

## 7. Create it

An issue:

Write the description to a file, then:

```
keel linear create --title "<title>" --body <file> [--project "<name>"] [--blocked-by ABC-1]...
```

It prints the new ID, its URL, and the team and workspace it filed in; check those are the ones you meant.

A Project:

1. `keel linear project create "<name>" --summary "<one line, 255 characters at most>" --body <file>`, with the filled `project` template as the body.
2. One `keel linear create` per Breakdown row, in order, with `--project` set and `--blocked-by` from its "Depends on" column, each body filled from the `issue` template.
3. Put the new issue IDs into the project's Breakdown table: `keel linear project update "<name>" --body <file>` with the edited body.

Leave every issue in its default state and unassigned unless the user said otherwise.

## 8. Report

The issue IDs and their URLs.
Do not branch or start building: `/pickup ABC-123` does that.

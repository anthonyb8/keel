---
name: implement
description: Build an audited issue end to end, layer by layer, following the repository's CLAUDE.md and the pack's rules, verifying as it goes and leaving the change uncommitted. Run only when the user invokes /implement or /pickup runs it.
disable-model-invocation: true
argument-hint: "[ABC-123]"
---

# Implement the issue

This turns the audited issue into code.
It writes files but never commits, pushes or changes branches: `/ship` does that when asked.

The repository's `CLAUDE.md` is the rulebook, and the pack's rules add to it.
Where this skill disagrees with them, they win.
Where existing code disagrees with them, the code is drift: bring what you touch up to standard, and leave the rest of the file alone.

## 1. Gather the inputs

- The issue is the argument, else the one in this conversation, else the branch name's ID. With none, ask.
- The spec is the issue, its comments, and the `/audit-issue` write-up with its answered decisions. Those decisions are settled; do not reopen them.
- For a UI change, the mockup approved through `/mockup`, linked from the issue's comments: build to it, and name anything that has to differ and why.
- With no audit in the conversation, say so and offer to run `/audit-issue` first. Building without one is the user's call, not a default.
- Ask any decision still open now. Building on a guess about the data model is the most expensive mistake to undo.
- `git status` and `git branch --show-current`. If the tree holds unrelated changes, ask before working alongside them.

## 2. Load the standards

Before writing code, not after:

- The repository's `CLAUDE.md`, and every standard it says to load for the layers this change touches, such as a project skill for code style, UI design or accessibility.
- The existing feature the audit named as the pattern to copy: match its layout, naming and idiom.
- The Writing code section of `~/.keel/claude/OPINIONS.md`: climb its rungs before writing each piece, and reuse what the repository already has.

## 3. Reproduce a bug first

A bug fix starts with a test that reproduces it the way a user hits it, end to end where the bug is user-visible.
Write it as `/e2e` describes, run it, and watch it fail for the reason in the issue before changing any code.
Keep it: it is the regression test.

## 4. Build in order, layer by layer

Schema and data first, then data access, business rules, services, and UI last, so each layer is built on one that already works.
Follow the repository's rules for each layer as its `CLAUDE.md` states them, including the ones CI does not catch.

- A schema change is backward compatible with the code already deployed (expand, then contract) unless the repository says otherwise.
- UI gets its loading, empty and error states, works for every role the audit listed, and meets the repository's accessibility bar.
- Comments say why, in the present tense. Code nothing calls is deleted, not kept.

Run the repository's fast check (typecheck, lint, the touched unit tests) after each meaningful change rather than only at the end: a failure is easier to trace while it is small.

## 5. Docs in the same change

Update the docs this change makes stale, and any help or user-facing content whose wording it changes, as the repository's docs policy says.
A "planned, not built" statement this change makes true gets flipped.

## 6. Finish

- Every check the repository's `CLAUDE.md` requires before finishing passes, at zero.
- If the change is visible, bring the app up with `keel stack up` and look at it as each role the audit named. Visual perfection is the bar.

Report on the change itself, not the thinking behind it:

- what was built, layer by layer, with the key files;
- what was reused rather than written, and what was left out as unneeded;
- anything that differs from the audit, each with the fact that forced it, at `path:line`;
- what was not verified: a suite not run, a role not checked, a stack that was not up;
- manual steps for release: env vars, dashboard settings, secrets.

The code is audited next, by `/audit-code` in a fresh context, then the tests come through `/write-tests`. Do not commit.

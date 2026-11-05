---
name: mockup
description: Mock up an issue's UI change as a private claude.ai Artifact in the repository's own look - every role, state and width the audit named - and stop until the user approves it, so the build has a design to follow. Use when asked to mock up, design or sketch a UI change before building it, or as the mockup step of /pickup.
argument-hint: "[ABC-123]"
---

# Mock up the UI change

The output is one approved mockup the build follows, so the user sees the design before any code exists.
It writes no code in the repository and changes no git state.

## 1. Decide whether it applies

- The issue is the argument, else the one in this conversation, else the branch name's ID.
- The spec is the issue, its comments, and the `/audit-issue` write-up with its answered decisions.
- It applies when the audit's affected systems include the UI layer: a new screen, or a change to what an existing one shows or how it behaves.
- It does not apply to a change with no UI, or one that only rewords copy the audit already settled: skip it and say why.

## 2. Learn the look

Before drawing anything:

- The repository's `CLAUDE.md`, and every standard it names for UI design or accessibility.
- Its design tokens: colours, type, spacing, radii, shadows, wherever the repository keeps them, such as a theme file, CSS variables or a Tailwind config.
- The components the change will use, read for their shape, states and spacing.
- The existing screen the audit named as the pattern to copy. When the stack is up (`keel stack up`), screenshot it as each role the audit listed: that is the before.

## 3. Build it

Start it as a private Artifact with the Artifact tool, from the Design type (`action: "quickstart"`, `intent: "design"`), and follow what its result says.

- Use the repository's tokens and component shapes, so it reads as this app, not a generic wireframe.
- Use the real copy and realistic data, including long names, many rows and none.
- Show every role the audit listed, and each state the change reaches: loading, empty, error, success, and disabled where it applies.
- Show phone and desktop widths.
- When the change alters an existing screen, show the before beside the after.
- Make the main path clickable where a static frame would hide how it behaves.
- Label each frame with the acceptance check it shows, so the user can match the design to the issue.

## 4. Stop for approval

Give the user the link, the frames it holds, and anything you decided that the issue did not say.
Stop until the user approves it **(stop)**.

Revise it in place, to the same link, for each change the user asks for, whether in the conversation or as comments on the Artifact, and stop again.
A design question the issue left open is the user's to settle here: do not settle it in the build.

## 5. Record it

Once approved, add one comment to the issue with `keel linear comment <ID> --body <file>`: the mockup's link, the date it was approved, and any decision made while reviewing it.
That comment is what `/implement`, `/e2e` and the verifier work from.

## 6. Report

The link, the frames and the acceptance check each shows, the decisions made in review, and the Linear comment's URL.
The mockup shows intent, not pixels: it is drawn in HTML, not the repository's own components, so the real screens are judged by `/e2e` against it.

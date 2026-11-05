# Voice

How I write.
Read this before producing any of the following in my name:

- commit messages, PR titles and descriptions, issue text, code review comments
- READMEs, docs, changelog prose, design docs
- email, chat, and DMs sent as me

It does not apply to code comments, which follow the conventions of the code around them.

## Register

Plain and complete.
Direct, but willing to spend a paragraph on context and reasoning so the reader is not left
inferring what I meant.
Explanatory rather than clipped.

State the thing, then explain it.
Do not warm up to the point across two sentences of preamble.

No hedging stacks.
"This might possibly be a problem" is "this is a problem" or it is nothing.
If I am genuinely unsure, say so once, plainly, and say what would settle it.

## Commits

A one-line headline, then a blank line and a body of two or three concise sentences.
Every commit gets the body, however small the change.

The headline is terse and names the change, prefixed with the issue ID where the project uses one.
The body says why the change was needed and what it means for the reader, not a list of files.
The diff already shows what.

Never add a co-author or agent attribution line.

## Pull requests

Fill the project's PR template and add nothing to it.
No extra headings, no rejected-alternatives section, no trailing notes after the checklist.
If something does not fit one of the sections, it belongs in a review comment or in the issue.

Write each section's prose as ordinary paragraphs, sentences running on within a line.
GitHub renders a single line break in a PR body as a visible break, so the one-sentence-per-line
rule for Markdown files does not apply here: it turns a paragraph into a column of broken lines.
The same goes for issue text and review or PR comments on GitHub.
Line breaks belong only between paragraphs, list items and sections.

"What changed" is the change itself, in one or two sentences.
The bug, its blast radius and the reasoning are "Why".
Opening "What changed" with the problem is the mistake to watch for.

"How to test" is a numbered list.
Start from getting the app running, in one command where the project has one.
Say what to click and what should appear, not which suite to run.
Close with a step for reproducing the old behaviour on the base branch when that is what makes the change legible.

Keep the optional sections rather than deleting them, and say why they are empty.
"N/A - no UI changes" reads better than a bare "N/A", which most template linters treat as filler.

Tick the checklist boxes and stop.

## Docs and READMEs

Plain and complete register.
One sentence per line in long Markdown files, per the General rules.

Lead with what the thing is and what it is for.
Installation and usage before architecture and rationale.

## Email and messages

Same register.
Get to the ask in the first line, then give the context behind it.
No throat clearing, no apologizing for writing.

## Never

- em dashes, use a plain dash instead
- filler openers: "Great question!", "Absolutely!", "I'd be happy to"
- summary closers that restate what was just said
- emoji, unless the person I am replying to used them first
- marketing language: "seamless", "robust solution", "leverage", "powerful"
- exclamation marks, outside genuine good news

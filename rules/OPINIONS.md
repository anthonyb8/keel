# Opinions

These are positions, not observations.
Where a default, a common practice, or the surrounding code disagrees, these win.

This file covers what the General rules in `~/.keel/claude/CLAUDE.md` do not.
It does not repeat them.

## Testing

Mocks are a smell.
A mock standing in for the thing under test hides the exact failure you are looking for.
Mocking a third party boundary you do not control is sometimes the only option; mocking your own code
to make a test pass is not.

Unit tests are for genuinely isolated logic.
They are not a way to simulate the system.
If a test needs five fakes wired together to run, it is an integration test wearing a disguise, and
it should be written as one.

## Dependencies

Prefer a mature, widely used library over code I have to maintain.
Do not reinvent solved problems.
A maintained library has already absorbed edge cases I have not hit yet, and my hand-rolled version
will hit them later, alone, at a worse time.

Boring and widely adopted beats clever and new.
Check that a dependency is actually maintained before reaching for it: recent releases, open issues
getting answered, more than one committer.

This does not license dependency sprawl.
One good library for a real problem, not four to avoid writing ten lines.

## Writing code

Write only what the task needs.
The best code is the code that was never written, because something already does the job.

Read first: the code the change touches, its callers, and the real flow through it.
Be lazy about the solution, never about the reading.
Then, before writing anything, stop at the first rung that holds:

1. Does this need to exist at all?
2. Is it already in this repository?
3. Does the standard library do it?
4. Does the platform do it natively, such as a browser input type or a database constraint?
5. Does a dependency already installed do it?
6. Would one mature library earn its place, as Dependencies above says?
7. Only then, write the minimum that works by hand.

Never cut, whatever the rung: validation at a trust boundary, error handling where data can be lost, security, accessibility, or a test for logic with a branch, a loop, a parser, money or a permission in it.

Small because necessary, not golfed.
A clear five lines beat a clever one.
An abstraction with one caller is not one yet.

## Rules vs existing code

Rules are decisions, not observations.
Where the existing tree disagrees with a rule, the rule wins and the old code is drift.

Do not infer a convention from surrounding code when a written rule says otherwise.
Consistency with a file is not a reason to violate a rule; it is evidence the file needs updating.

Do not silently migrate drift you were not asked to touch.
Follow the rule for what you are writing, and name the drift you found when you finish.

## Technical judgment

When two approaches are close, pick the one that is easier to delete.
Reversible decisions can be made fast; irreversible ones deserve the paragraph of thought.

Say when you are uncertain.
A flagged guess is useful. A confident wrong answer costs me the time it takes to discover it.

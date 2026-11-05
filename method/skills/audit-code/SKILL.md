---
name: audit-code
description: Audit code for what it does not need - cut what need not exist, what the repository, standard library, platform or an installed dependency already does, and dead or single-use abstractions, while never cutting validation, error handling, security, accessibility or tests. Use when asked to audit, debloat, slim or prune code, or as the code audit step of /pickup, run by an agent that did not write the code.
argument-hint: "[diff | path | repo]"
---

# Audit the code

Aim for code that is small because it is necessary, not a deletion count.
The standard is the Writing code section of `~/.keel/claude/OPINIONS.md`: read it first.
Read the repository's `CLAUDE.md` too, and any project skill it names for code style: where they and this skill disagree, they win.

## 0. Audit with fresh eyes

The code is judged by an agent that did not write it, so the writer's reasoning cannot anchor the verdict.
When this session wrote the code, do not audit it here: spawn a `keel-agent` with the tree's path, the base branch, the issue ID if there is one, the scope, and the instruction to read `~/.keel/claude/skills/audit-code/SKILL.md` and follow it.
Give it no summary of why the code was written. Relay its report.

## 1. Scope

- **Diff** (the default, and what `/pickup` asks for): every production file added or changed against the base (`keel base`, else the default branch), and the code those changes call or are called by, even where it is untouched.
- **Path or area**: one owner boundary, read whole.
- **Repo**: the whole repository, mapped first: entry points, how data moves through it, and the load it is built for. Report only; change nothing.

Before judging a piece of code, read its callers, what it calls, its tests, and `git log -p --follow` on it: why code exists often lives in its commit or issue.

## 2. What to look for

**Need not exist**
- a feature, option, flag or parameter nothing in the task or the app asks for;
- code nothing calls, and production code only tests call;
- config, env vars or settings nothing reads;
- a fallback for a state that cannot happen, and handling for an error the callee never raises.

**Already done elsewhere**
- a helper that duplicates one already in the repository;
- a hand-rolled version of something the standard library does;
- a hand-rolled version of something the platform does natively, such as a browser input type, a CSS feature, or a database constraint or default;
- a hand-rolled version of something an installed dependency does;
- a new dependency added for what a few lines, or an installed one, already cover.

**Too much shape**
- an abstraction, interface, factory or wrapper with one caller;
- a layer that only passes its arguments through;
- generality no caller uses: type parameters, hooks or options with one value;
- copied code that should be one function, at three copies or more.

**Breaks outside the diff** (diff and repo scope)
- a caller, route or job the change breaks without touching it, such as a renamed field still read elsewhere.

## 3. Never cut

Drop any finding that would remove or weaken:
- validation at a trust boundary: user input, request bodies, files, webhooks, anything from outside the process;
- error handling where data can be lost or corrupted;
- security: authentication, authorization, tenant isolation, escaping, secrets handling, rate limits;
- accessibility;
- a test for logic with a branch, a loop, a parser, money or a permission in it (`/audit-tests` owns tests);
- a contract other code depends on: a public API, a schema, a migration.

Shorter is not a reason on its own: a clear five lines stay over a clever one.

## 4. Evidence before cutting

Record for every finding: the code at `path:line`, what replaces it (the existing function, the standard library call, the platform feature, or nothing), every non-test caller, why it was added, and what breaks if it goes.
A finding missing a field is not ready to act on.

## 5. Fix

On **diff** or **path** scope, apply the findings in one coherent batch: cut, replace with what already exists, inline single-use abstractions, and delete the tests that only covered what was cut.
Re-run the owner suites and the repository's required checks.
Leave the changes uncommitted.

On **repo** scope, change nothing: the report is the output.

## 6. Report

Findings ranked, most important first:
- **Must fix**: something breaks, such as a caller outside the diff;
- **Should fix**: real weight, such as a duplicate of existing code or a hand-rolled standard library function;
- **Nice to have**: small, such as a one-caller wrapper.

Each with its evidence, and on diff or path scope whether it was applied.
Then: what was dropped under Never cut and why, what was run and what was skipped, and production lines removed against lines added.

---
name: audit-issue
description: Audit a Linear issue against the codebase before any code is written - map what it touches, challenge its approach, and raise its open decisions as questions with options and a recommendation. Use when asked to audit, scope, refine or check an issue like ABC-123, or as the first step of /pickup.
argument-hint: "ABC-123"
---

# Audit an issue

The output is a scope map and a short list of questions that, once answered, leave nothing for the build to guess.
Do not start implementing: read the repository, never write it, and change no git state.

## 1. Read the issue

- The argument is the issue ID. Without one, take it from the branch name (`[A-Za-z]+-[0-9]+`, uppercased), else ask.
- `keel linear get <ID>` prints the issue with its state, project, relations and comments. A decision in a comment overrides the description.
- Follow related, blocking and duplicate issues one level deep, and read the parent project's description: its Design and Rollout bind this issue.
- Restate the ask in one sentence. If you cannot, that is the first open decision.

## 2. Map it onto the code

Research before asking: every question in step 4 must point at something you found.
Fan out read-only `Explore` agents, one per layer, for a broad issue.

Take the layers from the repository's `CLAUDE.md` and architecture docs, and the pack's rules where they name them, typically UI, data access, business rules, services and vendors, schema, and tests.
Trace each thing the issue changes through them end to end, and record with `path:line`:

- **Affected systems:** every file or directory that will change, by layer.
- **Pattern to copy:** the closest existing feature, named, so the build reuses it rather than inventing one.
- **Callers:** what else reads the tables, functions or components being changed. This is where breakage hides.
- **Data and contract changes**, each flagged yes or no: schema, access rules, env vars, a new service or endpoint, a vendor, anything another client sees live, a performance budget.
- **Compatibility:** does a changed column, response or signature break a caller, and can the change ship without one release breaking the other?
- **Tests that own it:** which existing tests cover the area, and which layer a new test belongs in, per the repository's testing policy.

## 3. Check it against the issue template

`keel template issue` prints the shape the issue should have.
Note every heading the issue leaves empty or unsupported, especially Outcome, Out of scope and Acceptance: an acceptance check that is not something a user does and sees cannot become the end-to-end test.

## 4. Find the open decisions

Look for what the issue leaves undecided, in three categories:

| Category | Look for |
|---|---|
| **Technical** | missing implementation detail, an architecture choice, scale |
| **Product** | edge cases, empty and error states, permissions, flows nobody described |
| **Scope** | overlap with other issues or in-flight branches, work that could split off |

Probes that find most of them:

- **Roles:** what each role sees and can do, another organisation's users, any plan or billing gate.
- **States:** every state the entity can be in, not just the happy one, and what happens to rows that already exist.
- **Failure:** a vendor that is down, a partial write, a retry; is the write atomic?
- **Notifications:** who hears about it, by which channel, and is it deduplicated?
- **Overlap:** open issues in the team, and other branches (`git branch -a`) touching the same files.
- **Whatever the pack's rules list as this product's sharp edges**, such as money rules.

Drop anything the code or docs already answer, and cite where: a question the repository answers is research left undone.
Drop anything with a clear conventional default, and list the default as an assumption instead.

## 5. Challenge the approach

An issue states a solution. Test it before anyone builds it:

- Is it the real problem, or would a different change remove the need for this one?
- Is there a smaller version that delivers most of the value now, with a follow-up for the rest?
- What does it do to the neighbouring features the data flow reaches?
- Does it hold for every role and every state, including data already in production?
- Is there an existing pattern or wording it should match rather than invent?

A challenge that changes what gets built is an open decision, with the issue's approach as one option.
If the approach holds, say so in one line.

## 6. Write it up

Reply in chat in this shape:

```markdown
## ABC-123: <title>

**The ask:** <one sentence>

### Scope
- **<layer>:** <files>, modelled on <existing feature>
- **Tests:** <owning layer and existing files>
- **Risk:** <callers that could break, compatibility, budgets>

**The approach:** <"Holds" | the challenge, raised below>
**Template gaps:** <none | the headings that are empty or untestable>

### Assumptions (proceeding unless told otherwise)
- <a decision with a clear default, and the default>

### Open decisions
**1. <Short question>?** _(Technical | Product | Scope)_
Context: <what the code does today, with path:line>
Options: **A.** <option and its consequence> · **B.** <option and its consequence>
Recommendation: <A or B, and why in one line>
Blocks: <what cannot start until this is answered | nothing, defaults to X>
```

Order the questions by what they block, data model and schema first, since those cost most to change later.
Keep each answerable in a word. Aim for three to seven; more usually means the issue should split, which is itself a Scope question.

## 7. Offer to post

Ask whether to post the open decisions, and the answers once given, as a comment on the issue.
Post with `keel linear comment <ID> --body <file>` only on an explicit yes: a comment is visible to the whole team.
Once the decisions are answered, the issue is ready for `/implement`.

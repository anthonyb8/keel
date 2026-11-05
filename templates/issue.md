## Why

_Who hits this, what it costs them, and the evidence: a report, a screenshot, a count._

## Outcome

_What is true for the user once this is done, in one or two sentences._

## Repro

_Bugs only: numbered steps from a signed-in user, then what should happen and what happens instead. Otherwise "N/A - not a bug"._

## Scope

**In:** _what this issue changes._

**Out:** _what it deliberately leaves alone, and the issue that takes it, if any._

**Layers**, each one "none" or what changes:

- **UI:** _the page, its sections and dialogs, modelled on which existing feature._
- **Data:** _client data access, its caching and invalidation._
- **Schema:** _none, or the tables, enums, access rules and functions it changes, and the file each lives in._
- **Services / vendors / env:** _server functions, vendor calls, new env vars._
- **Tests:** _the layer that owns the check, and the existing files._
- **Risk:** _callers that could break, migration compatibility, perf budgets._

**Roles:** _what each role sees and can do, and whether a plan or billing gate applies, or "N/A - one role"._

## Acceptance

- [ ] _A check written as what a user does and what they see, testable end to end._

## Approach

_Known constraints and code pointers as `path:line`, each checked against the current base branch. Judge UI-only against backend work from the code, not from labels. "Open - not yet scoped" when nobody has looked._

## Open decisions

_Each as a question tagged Technical, Product or Scope, with its options and a recommendation, or "None"._

## Links

**Project:** _the parent project, or "None - standalone"._ **Blocked by:** _issues, or "None"._ **Blocks:** _issues, or "None"._

## Goal

_The outcome this build delivers, who it is for, and why now._

## Success

_How we know it worked once it has shipped: a behaviour, a number, or a complaint that stops._

## Scope

**In:** _what the build covers._

**Out:** _what it deliberately leaves for later, and where that goes._

## Design

_The user flows per role, the data model, and the interfaces between the pieces the issues build, so each issue can be built without re-deciding them._

- **Schema:** _tables, enums and access rules, naming the file each one lives in, or "none"._
- **Data:** _the client data access and caching the issues share._
- **Services / vendors / env:** _server functions, vendor integrations and env vars, or "none"._

## Breakdown

_One row per project issue, each sized to one PR into the base branch and created from `keel template issue`. Order the rows so each depends only on rows above it, schema first._

| # | Issue | Delivers | Depends on |
|---|---|---|---|
| 1 | _ID once created_ | _what a user or the next issue gets from it_ | _None_ |

## Rollout

_The order things release in through the branches the repository promotes along, and for each migration how it stays backward compatible (expand, then contract). Name who watches after release, the manual smoke check, and the rollback for each layer: UI, services, schema._

## Risks

_What could go wrong for users or data, and what guards against it, or "None known"._

## Open decisions

_Each as a question tagged Technical, Product or Scope, with its options and a recommendation, or "None"._

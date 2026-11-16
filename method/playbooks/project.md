# project

Carry a Linear project's issues to one pull request: audit every issue first, stop once for the answers, then build each in order on one branch with a commit per issue.
Invoking `/pickup` on the project is the ask for one `/ship commit` per issue it builds, one `/ship pr` after the last, and posting each issue's audit answers on it.

## Steps

1. Resolve the project: the argument, a Linear project's name or code, such as P-ANB-12, and for a code its name from `keel linear project get <code>`, used from then on; with none, ask, and never guess or search for one.
2. List its issues in build order with `keel linear project order "<name>"`; the ones still to build are in Backlog, Todo or In Progress with no commit on this branch whose headline starts with their ID.
3. Open the project's tree with `EnterWorktree name=<branch prefix>/<project-slug>`, using the prefix this repository's branches use, unless the session is already in a tree on that branch, and name the session `<project> short slug`.
4. Audit each issue still to build with `/audit-issue`, in order, unless its comments already hold its answered audit decisions, and stop once for the answers to all their open decisions, grouped by issue **(stop)**.
5. Post each issue's answered decisions as a comment on it with `keel linear comment <ID> --body <file>`.
6. End this run with `keel run stop done`, then build each issue still to build, in order, as its own run with `/pickup <ID>`, ending each with `/ship commit` and the last with `/ship pr`, titled for the project, whose body names every issue built.

An issue's build that fails and cannot be fixed in place stops the project there: report it, and leave the issues after it unbuilt.
Running `/pickup` on the project again resumes from the first issue still to build.

## Reply

The issues built, each with its commit, any skipped and why, the PR's URL, and what was not verified.

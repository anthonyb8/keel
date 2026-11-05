"""PreToolUse guard for Bash, behind `keel hook git-guard`.

Refuses a merge, rebase, cherry-pick or revert that would move a protected
branch, the list `keel protected` prints for the repository it runs in. In a
tree with an active contracted run it also holds commits, pushes and PRs to
the contract's grants, and a push or PR to a passing verifier.
Permission rules match command text and cannot see which branch is checked
out, so the check has to run here. Anything it cannot place, such as a git
call inside `bash -c` or a `cd` into `$VAR`, is refused rather than guessed:
a refusal costs a rephrase, a wrong guess costs a protected branch.

    python3 -I git-guard.py <keel> < event.json
"""

import json
import os
import re
import shlex
import subprocess
import sys

GUARDED = {"merge", "rebase", "cherry-pick", "revert"}
# Flags that leave the branch where it is, or finish an operation that could
# only have started off a protected branch.
HARMLESS = {"--abort", "--quit", "--continue", "--skip", "--edit-todo", "--show-current-patch"}
# Rebase options whose value is the next word, so it is not read as a branch.
REBASE_VALUED = {"--onto", "-s", "--strategy", "-X", "--strategy-option", "-x", "--exec"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
VERB_TEXT = re.compile(r"(?<![\w-])git(?![\w-]).*?(?<![\w-])(merge|rebase|cherry-pick|revert)(?![\w-])")


class Unplaceable(Exception):
    """The command runs a guarded verb somewhere this guard cannot follow."""


def tokens(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars="();<>|&\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def simple_commands(command, cwd):
    """Yields (dir, argv) for each simple command, following cd and subshells.

    dir is None once a cd goes somewhere only the shell could resolve.
    """
    dirs = [cwd]
    argv = []
    skip_next = False
    for tok in tokens(command) + ["\n"]:
        if tok and all(c in "();<>|&\n" for c in tok):
            if any(c in "<>" for c in tok) and not tok.endswith("("):
                skip_next = True
                continue
            if argv:
                yield dirs[-1], argv
                if argv[0] in ("cd", "pushd"):
                    paths = [a for a in argv[1:] if not a.startswith("-") or a == "-"]
                    dirs[-1] = resolve(dirs[-1], paths[0]) if paths else os.path.expanduser("~")
                argv = []
            for c in tok:
                if c == "(":
                    dirs.append(dirs[-1])
                elif c == ")" and len(dirs) > 1:
                    dirs.pop()
            continue
        if skip_next:
            skip_next = False
            continue
        argv.append(tok)


def resolve(base, path):
    if base is None or "$" in path or "`" in path or path == "-":
        return None
    return os.path.normpath(os.path.join(base, os.path.expanduser(path)))


def git_call(directory, argv):
    """Returns (dir, verb, args) for a git call running a guarded verb, else None."""
    words = argv
    env_dir = False
    while words and ASSIGNMENT.match(words[0]):
        env_dir |= words[0].startswith(("GIT_DIR=", "GIT_WORK_TREE="))
        words = words[1:]
    if not words:
        return None
    if words[0] != "git":
        # A wrapper such as `bash -c` or `xargs` that names a guarded verb.
        if VERB_TEXT.search(" ".join(words)):
            raise Unplaceable(" ".join(words[:2]))
        return None
    i = 1
    while i < len(words) and words[i].startswith("-"):
        opt = words[i]
        if opt == "-C" and i + 1 < len(words):
            directory = resolve(directory, words[i + 1])
            i += 2
        elif opt == "-c" and i + 1 < len(words):
            if words[i + 1].startswith("alias."):
                raise Unplaceable(f"git -c {words[i + 1]}")
            i += 2
        elif opt.startswith(("--git-dir", "--work-tree", "--namespace")):
            env_dir = True
            i += 1
        else:
            i += 1
    if i >= len(words) or words[i] not in GUARDED:
        return None
    verb, args = words[i], words[i + 1 :]
    if env_dir or directory is None:
        raise Unplaceable(f"git {verb}")
    return directory, verb, args


def target_branch(directory, verb, args):
    """The branch the call would move, or None when it moves none."""
    if any(a in HARMLESS for a in args):
        return None
    if verb == "rebase":
        if "--update-refs" in args:
            raise Unplaceable("git rebase --update-refs")
        positional = []
        it = iter(args)
        for a in it:
            if a in REBASE_VALUED:
                next(it, None)
            elif not a.startswith("-"):
                positional.append(a)
        named = positional[0:1] if "--root" in args else positional[1:2]
        if named:
            return named[0].removeprefix("refs/heads/")
    head = subprocess.run(
        ["git", "-C", directory, "symbolic-ref", "--quiet", "--short", "HEAD"],
        capture_output=True,
        text=True,
    )
    return head.stdout.strip() or None


def protected(keel, directory):
    out = subprocess.run([keel, "protected", directory], capture_output=True, text=True, check=True)
    return set(out.stdout.split())


def deny(reason):
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )


# Grants. In a tree with an active contracted run, the run's contract says
# what may leave the machine: `commit`, `push` and `draft-pr`, each in one
# narrow form, and a push or PR only once a passing verifier is recorded
# against the tree being sent. Outside a run nothing here applies.
#
# Inside a run the guard parses strictly and refuses what it cannot place: a
# git call aimed elsewhere by GIT_DIR or --git-dir, a gh alias or extension,
# and a commit, push or PR chained with other commands in one Bash call, since
# the verdicts and the branch are read before any of it runs.
RUN_VERB_TEXT = re.compile(
    r"(?<![\w-])(git(?![\w-]).*?(?<![\w-])(commit|commit-tree|update-ref|push|send-pack|http-push|branch|tag)(?![\w-])"
    r"|gh(?![\w-]))"
)
ALWAYS_REFUSED_PR = {"merge", "ready", "close", "reopen"}
# gh's own commands. Anything else is an alias or extension that could run
# any of them under another name.
GH_COMMANDS = {
    "pr", "issue", "repo", "run", "workflow", "api", "search", "label", "release", "auth",
    "status", "browse", "gist", "cache", "secret", "variable", "ruleset", "project", "codespace",
    "org", "ssh-key", "gpg-key", "config", "completion", "help", "version", "attestation",
}
GH_VALUED = {"-R", "--repo", "--hostname"}
# Git verbs that only ever send commits elsewhere.
NEVER_IN_RUN = {"send-pack", "http-push"}
# A commit, push or PR whose checks read the tree before the call runs, so it
# must be the only command in its Bash call.
ALONE = {"commit", "commit-tree", "update-ref", "push"}
BRANCH_MOVES = {"-f", "--force", "-m", "-M", "--move", "-c", "-C", "--copy", "-d", "-D", "--delete"}


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "keel", "runs")


def toplevel(directory):
    out = subprocess.run(["git", "-C", directory, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return out.stdout.strip() or None


def contract_run(directory):
    """The active contracted run holding the tree at directory, else None."""
    if directory is None:
        return None
    top = toplevel(directory)
    if not top:
        return None
    folder = os.path.join(state_dir(), re.sub(r"[/.]", "-", top))
    try:
        with open(os.path.join(folder, "status.json")) as f:
            status = json.load(f)
    except (OSError, ValueError):
        return None
    if status.get("state") != "active" or not status.get("contract_hash"):
        return None
    grants = set()
    try:
        with open(os.path.join(folder, "contract.md")) as f:
            for line in f:
                if not line.strip():
                    break
                if line.startswith("grants:"):
                    grants = {g.strip() for g in line[len("grants:"):].replace(",", " ").split()}
    except OSError:
        pass
    return {"tree": top, "folder": folder, "status": status, "grants": grants}


def head_tree(directory):
    out = subprocess.run(["git", "-C", directory, "rev-parse", "HEAD^{tree}"], capture_output=True, text=True)
    return out.stdout.strip()


def current_branch(directory):
    out = subprocess.run(["git", "-C", directory, "symbolic-ref", "--quiet", "--short", "HEAD"], capture_output=True, text=True)
    return out.stdout.strip()


def default_branch(directory):
    out = subprocess.run(["git", "-C", directory, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], capture_output=True, text=True)
    return out.stdout.strip().removeprefix("origin/") or "main"


def missing_verdicts(run, directory):
    """Why a push or PR from this tree lacks its verifier's pass, or None."""
    tree = head_tree(directory)
    v = run["status"].get("verifier") or {}
    if v.get("verdict") != "pass":
        return "a passing verifier (/verify)"
    if v.get("tree") != tree:
        return f"a passing verifier on this code: the last one passed tree {v.get('tree', '?')[:12]}, HEAD is now {tree[:12]} (/verify again)"
    return None


def run_refusal(keel, run, command, why):
    """Logs the refusal to the run's decisions.tsv, flagged, and returns it."""
    subprocess.run(
        [keel, "run", "decide", f"refused `{command}`", "--why", why, "--evidence", "git-guard", "--result", "refused", "--attention"],
        cwd=run["tree"],
        capture_output=True,
    )
    return f"git-guard refuses `{command}` in this run: {why}"


def strip_env(argv):
    """(argv without leading VAR=value words, whether one aims git elsewhere)."""
    words, aimed = argv, False
    while words and ASSIGNMENT.match(words[0]):
        aimed |= words[0].startswith(("GIT_DIR=", "GIT_WORK_TREE=", "GIT_COMMON_DIR=", "GIT_INDEX_FILE="))
        words = words[1:]
    return words, aimed


def git_target(directory, words):
    """(directory, words after git's options, aimed) for a git argv. Each -C
    applies in turn, as git applies them; directory is None when it cannot be
    placed, and aimed is True when an option points git at another repository."""
    i, aimed = 1, False
    while i < len(words) and words[i].startswith("-"):
        opt = words[i]
        if opt == "-C" and i + 1 < len(words):
            directory = resolve(directory, words[i + 1])
            i += 2
        elif opt == "-c" and i + 1 < len(words):
            i += 2
        elif opt.startswith(("--git-dir", "--work-tree", "--namespace")):
            aimed = True
            i += 1 if "=" in opt else 2
        else:
            i += 1
    return directory, words[i:], aimed


def gh_pr(words):
    """(subcommand, its args) for `gh pr ...`, skipping flags before it."""
    rest = words[2:]
    i = 0
    while i < len(rest) and rest[i].startswith("-"):
        i += 2 if rest[i] in GH_VALUED else 1
    return (rest[i] if i < len(rest) else ""), rest[i + 1:]


def flag_value(args, *names):
    """The value of the first of names in args, in any of its spellings."""
    for i, a in enumerate(args):
        for n in names:
            if a == n and i + 1 < len(args):
                return a, args[i + 1]
            if n.startswith("--") and a.startswith(n + "="):
                return a, a.split("=", 1)[1]
            if not n.startswith("--") and a.startswith(n) and len(a) > len(n):
                return a, a[len(n):]
    return None


def check_gh(keel, run, directory, words, text):
    if len(words) < 2 or words[1] not in GH_COMMANDS:
        return run_refusal(keel, run, text, "a gh alias or extension could run anything; use gh's own commands")
    if words[1] != "pr":
        return None
    sub, args = gh_pr(words)
    if sub in ALWAYS_REFUSED_PR:
        return run_refusal(keel, run, text, f"`gh pr {sub}` is never done inside a run, whatever the grants; landing a PR is the user's")
    if sub == "review" and any(a in ("--approve", "-a") for a in args):
        return run_refusal(keel, run, text, "a run never approves a PR")
    if sub == "edit" and flag_value(args, "--base", "-B"):
        return run_refusal(keel, run, text, "a run never retargets a PR")
    if sub != "create":
        return None
    if "draft-pr" not in run["grants"]:
        return run_refusal(keel, run, text, "the contract does not grant `draft-pr`")
    if "--draft" not in args and "-d" not in args:
        return run_refusal(keel, run, text, "a run opens only draft PRs: add --draft")
    if flag_value(args, "--head", "-H") or flag_value(args, "--repo", "-R") or any(w in GH_VALUED for w in words[2:3]):
        return run_refusal(keel, run, text, "a run's PR is from its own branch, in its own repository: drop --head and --repo")
    base = flag_value(args, "--base", "-B")
    want = subprocess.run([keel, "base", directory], capture_output=True, text=True).stdout.strip() or default_branch(directory)
    if not base or base[1] != want:
        return run_refusal(keel, run, text, f"a run's PR goes into the base: pass --base {want}")
    missing = missing_verdicts(run, directory)
    return run_refusal(keel, run, text, f"it needs {missing}") if missing else None


def check_git(keel, run, directory, verb, args, text, protected_branches):
    grants, branch = run["grants"], run["status"].get("branch", "")
    if verb in NEVER_IN_RUN:
        return run_refusal(keel, run, text, f"a run sends commits only with `git push -u origin HEAD:{branch}`")
    if verb in ("commit", "commit-tree", "update-ref") and "commit" not in grants:
        return run_refusal(keel, run, text, "the contract does not grant `commit`")
    if verb == "commit":
        if any(a.startswith("--amend") for a in args):
            return run_refusal(keel, run, text, "a run never amends a commit")
        if current_branch(directory) != branch:
            return run_refusal(keel, run, text, f"a run commits only on its branch, {branch}")
        return None
    if verb == "update-ref":
        positional, it = [], iter(args)
        for a in it:
            if a in ("-d", "--stdin", "--no-deref", "-z"):
                return run_refusal(keel, run, text, f"a run moves only its own branch, refs/heads/{branch}, one ref at a time")
            if a == "-m":
                next(it, None)
            elif a == "--":
                positional += list(it)
            elif not a.startswith("-"):
                positional.append(a)
        if not positional or positional[0] != f"refs/heads/{branch}":
            return run_refusal(keel, run, text, f"a run moves only its own branch, refs/heads/{branch}")
        return None
    if verb == "branch" and any(a in BRANCH_MOVES or (a.startswith("-") and not a.startswith("--") and set(a[1:]) & set("fmMcCdD")) for a in args):
        return run_refusal(keel, run, text, "a run never moves, copies, renames or deletes a branch")
    if verb == "tag" and any(a in ("-d", "--delete", "-f", "--force") for a in args):
        return run_refusal(keel, run, text, "a run never moves or deletes a tag")
    if verb == "push":
        if any(a.startswith(("--force", "-f", "--delete", "-d", "--mirror", "--all", "--tags", "--prune", "+", ":")) for a in args):
            return run_refusal(keel, run, text, "a run never force-pushes, deletes or pushes more than its branch")
        if "push" not in grants:
            return run_refusal(keel, run, text, "the contract does not grant `push`")
        if args not in (["-u", "origin", f"HEAD:{branch}"], ["-u", "origin", f"HEAD:refs/heads/{branch}"]):
            return run_refusal(keel, run, text, f"a run pushes only its own branch, as `git push -u origin HEAD:{branch}`")
        if branch in protected_branches(directory):
            return run_refusal(keel, run, text, f"{branch} is protected")
        missing = missing_verdicts(run, directory)
        return run_refusal(keel, run, text, f"it needs {missing}") if missing else None
    return None


def check_run(keel, cwd, commands, protected_branches):
    """Returns a refusal when any command in the Bash call breaks a run's
    grants, else None. commands is the call's (directory, argv) list."""
    run_here = contract_run(cwd)
    alone_needed = None
    for directory, argv in commands:
        text = " ".join(argv)
        words, env_aimed = strip_env(argv)
        if not words:
            continue
        if words[0] == "git":
            target, rest, opt_aimed = git_target(directory, words)
            run = contract_run(target) or run_here
            if run is None or not rest:
                continue
            if env_aimed or opt_aimed or target is None:
                if RUN_VERB_TEXT.search(text):
                    return run_refusal(keel, run, text, "git-guard cannot place a git call aimed by GIT_DIR, --git-dir or a cd it cannot follow; run it from the tree")
                continue
            if contract_run(target) is None:
                continue
            verb = rest[0]
            if verb in ALONE:
                alone_needed = alone_needed or (run, text, verb)
            refusal = check_git(keel, run, target, verb, rest[1:], text, protected_branches)
            if refusal:
                return refusal
        elif words[0] == "gh":
            run = contract_run(directory) or run_here
            if run is None:
                continue
            if words[1:3] == ["pr", "create"] or (len(words) > 1 and words[1] == "pr" and gh_pr(words)[0] == "create"):
                alone_needed = alone_needed or (run, text, "gh pr create")
            refusal = check_gh(keel, run, directory or run["tree"], words, text)
            if refusal:
                return refusal
        elif run_here and RUN_VERB_TEXT.search(text):
            return run_refusal(keel, run_here, text, "git-guard cannot see inside this wrapper; run the git or gh step as a plain command")
    if alone_needed and len([c for c in commands if strip_env(c[1])[0]]) > 1:
        run, text, verb = alone_needed
        return run_refusal(keel, run, text, f"in a run, `{verb}` is checked against the tree as it is now, so run it as a Bash call of its own, not chained with other commands")
    return None


def main():
    keel = sys.argv[1]
    event = json.load(sys.stdin)
    command = event.get("tool_input", {}).get("command", "")
    cwd = event.get("cwd") or os.getcwd()
    try:
        calls = [c for d, argv in simple_commands(command, cwd) if (c := git_call(d, argv))]
    except ValueError:
        # Unbalanced quotes, as in a heredoc with an apostrophe: shlex cannot
        # split it, so any line that runs a guarded verb is unplaceable, and
        # in a run so is any line that commits, pushes or opens a PR.
        if any(VERB_TEXT.search(line) for line in command.splitlines()):
            deny("git-guard could not parse this command to tell which branch it moves. Run the git step on its own, with no heredoc in the same command.")
        elif (run := contract_run(cwd)) and any(RUN_VERB_TEXT.search(line) for line in command.splitlines()):
            deny(run_refusal(keel, run, command.splitlines()[0], "git-guard could not parse this command; run the git or gh step on its own"))
        return
    except Unplaceable as e:
        deny(f"git-guard cannot tell which branch `{e}` would move. Run it as a plain `git` command, from the tree or with `git -C <dir>`, not inside a wrapper, substitution or a cd it cannot follow.")
        return
    for directory, verb, args in calls:
        try:
            branch = target_branch(directory, verb, args)
        except Unplaceable as e:
            deny(f"git-guard refuses `{e}`: it can move branches other than the one being rebased, protected ones included.")
            return
        if branch and branch in protected(keel, directory):
            deny(f"`git {verb}` would move {branch}, a protected branch. Merge, rebase, cherry-pick and revert only on a feature branch.")
            return
    refusal = check_run(keel, cwd, list(simple_commands(command, cwd)), lambda d: protected(keel, d))
    if refusal:
        deny(refusal)


if __name__ == "__main__":
    main()

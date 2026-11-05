"""PreToolUse guard for Bash, behind `keel hook git-guard`.

Refuses a merge, rebase, cherry-pick or revert that would move a protected
branch, the list `keel protected` prints for the repository it runs in.
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


def main():
    keel = sys.argv[1]
    event = json.load(sys.stdin)
    command = event.get("tool_input", {}).get("command", "")
    cwd = event.get("cwd") or os.getcwd()
    try:
        calls = [c for d, argv in simple_commands(command, cwd) if (c := git_call(d, argv))]
    except ValueError:
        # Unbalanced quotes, as in a heredoc with an apostrophe: shlex cannot
        # split it, so any line that runs a guarded verb is unplaceable.
        if any(VERB_TEXT.search(line) for line in command.splitlines()):
            deny("git-guard could not parse this command to tell which branch it moves. Run the git step on its own, with no heredoc in the same command.")
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


if __name__ == "__main__":
    main()

"""Says whether a workflow skipped a job on purpose for a pull request.

    python3 -I merge-skip.py <check name> <workflow path> <base ref> <head ref> <event> < workflow.yml

Prints {"explained": true|false, "why": "..."}. A skip is explained when the
job's own `if:` is false from the pull request's own facts, or when a job it
`needs:` was skipped that way, since a job whose dependency was skipped is
skipped too. Anything this cannot read for certain is unexplained, so keel
merge asks rather than guesses: an `if:` that reads anything but the base
ref, head ref and event name, a status function, an `if:` across lines, or a
job it cannot find. It reads only the plain YAML a job's keys are written in,
with no YAML library, and gives up on anything else.
"""

import json
import re
import sys

FACTS = ("github.base_ref", "github.head_ref", "github.event_name")


class Unknown(Exception):
    """A part of the workflow this cannot read for certain."""


def indent(line):
    return len(line) - len(line.lstrip(" "))


def meaningful(line):
    stripped = line.strip()
    return stripped and not stripped.startswith("#")


def strip_comment(value):
    """A value without its trailing comment, outside quotes."""
    quote = None
    for i, ch in enumerate(value):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or value[i - 1] in " \t"):
            return value[:i].rstrip()
    return value.strip()


def unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def read_jobs(lines):
    """{job id: {"line": n, "name": str, "if": (str, n), "needs": [ids]}}"""
    start = next((i for i, l in enumerate(lines) if re.match(r"jobs:\s*(#.*)?$", l)), None)
    if start is None:
        raise Unknown("the workflow has no jobs: key")
    jobs, current, job_indent, key_indent = {}, None, None, None
    i = start + 1
    while i < len(lines):
        line = lines[i]
        if not meaningful(line):
            i += 1
            continue
        if indent(line) == 0:
            break
        if job_indent is None:
            job_indent = indent(line)
        if indent(line) == job_indent:
            m = re.match(r"\s*([A-Za-z_][\w-]*):\s*(#.*)?$", line)
            if not m:
                raise Unknown(f"line {i + 1} is not a job")
            current = jobs[m.group(1)] = {"line": i + 1, "needs": []}
            key_indent = None
        elif indent(line) > job_indent and current is not None:
            if key_indent is None:
                key_indent = indent(line)
            if indent(line) == key_indent:
                m = re.match(r"\s*([\w-]+):\s*(.*)$", line)
                if m:
                    key, value = m.group(1), strip_comment(m.group(2))
                    if key == "name":
                        current["name"] = unquote(value)
                    elif key == "if":
                        # A plain scalar goes on over deeper lines; reading
                        # only the first would judge half the expression.
                        nxt = next((l for l in lines[i + 1:] if meaningful(l)), "")
                        current["if"] = ("|" if indent(nxt) > key_indent else value, i + 1)
                    elif key == "needs":
                        if value.startswith("["):
                            current["needs"] = [unquote(n.strip()) for n in value.strip("[]").split(",") if n.strip()]
                        elif value:
                            current["needs"] = [unquote(value)]
                        else:
                            j = i + 1
                            while j < len(lines) and (not meaningful(lines[j]) or indent(lines[j]) > key_indent):
                                item = re.match(r"\s*-\s*(\S+)", lines[j])
                                if item:
                                    current["needs"].append(unquote(strip_comment(item.group(1))))
                                j += 1
        i += 1
    return jobs


TOKEN = re.compile(r"\s*(?:(\$\{\{|\}\})|('(?:[^']|'')*')|(==|!=|&&|\|\||!|\(|\))|([A-Za-z_][\w.-]*\(?)|(\S))")


def tokens(expr):
    # One ${{ }} around the whole if: is an expression; any other ${{ }} makes
    # it a string template, which is never empty and so always true.
    expr = expr.strip()
    if expr.startswith("${{") and expr.endswith("}}"):
        expr = expr[3:-2]
    out = []
    for m in TOKEN.finditer(expr):
        wrap, string, op, word, other = m.groups()
        if wrap:
            raise Unknown("it mixes ${{ }} with other text")
        if string:
            out.append(("str", string[1:-1].replace("''", "'")))
        elif op:
            out.append(("op", op))
        elif word:
            if word.endswith("("):
                raise Unknown(f"it calls {word[:-1]}()")
            if word in ("true", "false"):
                out.append(("bool", word == "true"))
            elif word in FACTS:
                out.append(("fact", word))
            else:
                raise Unknown(f"it reads {word}")
        elif other:
            raise Unknown(f"it holds {other!r}")
    return out


def evaluate(expr, facts):
    """The value of an if: expression, or Unknown."""
    toks = tokens(expr)
    pos = 0

    def peek():
        return toks[pos] if pos < len(toks) else (None, None)

    def take():
        nonlocal pos
        pos += 1
        return toks[pos - 1]

    def value():
        kind, v = take() if pos < len(toks) else (None, None)
        if kind == "str" or kind == "bool":
            return v
        if kind == "fact":
            return facts[v]
        if (kind, v) == ("op", "!"):
            return not truthy(value())
        if (kind, v) == ("op", "("):
            inner = either()
            if take() != ("op", ")"):
                raise Unknown("its brackets do not close")
            return inner
        raise Unknown("it is not an expression this reads")

    def compare():
        left = value()
        while peek() in (("op", "=="), ("op", "!=")):
            op = take()[1]
            right = value()
            if not (isinstance(left, str) and isinstance(right, str)):
                raise Unknown("it compares other than two strings")
            # GitHub compares strings without regard to case.
            same = left.lower() == right.lower()
            left = same if op == "==" else not same
        return left

    def both():
        left = compare()
        while peek() == ("op", "&&"):
            take()
            right = compare()
            left = truthy(left) and truthy(right)
        return left

    def either():
        left = both()
        while peek() == ("op", "||"):
            take()
            right = both()
            left = truthy(left) or truthy(right)
        return left

    result = either()
    if pos != len(toks):
        raise Unknown("it is not an expression this reads")
    return truthy(result)


def truthy(v):
    return v if isinstance(v, bool) else v != ""


def explain(job_id, jobs, path, facts, seen):
    """(explained, why) for one job."""
    job = jobs[job_id]
    if "if" in job:
        expr, line = job["if"]
        if expr in ("", "|", ">", "|-", ">-", "|+", ">+"):
            raise Unknown(f"{path}:{line}: its if: runs across lines")
        if expr in ("''", '""'):
            raise Unknown(f"{path}:{line}: its if: is empty, which GitHub may read as no condition")
        if not evaluate(expr, facts):
            return True, f"{path}:{line}: if: {expr}"
    for need in job["needs"]:
        if need in jobs and need not in seen:
            try:
                ok, why = explain(need, jobs, path, facts, seen | {need})
            except Unknown:
                continue
            if ok:
                return True, f"needs {need}, {why}"
    return False, "nothing in the workflow skips it for this PR"


def main():
    name, path, base, head, event = sys.argv[1:6]
    facts = {"github.base_ref": base, "github.head_ref": head, "github.event_name": event}
    short = path.rsplit("/", 1)[-1]
    sys.stdin.reconfigure(errors="replace")
    try:
        # GitHub names a job's check by its name:, else by its id.
        jobs = read_jobs(sys.stdin.read().splitlines())
        matches = [j for j, job in jobs.items() if job.get("name", j) == name]
        if len(matches) != 1:
            raise Unknown(f"{short} has {'no' if not matches else 'more than one'} job named {name}")
        ok, why = explain(matches[0], jobs, short, facts, {matches[0]})
    except Unknown as e:
        ok, why = False, f"keel cannot read why: {e}"
    except Exception as e:  # noqa: BLE001 - anything unforeseen asks rather than breaks
        ok, why = False, f"keel cannot read why: {type(e).__name__}: {e}"
    print(json.dumps({"explained": ok, "why": why}))


if __name__ == "__main__":
    main()

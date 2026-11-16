"""`keel stats`: which skills run most, take longest and get rerun, and on which model.

It reads local files only: keel's run folders, verdict history and script
events under the state folder, and Claude Code's transcripts under keel's
config folder, with each session's subagents. It never copies message text
into its output, only counts, run goals and step titles.

A skill is counted from the playbook step that runs it, the `/name` its text
runs "with", "through" or "run"; a step running none counts as
`<playbook> step <n>`, the time before step 1 as the router, and each
keel-verifier spawn as /verify. Tool calls, time and tokens are given to the
step a run had in `doing` when they happened, found from the `keel run start`
and `keel run step <n> doing` calls in the transcript, a `done` or `skip`
with `--next` entering the step after; a subagent counts
toward the step its first message falls in. A skill is also counted when it is
invoked directly, typed as `/name` or called through the agent's Skill tool;
the invocation holds what happens until the next message the user types or
the run's next step, whichever comes first. Each transcript's totals are
cached by its size and mtime, so a second run reads only new ones.

    python3 -I stats.py <state dir> <claude dir> <method dir> [--json] [--since YYYY-MM-DD] [--repo NAME]

`--texts` prints, instead of the counts, the text `keel dash` shows beside
each name: a skill's SKILL.md, a step's line from its playbook, and the
router's method/router.md.
"""

import argparse
import collections
import datetime as dt
import glob
import hashlib
import json
import os
import re
import statistics
import sys
from typing import TypedDict

VERSION = 1
CACHE_VERSION = 8
# A gap between two messages longer than this is idle, not work.
IDLE_S = 1800
# A step runs the skill its text runs "with", "through" or "run"; a step that
# only mentions one, such as "shipping is `/ship`", runs none.
SKILL_RE = re.compile(r"\b(?:with|through|run)\s+`?/([a-z][a-z0-9-]*)(?![\w/.-])")
# A slash command the user typed, as Claude Code records it.
COMMAND_RE = re.compile(r"<command-name>/([a-z][a-z0-9:-]*)</command-name>")
TOKEN_KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
# Each kind of token by the name stats gives it, in TOKEN_KEYS's order. Cache
# reads cost about a tenth of the rest, so a total alone misleads on cost.
KINDS = ("input", "cache_write", "cache_read", "output")
STEP_LINE = re.compile(r"^(\d+)\.\s+(.*)$")
# keel run start, step <n> doing, step <n> done or skip with --next, which
# enters step n+1, and stop, in the order a command runs them; a start's
# --playbook and a step's --next are read within their own part of the command.
RUN_CALL = re.compile(r"keel run (?:start\b[^;&|\n]*?--playbook\s+['\"]?([\w-]+)|step (\d{1,4}) doing\b"
                      r"|step (\d{1,4}) (?:done|skip\b(?:[^;&|\n'\"]|\"[^\"\n]*\"|'[^'\n]*')*?)\s+--next(?![\w-])"
                      r"|(stop)\b)")
# How far a run folder's start may sit outside the call that made it.
SLACK = dt.timedelta(seconds=5)

Counts = dict[str, int]


class Bucket(TypedDict):
    """What one session spent in one playbook step on one day."""

    playbook: str
    step: int
    day: str
    runs: int
    reentries: int
    calls: int
    agent_s: float
    wait_s: float
    session_tokens: int
    subagent_tokens: int
    kinds: Counts
    session_turns: int
    subagent_turns: int
    models: Counts
    subagents: Counts


class Invocation(TypedDict):
    """What one session spent in one skill invoked directly, typed or by the agent, on one day.

    `step` is the playbook step it was invoked in, as `<playbook> <n>`, or empty
    outside a run, so a skill invoked by the step that runs it is not counted twice.
    """

    skill: str
    how: str
    step: str
    day: str
    runs: int
    calls: int
    agent_s: float
    wait_s: float
    session_tokens: int
    subagent_tokens: int
    kinds: Counts
    session_turns: int
    subagent_turns: int
    models: Counts
    subagents: Counts


class Start(TypedDict):
    """A run this session started, and the skill invoked to start it, or the router."""

    playbook: str
    day: str
    by: str


class Verifier(TypedDict):
    """One keel-verifier, and the run it verified, if any."""

    day: str
    run: str | None
    agent_s: float
    tokens: int
    kinds: Counts
    turns: int
    models: Counts


class Session(TypedDict):
    """One transcript's totals, as cached."""

    cwd: str
    lines: int
    unread: int
    buckets: list[Bucket]
    invocations: list[Invocation]
    starts: list[Start]
    verifiers: list[Verifier]


# Where a moment's work goes: ("step", playbook, n, "") or ("inv", skill, how, step).
Target = tuple[str, str, int | str, str]


class Window(TypedDict):
    day: str
    start: dt.datetime
    end: dt.datetime | None
    target: Target
    run: str | None


# Every value read from a file is checked for its type before it is used:
# one that does not fit is counted as unread or left out, never fatal.
def ts(s: str) -> dt.datetime:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def when(value: object) -> dt.datetime | None:
    """A timestamp string with its offset, else None."""
    if not isinstance(value, str):
        return None
    try:
        t = ts(value)
    except ValueError:
        return None
    return t if t.tzinfo is not None else None


def day_of(value: object) -> str | None:
    t = when(value)
    return t.date().isoformat() if t else None


def text(value: object) -> str | None:
    return value if isinstance(value, str) and value else None


# No real count of tokens, milliseconds or exit codes comes near this; a larger
# one is damage, and would overflow the arithmetic done on it.
MAX_COUNT = 10**15


def count(value: object) -> int | None:
    """A whole, non-negative number below MAX_COUNT, else None."""
    return value if isinstance(value, int) and not isinstance(value, bool) and 0 <= value < MAX_COUNT else None


def load_json(path: str) -> object:
    """A JSON file's value, or None when it cannot be read or parsed."""
    try:
        with open(path, errors="replace") as f:
            return json.load(f)
    except (OSError, ValueError, RecursionError):
        return None


def message_of(entry: dict[str, object]) -> dict[str, object]:
    message = entry.get("message")
    return message if isinstance(message, dict) else {}


def usage_of(entry: dict[str, object]) -> Counts:
    """An assistant message's tokens by kind."""
    usage = message_of(entry).get("usage")
    if not isinstance(usage, dict):
        return {}
    return {kind: n for kind, k in zip(KINDS, TOKEN_KEYS) if (n := count(usage.get(k)))}


def is_prompt(entry: dict[str, object]) -> bool:
    """A message the user typed, as opposed to a tool result or injected text."""
    if entry.get("type") != "user" or entry.get("isMeta"):
        return False
    content = message_of(entry).get("content")
    if isinstance(content, str):
        return not content.startswith("<")
    return isinstance(content, list) and not any(
        isinstance(c, dict) and c.get("type") == "tool_result" for c in content
    )


def result_text(content: object) -> str:
    """A tool result's text, whether a string or a list of text blocks."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(t for c in content if isinstance(c, dict) and (t := text(c.get("text"))))
    return ""


def read_entries(path: str) -> tuple[list[dict[str, object]], int, int]:
    """The transcript's timestamped entries, its line count and how many lines did not parse."""
    entries: list[dict[str, object]] = []
    lines = unread = 0
    try:
        with open(path, errors="replace") as f:
            for line in f:
                if not line.strip():
                    continue
                lines += 1
                try:
                    entry = json.loads(line)
                except (ValueError, RecursionError):
                    unread += 1
                    continue
                if not isinstance(entry, dict):
                    unread += 1
                # A record kind with no time, such as a summary, is not a message.
                elif "timestamp" not in entry:
                    continue
                elif readable(entry):
                    entries.append(entry)
                else:
                    unread += 1
    except OSError:
        return [], lines + 1, unread + 1
    return entries, lines, unread


def readable(entry: dict[str, object]) -> bool:
    """A timestamp with its offset, and token counts that are whole, non-negative numbers."""
    if when(entry.get("timestamp")) is None:
        return False
    usage = message_of(entry).get("usage")
    return not isinstance(usage, dict) or all(usage.get(k) is None or count(usage.get(k)) is not None for k in TOKEN_KEYS)


def read_session(path: str, sid: str, starts: dict[str, list[dt.datetime]]) -> Session:
    """Attribute one session's calls, time and tokens, and its subagents', to run steps and invoked skills."""
    entries, lines, unread = read_entries(path)
    buckets: dict[tuple[str, int, str], Bucket] = {}
    invocations: dict[tuple[str, str, str, str], Invocation] = {}
    started: list[Start] = []
    windows: list[Window] = []
    seen: set[str] = set()
    playbook: str | None = None
    step = 0
    run: str | None = None
    entered: set[int] = set()
    runs = 0
    # The skill invoked directly that holds the work now, until the next typed
    # message or the run's next step: (skill, how, the step it was invoked in).
    inv: tuple[str, str, str] | None = None
    inv_day = ""
    prev_t: dt.datetime | None = None
    prev_target: Target | None = None
    cwd = ""
    # Everything a run did is dated by the day it started, so --since keeps or
    # leaves out a run whole, as it does in the playbooks.
    run_day = ""
    pending: dict[str, tuple[str, dt.datetime]] = {}

    def bucket(key: tuple[str, int], day: str) -> Bucket:
        k = (key[0], key[1], day)
        if k not in buckets:
            buckets[k] = Bucket(playbook=k[0], step=k[1], day=k[2], runs=0, reentries=0, calls=0, agent_s=0.0,
                                wait_s=0.0, session_tokens=0, subagent_tokens=0, kinds={}, session_turns=0,
                                subagent_turns=0, models={}, subagents={})
        return buckets[k]

    def invocation(skill: str, how: str, in_step: str, day: str) -> Invocation:
        k = (skill, how, in_step, day)
        if k not in invocations:
            invocations[k] = Invocation(skill=skill, how=how, step=in_step, day=day, runs=0, calls=0, agent_s=0.0,
                                        wait_s=0.0, session_tokens=0, subagent_tokens=0, kinds={}, session_turns=0,
                                        subagent_turns=0, models={}, subagents={})
        return invocations[k]

    def counts_for(target: Target, day: str) -> Bucket | Invocation:
        if target[0] == "inv":
            return invocation(target[1], str(target[2]), target[3], day)
        return bucket((target[1], int(target[2])), day)

    def current() -> Target | None:
        if inv:
            return ("inv", inv[0], inv[1], inv[2])
        return ("step", playbook, step, "") if playbook else None

    def invoke(skill: str, how: str, t: dt.datetime) -> None:
        nonlocal inv, inv_day
        # /verify is counted from the keel-verifiers it spawns; an agent loading
        # the skill the user just typed is that same run.
        if skill == "verify" or (how == "agent" and inv and inv[0] == skill):
            return
        inv = (skill, how, f"{playbook} {step}" if playbook else "")
        inv_day = run_day if playbook else t.date().isoformat()
        invocation(*inv, inv_day)["runs"] += 1

    for entry in entries:
        t = ts(str(entry["timestamp"]))
        if not cwd and isinstance(entry.get("cwd"), str):
            cwd = str(entry["cwd"])
        target = current()
        day = inv_day if inv else run_day
        if target and prev_t and prev_target == target:
            gap = (t - prev_t).total_seconds()
            if gap > 0 and is_prompt(entry):
                counts_for(target, day)["wait_s"] += gap
            elif 0 < gap < IDLE_S:
                counts_for(target, day)["agent_s"] += gap
        message = message_of(entry)
        if target and entry.get("type") == "assistant":
            mid = str(message.get("id") or "")
            if mid and mid not in seen:
                seen.add(mid)
                b = counts_for(target, day)
                used = usage_of(entry)
                n = sum(used.values())
                b["session_tokens"] += n
                b["session_turns"] += 1
                add(b["kinds"], used)
                model = text(message.get("model")) or "unknown"
                b["models"][model] = b["models"].get(model, 0) + n
        content = message.get("content")
        for c in content if isinstance(content, list) else []:
            if not isinstance(c, dict):
                continue
            if c.get("type") == "tool_use" and entry.get("type") == "assistant":
                if target:
                    counts_for(target, day)["calls"] += 1
                tool_input = c.get("input")
                if c.get("name") == "Skill" and isinstance(tool_input, dict) and (skill := text(tool_input.get("skill"))):
                    invoke(skill, "agent", t)
                command = text(tool_input.get("command")) if isinstance(tool_input, dict) else None
                if command and (tid := text(c.get("id"))):
                    pending[tid] = (command, t)
                continue
            asked = pending.pop(text(c.get("tool_use_id")) or "", None) if c.get("type") == "tool_result" else None
            if asked is None:
                continue
            command, asked_at = asked
            # A Bash call that ran reports its failure as "Exit code N", which
            # for a compound command says nothing about keel's part of it; any
            # other error, such as the user denying it or a hook refusing it,
            # means it never ran.
            if c.get("is_error") and not result_text(c.get("content")).lstrip().startswith("Exit code"):
                continue
            for call in RUN_CALL.finditer(command):
                started_pb, n_text, before_next, stopped = call.groups()
                if before_next:
                    n_text = str(int(before_next) + 1)
                # A start counts when a run folder for that playbook began while
                # the call ran, which also rules out a refused start and a command
                # that only mentions one; its output can be redirected away.
                if started_pb and any(asked_at - SLACK <= s <= t + SLACK for s in starts.get(started_pb, [])):
                    runs += 1
                    run_day = t.date().isoformat()
                    started.append(Start(playbook=started_pb, day=run_day, by=inv[0] if inv else "router"))
                    playbook, step, run, entered, inv = started_pb, 0, f"{sid}:{runs}", set(), None
                    bucket((playbook, 0), run_day)["runs"] += 1
                elif n_text and playbook is not None and int(n_text) != step:
                    n = int(n_text)
                    b = bucket((playbook, n), run_day)
                    b["runs"] += 1
                    if n in entered:
                        b["reentries"] += 1
                    entered.add(n)
                    step, inv = n, None
                elif stopped:
                    playbook, run = None, None
        if entry.get("type") == "user" and not entry.get("isMeta"):
            if typed := COMMAND_RE.search(result_text(content)):
                invoke(typed.group(1), "typed", t)
            elif is_prompt(entry):
                inv = None
        new_target = current()
        if new_target != prev_target:
            if windows and windows[-1]["end"] is None:
                windows[-1]["end"] = t
            if new_target:
                windows.append(Window(day=inv_day if inv else run_day, start=t, end=None, target=new_target, run=run))
        prev_t, prev_target = t, new_target
    if windows and windows[-1]["end"] is None:
        windows[-1]["end"] = prev_t

    verifiers: list[Verifier] = []
    for sub in sorted(glob.glob(os.path.join(path[: -len(".jsonl")], "subagents", "*.jsonl"))):
        sub_entries, sub_lines, sub_unread = read_entries(sub)
        lines += sub_lines
        unread += sub_unread
        if not sub_entries:
            continue
        loaded = load_json(sub[: -len(".jsonl")] + ".meta.json")
        kind = (text(loaded.get("agentType")) if isinstance(loaded, dict) else None) or "unknown"
        t0, t1 = ts(str(sub_entries[0]["timestamp"])), ts(str(sub_entries[-1]["timestamp"]))
        window = next((w for w in windows if w["start"] <= t0 <= (w["end"] or t0)), None)
        sub_seen: set[str] = set()
        total = 0
        models: Counts = {}
        kinds: Counts = {}
        for e in sub_entries:
            m = message_of(e)
            mid = str(m.get("id") or "")
            if e.get("type") != "assistant" or not mid or mid in sub_seen:
                continue
            sub_seen.add(mid)
            used = usage_of(e)
            add(kinds, used)
            n = sum(used.values())
            total += n
            model = text(m.get("model")) or "unknown"
            models[model] = models.get(model, 0) + n
        if kind == "keel-verifier":
            verifiers.append(Verifier(day=window["day"] if window else t0.date().isoformat(), run=window["run"] if window else None,
                                      agent_s=min((t1 - t0).total_seconds(), 4 * IDLE_S), tokens=total, kinds=kinds,
                                      turns=len(sub_seen), models=models))
        elif window:
            b = counts_for(window["target"], window["day"])
            b["subagent_tokens"] += total
            b["subagent_turns"] += len(sub_seen)
            add(b["kinds"], kinds)
            b["subagents"][kind] = b["subagents"].get(kind, 0) + 1
            for model, n in models.items():
                b["models"][model] = b["models"].get(model, 0) + n
    return Session(cwd=cwd, lines=lines, unread=unread, buckets=list(buckets.values()),
                   invocations=list(invocations.values()), starts=started, verifiers=verifiers)


def signature(path: str) -> str:
    """Changes whenever the transcript or any of its subagents' files does."""
    parts: list[str] = []
    for p in [path, *sorted(glob.glob(os.path.join(path[: -len(".jsonl")], "subagents", "*")))]:
        st = os.stat(p)
        parts.append(f"{p}:{st.st_size}:{st.st_mtime_ns}")
    return hashlib.sha256("\n".join(parts).encode()).hexdigest()


def well_formed(value: object) -> bool:
    """A cached session in the shape read_session writes; anything else is read again."""
    def counts(x: object) -> bool:
        return isinstance(x, dict) and all(isinstance(k, str) and count(v) is not None for k, v in x.items())

    def number(x: object) -> bool:
        return isinstance(x, (int, float)) and not isinstance(x, bool) and 0 <= x < MAX_COUNT

    if not (isinstance(value, dict) and isinstance(value.get("cwd"), str) and count(value.get("lines")) is not None
            and count(value.get("unread")) is not None and isinstance(value.get("buckets"), list)
            and isinstance(value.get("invocations"), list) and isinstance(value.get("starts"), list)
            and isinstance(value.get("verifiers"), list)):
        return False
    buckets_ok = all(
        isinstance(b, dict) and isinstance(b.get("playbook"), str) and isinstance(b.get("day"), str)
        and count(b.get("step")) is not None and counts(b.get("models")) and counts(b.get("subagents"))
        and counts(b.get("kinds"))
        and all(count(b.get(k)) is not None for k in ("runs", "reentries", "calls", "session_tokens", "subagent_tokens",
                                                       "session_turns", "subagent_turns"))
        and all(number(b.get(k)) for k in ("agent_s", "wait_s"))
        for b in value["buckets"])
    invocations_ok = all(
        isinstance(i, dict) and all(isinstance(i.get(k), str) for k in ("skill", "how", "step", "day"))
        and counts(i.get("models")) and counts(i.get("subagents")) and counts(i.get("kinds"))
        and all(count(i.get(k)) is not None for k in ("runs", "calls", "session_tokens", "subagent_tokens",
                                                       "session_turns", "subagent_turns"))
        and all(number(i.get(k)) for k in ("agent_s", "wait_s"))
        for i in value["invocations"])
    starts_ok = all(isinstance(x, dict) and all(isinstance(x.get(k), str) for k in ("playbook", "day", "by"))
                    for x in value["starts"])
    verifiers_ok = all(
        isinstance(v, dict) and isinstance(v.get("day"), str) and (v.get("run") is None or isinstance(v.get("run"), str))
        and number(v.get("agent_s")) and count(v.get("tokens")) is not None and counts(v.get("models"))
        and counts(v.get("kinds")) and count(v.get("turns")) is not None
        for v in value["verifiers"])
    return buckets_ok and invocations_ok and starts_ok and verifiers_ok


def run_starts(state_dir: str) -> dict[str, list[dt.datetime]]:
    """When each playbook's runs began, from every run folder, live and archived."""
    out: dict[str, list[dt.datetime]] = collections.defaultdict(list)
    for path in glob.glob(os.path.join(state_dir, "runs", "**", "status.json"), recursive=True):
        run = load_json(path)
        if isinstance(run, dict) and (name := text(run.get("playbook"))) and (start := when(run.get("started_at"))):
            out[name].append(start)
    return out


def sessions(claude_dir: str, cache_dir: str, starts: dict[str, list[dt.datetime]]) -> tuple[list[Session], int, int]:
    """Every transcript's totals, from the cache where it is still current."""
    out: list[Session] = []
    read = cached = 0
    os.makedirs(cache_dir, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(claude_dir, "projects", "*", "*.jsonl"))):
        try:
            sig = signature(path)
        except OSError:
            continue
        cache = os.path.join(cache_dir, hashlib.sha256(path.encode()).hexdigest() + ".json")
        hit = load_json(cache)
        if isinstance(hit, dict) and hit.get("v") == CACHE_VERSION and hit.get("sig") == sig and well_formed(hit.get("session")):
            out.append(hit["session"])
            cached += 1
            continue
        session = read_session(path, os.path.basename(path)[: -len(".jsonl")], starts)
        tmp = cache + ".tmp"
        try:
            with open(tmp, "w") as f:
                json.dump({"v": CACHE_VERSION, "sig": sig, "session": session}, f)
            os.replace(tmp, cache)
        except (OSError, ValueError):
            # An unwritable cache only costs the next run a re-read.
            if os.path.exists(tmp):
                os.remove(tmp)
        out.append(session)
        read += 1
    return out, read, cached


def playbook_steps(method_dir: str) -> dict[str, dict[int, str]]:
    """Each playbook's numbered steps, from the playbook files as they are now."""
    out: dict[str, dict[int, str]] = {}
    for path in glob.glob(os.path.join(method_dir, "playbooks", "*.md")):
        name = os.path.basename(path)[: -len(".md")]
        with open(path) as f:
            steps = {int(m.group(1)): m.group(2) for line in f if (m := STEP_LINE.match(line))}
        if steps:
            out[name] = steps
    return out


def skill_of(playbook: str, step: int, steps: dict[str, dict[int, str]]) -> str:
    if step == 0:
        return "router"
    m = SKILL_RE.search(steps.get(playbook, {}).get(step, ""))
    # /verify is counted from keel-verifier spawns alone, so a step that names
    # it counts as the playbook's own step rather than as one more verify run.
    return m.group(1) if m and m.group(1) != "verify" else f"{playbook} step {step}"


class Text(TypedDict):
    """What `keel dash` shows of a name: its lead line, its Markdown, and for a
    playbook step the skill it runs, or empty."""

    lead: str
    text: str
    skill: str


def front_matter(body: str) -> tuple[str, str]:
    """A SKILL.md's description and the Markdown after its front matter."""
    if body.startswith("---\n") and (end := body.find("\n---\n", 3)) != -1:
        m = re.search(r"^description:[ \t]*(.*)$", body[4:end], re.M)
        lead = m.group(1).strip() if m else ""
        if len(lead) > 1 and lead[0] == lead[-1] and lead[0] in "\"'":
            lead = lead[1:-1]
        return lead, body[end + 5:].strip()
    return "", body.strip()


def texts(claude_dir: str, method_dir: str) -> dict[str, Text]:
    """The text of every name keel dash shows: each installed skill, the router,
    each playbook as `playbook <name>` with its purpose as the lead, and each of
    its steps as `<playbook> step <n>` with the skill it runs. A name with a
    space cannot be a skill's, so a playbook and a skill may share a name."""
    out: dict[str, Text] = {}
    for path in sorted(glob.glob(os.path.join(claude_dir, "skills", "*", "SKILL.md"))):
        with open(path) as f:
            lead, body = front_matter(f.read())
        out[os.path.basename(os.path.dirname(path))] = {"lead": lead, "text": body, "skill": ""}
    all_steps = playbook_steps(method_dir)
    for playbook, steps in all_steps.items():
        with open(os.path.join(method_dir, "playbooks", playbook + ".md")) as f:
            body = f.read().strip()
        # The purpose is the first line of prose under the title.
        purpose = next((line.strip() for line in body.splitlines()[1:] if line.strip() and not line.startswith("#")), "")
        out[f"playbook {playbook}"] = {"lead": purpose, "text": "", "skill": ""}
        for n, line in steps.items():
            name = skill_of(playbook, n, all_steps)
            out[f"{playbook} step {n}"] = {"lead": "", "text": line, "skill": "" if name == f"{playbook} step {n}" else name}
    router = os.path.join(method_dir, "router.md")
    if os.path.isfile(router):
        with open(router) as f:
            out["router"] = {"lead": "", "text": f.read().strip(), "skill": ""}
    return out


def in_repo(path: str, repo: str | None) -> bool:
    return repo is None or repo in path.split(os.sep)


def read_json_lines(path: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    try:
        with open(path, errors="replace") as f:
            for line in f:
                try:
                    row = json.loads(line)
                except (ValueError, RecursionError):
                    continue
                if isinstance(row, dict):
                    rows.append(row)
    except OSError:
        pass
    return rows


def add(into: Counts, more: Counts) -> None:
    for k, v in more.items():
        into[k] = into.get(k, 0) + v


def spend(into: "SkillRow | StepRow", b: Bucket | Invocation) -> None:
    """Add a bucket's or invocation's tokens, by where and by kind, and its turns."""
    into["tokens"]["session"] += b["session_tokens"]
    into["tokens"]["subagents"] += b["subagent_tokens"]
    into["turns"]["session"] += b["session_turns"]
    into["turns"]["subagents"] += b["subagent_turns"]
    add(into["tokens_by_kind"], b["kinds"])


class SkillRow(TypedDict, total=False):
    name: str
    where: list[str]
    runs: int
    calls: int
    agent_s: float
    wait_s: float
    tokens: Counts
    tokens_by_kind: Counts
    turns: Counts
    models: Counts
    subagents: Counts
    reruns: int
    how: list[str]
    invoked: Counts
    verify_rounds: Counts


def skills(all_sessions: list[Session], steps: dict[str, dict[int, str]], installed: set[str], since: str,
           repo: str | None) -> list[SkillRow]:
    by: dict[str, SkillRow] = {}
    where: dict[str, set[str]] = collections.defaultdict(set)
    ways: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)

    def entry(name: str) -> SkillRow:
        if name not in by:
            by[name] = SkillRow(name=name, where=[], runs=0, calls=0, agent_s=0.0, wait_s=0.0,
                                tokens={"session": 0, "subagents": 0}, tokens_by_kind=dict.fromkeys(KINDS, 0),
                                turns={"session": 0, "subagents": 0}, models={}, subagents={}, reruns=0,
                                how=[], invoked={"typed": 0, "agent": 0})
        return by[name]

    rounds: collections.Counter[str] = collections.Counter()
    for s in all_sessions:
        if not in_repo(s["cwd"], repo):
            continue
        for b in s["buckets"]:
            if b["day"] < since:
                continue
            name = skill_of(b["playbook"], b["step"], steps)
            e = entry(name)
            where[name].add(f"{b['playbook']} {b['step']}")
            ways[name]["router" if name == "router" else "step"] += b["runs"]
            e["runs"] += b["runs"]
            e["calls"] += b["calls"]
            e["agent_s"] += b["agent_s"]
            e["wait_s"] += b["wait_s"]
            e["reruns"] += b["reentries"]
            spend(e, b)
            add(e["models"], b["models"])
            add(e["subagents"], b["subagents"])
        for i in s["invocations"]:
            if i["day"] < since:
                continue
            playbook, _, n = i["step"].rpartition(" ")
            in_step = skill_of(playbook, int(n), steps) if playbook and n.isdigit() else None
            # Claude Code's own commands and other packs' skills are not keel's
            # library: their time inside a step stays that step's, and outside
            # one it is no skill's.
            name = i["skill"] if i["skill"] in installed else in_step
            if name is None:
                continue
            e = entry(name)
            # The step that runs this skill already counted the run; its time is still the skill's.
            if name != in_step:
                e["runs"] += i["runs"]
                e["invoked"][i["how"]] = e["invoked"].get(i["how"], 0) + i["runs"]
                ways[i["skill"]][i["how"]] += i["runs"]
            e["calls"] += i["calls"]
            e["agent_s"] += i["agent_s"]
            e["wait_s"] += i["wait_s"]
            spend(e, i)
            add(e["models"], i["models"])
            add(e["subagents"], i["subagents"])
        per_run: collections.Counter[str] = collections.Counter()
        for v in s["verifiers"]:
            if v["day"] < since:
                continue
            e = entry("verify")
            where["verify"].add("keel-verifier")
            e["runs"] += 1
            ways["verify"]["verifier"] += 1
            e["agent_s"] += v["agent_s"]
            e["tokens"]["subagents"] += v["tokens"]
            e["turns"]["subagents"] += v["turns"]
            add(e["tokens_by_kind"], v["kinds"])
            add(e["models"], v["models"])
            add(e["subagents"], {"keel-verifier": 1})
            if v["run"]:
                per_run[v["run"]] += 1
        rounds.update(str(n) for n in per_run.values())
    for name, e in by.items():
        e["where"] = sorted(where[name])
        e["how"] = [w for w, _ in ways[name].most_common()]
        e["agent_s"] = round(e["agent_s"])
        e["wait_s"] = round(e["wait_s"])
        if name == "verify":
            e["verify_rounds"] = dict(sorted(rounds.items(), key=lambda kv: int(kv[0])))
    return sorted(by.values(), key=lambda e: (-e["runs"], e["name"]))


def runs(state_dir: str, since: str, repo: str | None) -> list[tuple[dict[str, object], str]]:
    """Every run, live and archived, with its folder."""
    out: list[tuple[dict[str, object], str]] = []
    for path in glob.glob(os.path.join(state_dir, "runs", "**", "status.json"), recursive=True):
        run = load_json(path)
        if not isinstance(run, dict):
            continue
        day = day_of(run.get("started_at"))
        if (day or "") >= since and (day or not since) and in_repo(text(run.get("tree")) or "", repo):
            out.append((run, os.path.dirname(path)))
    return out


class StepRow(TypedDict):
    n: int
    title: str
    skill: str
    done: int
    skipped: int
    open: int
    skip_codes: Counts
    attempts: int
    rerun_runs: int
    attempt_s: float
    entered: int
    agent_s: float
    tokens: Counts
    tokens_by_kind: Counts
    turns: Counts


class PlaybookRow(TypedDict):
    name: str
    runs: int
    states: Counts
    median_minutes: float | None
    versions: int
    started_by: Counts
    steps: list[StepRow]


def playbooks(all_runs: list[tuple[dict[str, object], str]], steps: dict[str, dict[int, str]],
              started_by: dict[str, Counts], spent: dict[tuple[str, int], Bucket]) -> list[PlaybookRow]:
    grouped: dict[str, list[dict[str, object]]] = collections.defaultdict(list)
    for run, _ in all_runs:
        grouped[text(run.get("playbook")) or "unknown"].append(run)
    out: list[PlaybookRow] = []
    for name, rs in sorted(grouped.items()):
        minutes = [(end - start).total_seconds() / 60 for r in rs
                   if (start := when(r.get("started_at"))) and (end := when(r.get("ended_at")))]
        rows: dict[int, StepRow] = {}
        titles: dict[int, collections.Counter[str]] = collections.defaultdict(collections.Counter)
        for r in rs:
            run_steps = r.get("steps")
            for i, s in enumerate(run_steps if isinstance(run_steps, list) else [], 1):
                if not isinstance(s, dict):
                    continue
                if i not in rows:
                    b = spent.get((name, i))
                    rows[i] = StepRow(
                        n=i, title="", skill=skill_of(name, i, steps), done=0, skipped=0, open=0, skip_codes={}, attempts=0,
                        rerun_runs=0, attempt_s=0.0, entered=b["runs"] if b else 0, agent_s=round(b["agent_s"]) if b else 0,
                        tokens={"session": 0, "subagents": 0}, tokens_by_kind=dict.fromkeys(KINDS, 0),
                        turns={"session": 0, "subagents": 0})
                    if b:
                        spend(rows[i], b)
                row = rows[i]
                titles[i][text(s.get("title")) or ""] += 1
                state = s.get("state")
                if state == "done":
                    row["done"] += 1
                elif state == "skipped":
                    row["skipped"] += 1
                    if code := text(s.get("skip_code")):
                        add(row["skip_codes"], {code: 1})
                else:
                    row["open"] += 1
                attempts = s.get("attempts")
                n_attempts = len(attempts) if isinstance(attempts, list) else 0
                row["attempts"] += n_attempts
                row["rerun_runs"] += n_attempts > 1
                for a in attempts if isinstance(attempts, list) else []:
                    if isinstance(a, dict) and (start := when(a.get("started_at"))) and (end := when(a.get("ended_at"))):
                        row["attempt_s"] += (end - start).total_seconds()
        for i, row in rows.items():
            row["title"] = titles[i].most_common(1)[0][0]
            row["attempt_s"] = round(row["attempt_s"])
        out.append(PlaybookRow(
            name=name,
            runs=len(rs),
            states=dict(collections.Counter(text(r.get("state")) or "unknown" for r in rs)),
            median_minutes=round(statistics.median(minutes), 1) if minutes else None,
            versions=len({h for r in rs if (h := text(r.get("playbook_hash")))}),
            started_by=started_by.get(name, {}),
            steps=[rows[i] for i in sorted(rows)],
        ))
    return out


def verdicts(state_dir: str, all_runs: list[tuple[dict[str, object], str]], since: str, repo: str | None) -> tuple[dict[str, Counts], dict[str, object]]:
    """Verdicts per day, and how many verified runs passed their first round.

    A run's verdicts come from its decisions.tsv; verdicts.jsonl adds those
    outside runs, kept since it was introduced. Fails are counted by category
    from verdicts.jsonl alone, in runs and outside them, leaving out those
    recorded before fails had one.
    """
    days: dict[str, Counts] = collections.defaultdict(dict)
    first_pass = verified = 0
    rounds: collections.Counter[str] = collections.Counter()
    for _, folder in all_runs:
        seq: list[str] = []
        try:
            with open(os.path.join(folder, "decisions.tsv"), errors="replace") as f:
                for line in f:
                    cols = line.rstrip("\n").split("\t")
                    verdict = cols[2].split(": ", 1)[1].strip() if len(cols) > 2 and cols[2].startswith("verifier: ") else ""
                    if verdict in ("pass", "fail"):
                        seq.append(verdict)
                        if day := day_of(cols[0]):
                            add(days[day], {verdict: 1})
        except OSError:
            continue
        if seq:
            verified += 1
            first_pass += seq[0] == "pass"
            rounds[str(seq.index("pass") + 1 if "pass" in seq else len(seq))] += 1
    categories: Counts = {}
    for row in read_json_lines(os.path.join(state_dir, "verdicts.jsonl")):
        day, verdict = day_of(row.get("at")), row.get("verdict")
        if not (day and verdict in ("pass", "fail") and in_repo(text(row.get("path")) or "", repo)):
            continue
        in_run = row.get("run_started_at") is not None
        if not in_run and day >= since:
            add(days[day], {str(verdict): 1})
        # A verdict in a run belongs to the day the run started, as the run does.
        counted_day = day_of(row.get("run_started_at")) if in_run else day
        if verdict == "fail" and (category := text(row.get("category"))) and (counted_day or "") >= since:
            add(categories, {category: 1})
    quality = {"verified_runs": verified, "first_pass": first_pass,
               "rounds_to_pass": dict(sorted(rounds.items(), key=lambda kv: int(kv[0]))),
               "fail_categories": dict(sorted(categories.items(), key=lambda kv: (-kv[1], kv[0])))}
    return days, quality


def scripts(state_dir: str, since: str, repo: str | None) -> list[dict[str, object]]:
    by: dict[str, list[dict[str, object]]] = collections.defaultdict(list)
    for row in read_json_lines(os.path.join(state_dir, "events.jsonl")):
        day = day_of(row.get("at"))
        if day and day >= since and in_repo(text(row.get("tree")) or "", repo):
            by[text(row.get("cmd")) or "unknown"].append(row)
    out: list[dict[str, object]] = []
    for cmd, rows in sorted(by.items()):
        reasons = collections.Counter(reason for r in rows if count(r.get("exit")) == 2 and (reason := text(r.get("reason"))))
        ms = [n for r in rows if (n := count(r.get("ms"))) is not None]
        out.append({"cmd": cmd, "calls": len(rows),
                    "exits": dict(collections.Counter(str(n) if (n := count(r.get("exit"))) is not None else "unknown" for r in rows)),
                    "handed_back": [[reason, n] for reason, n in reasons.most_common(5)],
                    "median_ms": round(statistics.median(ms)) if ms else None})
    return out


def report(state_dir: str, claude_dir: str, method_dir: str, since_day: str | None,
           repo: str | None) -> tuple[dict[str, object], list[SkillRow]]:
    since = since_day or ""
    steps = playbook_steps(method_dir)
    all_sessions, read, cached = sessions(claude_dir, os.path.join(state_dir, "stats-cache"), run_starts(state_dir))
    all_runs = runs(state_dir, since, repo)
    days, quality = verdicts(state_dir, all_runs, since, repo)
    for run, _ in all_runs:
        if day := day_of(run.get("started_at")):
            add(days[day], {"runs": 1})
    lines = sum(s["lines"] for s in all_sessions)
    unread = sum(s["unread"] for s in all_sessions)
    installed = {os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(claude_dir, "skills", "*", "SKILL.md"))}
    skill_rows = skills(all_sessions, steps, installed, since, repo)
    # What started each run, and what each step spent, from the transcripts.
    started_by: dict[str, Counts] = collections.defaultdict(dict)
    spent: dict[tuple[str, int], Bucket] = {}

    def step_total(playbook: str, n: int) -> Bucket:
        return spent.setdefault((playbook, n), Bucket(
            playbook=playbook, step=n, day="", runs=0, reentries=0, calls=0, agent_s=0.0,
            wait_s=0.0, session_tokens=0, subagent_tokens=0, kinds={}, session_turns=0, subagent_turns=0,
            models={}, subagents={}))

    def take(t: Bucket, b: Bucket | Invocation) -> None:
        for k in ("session_tokens", "subagent_tokens", "session_turns", "subagent_turns"):
            t[k] += b[k]
        add(t["kinds"], b["kinds"])
        t["agent_s"] += b["agent_s"]
    for s in all_sessions:
        if in_repo(s["cwd"], repo):
            for x in s["starts"]:
                if x["day"] >= since:
                    add(started_by[x["playbook"]], {x["by"] if x["by"] in installed else "router": 1})
            for b in s["buckets"]:
                if b["day"] >= since:
                    t = step_total(b["playbook"], b["step"])
                    t["runs"] += b["runs"]
                    take(t, b)
            # A skill invoked in a step is that step's work when the step runs
            # that same skill or the skill is not keel's, as skills() counts it.
            for i in s["invocations"]:
                playbook, _, n = i["step"].rpartition(" ")
                if (i["day"] >= since and playbook and n.isdigit()
                        and (i["skill"] not in installed or skill_of(playbook, int(n), steps) == i["skill"])):
                    take(step_total(playbook, int(n)), i)
    return {
        "version": VERSION,
        "since": since_day,
        "repo": repo,
        "skills": skill_rows,
        "playbooks": playbooks(all_runs, steps, started_by, spent),
        "scripts": scripts(state_dir, since, repo),
        "verifier": quality,
        "days": [{"day": d, **c} for d, c in sorted(days.items()) if d >= since],
        "transcripts": {"read": read, "cached": cached},
        "unread": {"lines": lines, "unread": unread, "share": round(unread / lines, 4) if lines else 0},
    }, skill_rows


def table(rows: list[SkillRow]) -> str:
    out = [f"{'skill':<26} {'runs':>5} {'agent/run':>10} {'wait/run':>9} {'tokens/run':>11} {'cache%':>6} "
           f"{'turns/run':>9} {'reruns':>6}  model"]
    for s in rows:
        n = max(s["runs"], 1)
        tok = s["tokens"]["session"] + s["tokens"]["subagents"]
        cache = f"{s['tokens_by_kind']['cache_read'] / tok:.0%}" if tok else "-"
        turns = s["turns"]["session"] + s["turns"]["subagents"]
        top = max(s["models"].items(), key=lambda kv: kv[1])[0] if s["models"] else "-"
        out.append(f"{s['name']:<26} {s['runs']:>5} {s['agent_s'] / n / 60:>8.1f}m {s['wait_s'] / n / 60:>7.1f}m "
                   f"{tok / n / 1e6:>10.1f}M {cache:>6} {turns / n:>9.1f} {s['reruns']:>6}  {top}")
    return "\n".join(out)


def main() -> int:
    p = argparse.ArgumentParser(prog="keel stats")
    p.add_argument("state_dir")
    p.add_argument("claude_dir")
    p.add_argument("method_dir")
    p.add_argument("--json", action="store_true")
    p.add_argument("--since", type=lambda s: dt.date.fromisoformat(s).isoformat())
    p.add_argument("--repo")
    p.add_argument("--texts", action="store_true", help="print each listed name's text for keel dash, not the counts")
    args = p.parse_args()
    if args.texts:
        print(json.dumps(texts(str(args.claude_dir), str(args.method_dir))))
        return 0
    # argparse types every attribute as Any; these are the types its arguments declare.
    since: str | None = args.since
    repo: str | None = args.repo
    r, skill_rows = report(str(args.state_dir), str(args.claude_dir), str(args.method_dir), since, repo)
    print(json.dumps(r, indent=1) if args.json else table(skill_rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())

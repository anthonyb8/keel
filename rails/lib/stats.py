"""`keel stats`: which skills run most, take longest and get rerun, and on which model.

It reads local files only: keel's run folders, verdict history and script
events under the state folder, and Claude Code's transcripts under keel's
config folder, with each session's subagents. It never copies message text
into its output, only counts, run goals and step titles.

A skill is counted from the playbook step that runs it: the first `/name` in
the step's text, since a playbook step that runs a skill names it. A step
naming none counts as `<playbook> step <n>`, the time before step 1 as the
router, and each keel-verifier spawn as /verify. Tool calls, time and tokens
are given to the step a run had in `doing` when they happened, found from the
`keel run start` and `keel run step <n> doing` calls in the transcript; a
subagent counts toward the step its first message falls in. Each transcript's
totals are cached by its size and mtime, so a second run reads only new ones.

    python3 -I stats.py <state dir> <claude dir> <method dir> [--json] [--since YYYY-MM-DD] [--repo NAME]
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
CACHE_VERSION = 6
# A gap between two messages longer than this is idle, not work.
IDLE_S = 1800
# The first `/name` in a step's text names the skill it runs; a path such as
# ~/.keel/x or a/b is not one.
SKILL_RE = re.compile(r"(?<![\w./~-])/([a-z][a-z0-9-]*)(?![\w/.-])")
TOKEN_KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
STEP_LINE = re.compile(r"^(\d+)\.\s+(.*)$")
# keel run start, step <n> doing and stop, in the order a command runs them;
# a start's --playbook is read within its own part of the command.
RUN_CALL = re.compile(r"keel run (?:start\b[^;&|\n]*?--playbook\s+['\"]?([\w-]+)|step (\d{1,4}) doing\b|(stop)\b)")
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
    models: Counts
    subagents: Counts


class Verifier(TypedDict):
    """One keel-verifier, and the run it verified, if any."""

    day: str
    run: str | None
    agent_s: float
    tokens: int
    models: Counts


class Session(TypedDict):
    """One transcript's totals, as cached."""

    cwd: str
    lines: int
    unread: int
    buckets: list[Bucket]
    verifiers: list[Verifier]


class Window(TypedDict):
    day: str
    start: dt.datetime
    end: dt.datetime | None
    playbook: str
    step: int
    run: str


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


def tokens(entry: dict[str, object]) -> int:
    usage = message_of(entry).get("usage")
    if not isinstance(usage, dict):
        return 0
    return sum(count(usage.get(k)) or 0 for k in TOKEN_KEYS)


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
    """Attribute one session's calls, time and tokens, and its subagents', to run steps."""
    entries, lines, unread = read_entries(path)
    buckets: dict[tuple[str, int, str], Bucket] = {}
    windows: list[Window] = []
    seen: set[str] = set()
    playbook: str | None = None
    step = 0
    run: str | None = None
    entered: set[int] = set()
    runs = 0
    prev_t: dt.datetime | None = None
    prev_key: tuple[str, int] | None = None
    cwd = ""
    # Everything a run did is dated by the day it started, so --since keeps or
    # leaves out a run whole, as it does in the playbooks.
    run_day = ""
    pending: dict[str, tuple[str, dt.datetime]] = {}

    def bucket(key: tuple[str, int], day: str) -> Bucket:
        k = (key[0], key[1], day)
        if k not in buckets:
            buckets[k] = Bucket(playbook=k[0], step=k[1], day=k[2], runs=0, reentries=0, calls=0, agent_s=0.0,
                                wait_s=0.0, session_tokens=0, subagent_tokens=0, models={}, subagents={})
        return buckets[k]

    for entry in entries:
        t = ts(str(entry["timestamp"]))
        if not cwd and isinstance(entry.get("cwd"), str):
            cwd = str(entry["cwd"])
        key = (playbook, step) if playbook else None
        if key and prev_t and prev_key == key:
            gap = (t - prev_t).total_seconds()
            if gap > 0 and is_prompt(entry):
                bucket(key, run_day)["wait_s"] += gap
            elif 0 < gap < IDLE_S:
                bucket(key, run_day)["agent_s"] += gap
        message = message_of(entry)
        if key and entry.get("type") == "assistant":
            mid = str(message.get("id") or "")
            if mid and mid not in seen:
                seen.add(mid)
                b = bucket(key, run_day)
                n = tokens(entry)
                b["session_tokens"] += n
                model = text(message.get("model")) or "unknown"
                b["models"][model] = b["models"].get(model, 0) + n
        content = message.get("content")
        for c in content if isinstance(content, list) else []:
            if not isinstance(c, dict):
                continue
            if c.get("type") == "tool_use" and entry.get("type") == "assistant":
                if key:
                    bucket(key, run_day)["calls"] += 1
                tool_input = c.get("input")
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
                started, n_text, stopped = call.groups()
                # A start counts when a run folder for that playbook began while
                # the call ran, which also rules out a refused start and a command
                # that only mentions one; its output can be redirected away.
                if started and any(asked_at - SLACK <= s <= t + SLACK for s in starts.get(started, [])):
                    runs += 1
                    playbook, step, run, entered = started, 0, f"{sid}:{runs}", set()
                    run_day = t.date().isoformat()
                    bucket((playbook, 0), run_day)["runs"] += 1
                elif n_text and playbook is not None and int(n_text) != step:
                    n = int(n_text)
                    b = bucket((playbook, n), run_day)
                    b["runs"] += 1
                    if n in entered:
                        b["reentries"] += 1
                    entered.add(n)
                    step = n
                elif stopped:
                    playbook, run = None, None
        new_key = (playbook, step) if playbook else None
        if new_key != prev_key:
            if windows and windows[-1]["end"] is None:
                windows[-1]["end"] = t
            if new_key and run:
                windows.append(Window(day=run_day, start=t, end=None, playbook=new_key[0], step=new_key[1], run=run))
        prev_t, prev_key = t, new_key
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
        for e in sub_entries:
            m = message_of(e)
            mid = str(m.get("id") or "")
            if e.get("type") != "assistant" or not mid or mid in sub_seen:
                continue
            sub_seen.add(mid)
            n = tokens(e)
            total += n
            model = text(m.get("model")) or "unknown"
            models[model] = models.get(model, 0) + n
        if kind == "keel-verifier":
            verifiers.append(Verifier(day=window["day"] if window else t0.date().isoformat(), run=window["run"] if window else None,
                                      agent_s=min((t1 - t0).total_seconds(), 4 * IDLE_S), tokens=total, models=models))
        elif window:
            b = bucket((window["playbook"], window["step"]), window["day"])
            b["subagent_tokens"] += total
            b["subagents"][kind] = b["subagents"].get(kind, 0) + 1
            for model, n in models.items():
                b["models"][model] = b["models"].get(model, 0) + n
    return Session(cwd=cwd, lines=lines, unread=unread, buckets=list(buckets.values()), verifiers=verifiers)


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
            and isinstance(value.get("verifiers"), list)):
        return False
    buckets_ok = all(
        isinstance(b, dict) and isinstance(b.get("playbook"), str) and isinstance(b.get("day"), str)
        and count(b.get("step")) is not None and counts(b.get("models")) and counts(b.get("subagents"))
        and all(count(b.get(k)) is not None for k in ("runs", "reentries", "calls", "session_tokens", "subagent_tokens"))
        and all(number(b.get(k)) for k in ("agent_s", "wait_s"))
        for b in value["buckets"])
    verifiers_ok = all(
        isinstance(v, dict) and isinstance(v.get("day"), str) and (v.get("run") is None or isinstance(v.get("run"), str))
        and number(v.get("agent_s")) and count(v.get("tokens")) is not None and counts(v.get("models"))
        for v in value["verifiers"])
    return buckets_ok and verifiers_ok


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


class SkillRow(TypedDict, total=False):
    name: str
    where: list[str]
    runs: int
    calls: int
    agent_s: float
    wait_s: float
    tokens: Counts
    models: Counts
    subagents: Counts
    reruns: int
    verify_rounds: Counts


def skills(all_sessions: list[Session], steps: dict[str, dict[int, str]], since: str, repo: str | None) -> list[SkillRow]:
    by: dict[str, SkillRow] = {}
    where: dict[str, set[str]] = collections.defaultdict(set)

    def entry(name: str) -> SkillRow:
        if name not in by:
            by[name] = SkillRow(name=name, where=[], runs=0, calls=0, agent_s=0.0, wait_s=0.0,
                                tokens={"session": 0, "subagents": 0}, models={}, subagents={}, reruns=0)
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
            e["runs"] += b["runs"]
            e["calls"] += b["calls"]
            e["agent_s"] += b["agent_s"]
            e["wait_s"] += b["wait_s"]
            e["reruns"] += b["reentries"]
            e["tokens"]["session"] += b["session_tokens"]
            e["tokens"]["subagents"] += b["subagent_tokens"]
            add(e["models"], b["models"])
            add(e["subagents"], b["subagents"])
        per_run: collections.Counter[str] = collections.Counter()
        for v in s["verifiers"]:
            if v["day"] < since:
                continue
            e = entry("verify")
            where["verify"].add("keel-verifier")
            e["runs"] += 1
            e["agent_s"] += v["agent_s"]
            e["tokens"]["subagents"] += v["tokens"]
            add(e["models"], v["models"])
            add(e["subagents"], {"keel-verifier": 1})
            if v["run"]:
                per_run[v["run"]] += 1
        rounds.update(str(n) for n in per_run.values())
    for name, e in by.items():
        e["where"] = sorted(where[name])
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


class PlaybookRow(TypedDict):
    name: str
    runs: int
    states: Counts
    median_minutes: float | None
    versions: int
    steps: list[StepRow]


def playbooks(all_runs: list[tuple[dict[str, object], str]], steps: dict[str, dict[int, str]]) -> list[PlaybookRow]:
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
                row = rows.setdefault(i, StepRow(n=i, title="", skill=skill_of(name, i, steps), done=0, skipped=0,
                                                 open=0, skip_codes={}, attempts=0, rerun_runs=0, attempt_s=0.0))
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
            steps=[rows[i] for i in sorted(rows)],
        ))
    return out


def verdicts(state_dir: str, all_runs: list[tuple[dict[str, object], str]], since: str, repo: str | None) -> tuple[dict[str, Counts], dict[str, object]]:
    """Verdicts per day, and how many verified runs passed their first round.

    A run's verdicts come from its decisions.tsv; verdicts.jsonl adds those
    outside runs, kept since it was introduced.
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
    for row in read_json_lines(os.path.join(state_dir, "verdicts.jsonl")):
        day, verdict = day_of(row.get("at")), row.get("verdict")
        if (row.get("run_started_at") is None and day and day >= since and verdict in ("pass", "fail")
                and in_repo(text(row.get("path")) or "", repo)):
            add(days[day], {str(verdict): 1})
    quality = {"verified_runs": verified, "first_pass": first_pass,
               "rounds_to_pass": dict(sorted(rounds.items(), key=lambda kv: int(kv[0])))}
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
    skill_rows = skills(all_sessions, steps, since, repo)
    return {
        "version": VERSION,
        "since": since_day,
        "repo": repo,
        "skills": skill_rows,
        "playbooks": playbooks(all_runs, steps),
        "scripts": scripts(state_dir, since, repo),
        "verifier": quality,
        "days": [{"day": d, **c} for d, c in sorted(days.items()) if d >= since],
        "transcripts": {"read": read, "cached": cached},
        "unread": {"lines": lines, "unread": unread, "share": round(unread / lines, 4) if lines else 0},
    }, skill_rows


def table(rows: list[SkillRow]) -> str:
    out = [f"{'skill':<26} {'runs':>5} {'agent/run':>10} {'wait/run':>9} {'tokens/run':>11} {'reruns':>6}  model"]
    for s in rows:
        n = max(s["runs"], 1)
        tok = s["tokens"]["session"] + s["tokens"]["subagents"]
        top = max(s["models"].items(), key=lambda kv: kv[1])[0] if s["models"] else "-"
        out.append(f"{s['name']:<26} {s['runs']:>5} {s['agent_s'] / n / 60:>8.1f}m {s['wait_s'] / n / 60:>7.1f}m "
                   f"{tok / n / 1e6:>10.1f}M {s['reruns']:>6}  {top}")
    return "\n".join(out)


def main() -> int:
    p = argparse.ArgumentParser(prog="keel stats")
    p.add_argument("state_dir")
    p.add_argument("claude_dir")
    p.add_argument("method_dir")
    p.add_argument("--json", action="store_true")
    p.add_argument("--since", type=lambda s: dt.date.fromisoformat(s).isoformat())
    p.add_argument("--repo")
    args = p.parse_args()
    # argparse types every attribute as Any; these are the types its arguments declare.
    since: str | None = args.since
    repo: str | None = args.repo
    r, skill_rows = report(str(args.state_dir), str(args.claude_dir), str(args.method_dir), since, repo)
    print(json.dumps(r, indent=1) if args.json else table(skill_rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""A stand-in for Linear's GraphQL API, for tests/run.sh.

Answers each request by what its query asks for, appends the request's JSON
body to the log file, and refuses any request whose Authorization header is
not the expected key, the way Linear answers a bad key.

    python3 -I linear-stub.py <port file> <log file> <expected key>
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT_FILE, LOG, KEY = sys.argv[1], sys.argv[2], sys.argv[3]

# Each project's issues, in the order Linear lists them, with what relates to
# each: keel's ANB-12 is blocked by ANB-40, outside the project, and ANB-9 is
# only a duplicate of ANB-12, which orders nothing; loop's two issues block
# each other; teams spans two teams with the same number.
PROJECT_ISSUES = {
    "keel": [("ANB-10", [("blocks", "ANB-12")]), ("ANB-11", [("blocks", "ANB-10")]),
             ("ANB-12", [("blocks", "ANB-40")]), ("ANB-9", [("duplicate", "ANB-12")])],
    "loop": [("ANB-1", [("blocks", "ANB-2")]), ("ANB-2", [("blocks", "ANB-1")])],
    "teams": [("OTH-5", []), ("ANB-5", [])],
    "P-ANB-7": [],
}


# Each project code Linear knows, and the project it names; P-ANB-7 is also
# another project's name, which wins.
PROJECT_CODES = {"P-ANB-12": "keel", "P-ANB-7": "keel"}
# keel issue begin's issues: each one's state and the issues blocking it, each
# blocker as (identifier, state name, state type, project).
BEGIN_ISSUES = {
    "ANB-12": ("Backlog", [("ANB-8", "Done", "completed", "keel")]),
    "ANB-60": ("In Review", []),
    "ANB-61": ("Todo", [("ANB-62", "Todo", "unstarted", "other")]),
    "ANB-63": ("In Progress", [("ANB-62", "Todo", "unstarted", "keel")]),
    "ANB-64": ("Triage", []),
    "ANB-65": ("Todo", [("ANB-66", "Todo", "unstarted", "keel")]),
}
# Each issue's state now, for update --only-from; any other issue is in Backlog.
STATE_NOW = {"ANB-70": "In Progress"}


def answer(query, variables):
    if "IssueBegin" in query:
        if variables["id"] not in BEGIN_ISSUES:
            return None
        state, blockers = BEGIN_ISSUES[variables["id"]]
        return {"issue": {"identifier": variables["id"], "branchName": "x/" + variables["id"].lower() + "-foo",
                          "state": {"name": state}, "project": {"name": "keel"},
                          "inverseRelations": {"nodes": [{"type": "blocks", "issue": {
                              "identifier": i, "state": {"name": n, "type": t}, "project": {"name": p}}}
                              for i, n, t, p in blockers]}}}
    if "issueCreate" in query:
        return {"issueCreate": {"issue": {"id": "uuid-ANB-99", "identifier": "ANB-99", "url": "https://linear.test/ANB-99"}}}
    if "issueUpdate" in query:
        return {"issueUpdate": {"issue": {"identifier": variables["id"], "state": {"name": "Canceled"}}}}
    if "commentCreate" in query:
        return {"commentCreate": {"comment": {"url": "https://linear.test/comment/1"}}}
    if "issueRelationCreate" in query:
        return {"issueRelationCreate": {"success": True}}
    if "projectCreate" in query or "projectUpdate" in query:
        op = "projectCreate" if "projectCreate" in query else "projectUpdate"
        return {op: {"project": {"name": variables.get("name", "keel"), "url": "https://linear.test/project/keel"}}}
    if "projects(" in query or "project(id" in query:
        # A project by name, or by its code, which only keel's is given here;
        # Linear answers an unknown code with an error, as for an unknown issue.
        name = variables["name"] if "projects(" in query else PROJECT_CODES.get(variables["id"])
        if name is None:
            return None
        if name not in PROJECT_ISSUES:
            return {"projects": {"nodes": []}}
        issues = [{"identifier": i, "title": "t" + i, "state": {"name": "Todo"},
                   "inverseRelations": {"nodes": [{"type": t, "issue": {"identifier": b}} for t, b in by]}}
                  for i, by in PROJECT_ISSUES[name]]
        project = {"id": "project-" + name, "name": name, "description": "s",
                   "content": "c", "url": "u", "state": "started", "issues": {"nodes": issues}}
        return {"projects": {"nodes": [project]}} if "projects(" in query else {"project": project}
    if "issues(" in query:
        return {"issues": {"nodes": [{"identifier": "ANB-31", "title": "keel skeleton", "url": "u", "state": {"name": "Todo"}}]}}
    if "teams(" in query:
        nodes = [{"id": "team-" + variables["key"]}] if variables["key"] in ("ANB", "OTH") else []
        return {"teams": {"nodes": nodes}, "organization": {"name": "Stub Org"}}
    if "states" in query:
        return {"issue": {"state": {"name": STATE_NOW.get(variables["id"], "Backlog")},
                          "team": {"states": {"nodes": [{"id": "state-todo", "name": "Todo"},
                                                        {"id": "state-in-progress", "name": "In Progress"},
                                                        {"id": "state-canceled", "name": "Canceled"}]}}}}
    if "issue(" in query:
        if variables["id"] == "ANB-404":
            return None
        if "relations" in query:
            return {"issue": {"identifier": variables["id"], "title": "stub", "project": {"name": "keel"},
                              "relations": {"nodes": [{"type": "blocks", "relatedIssue": {"identifier": "ANB-32"}}]}}}
        return {"issue": {"id": "uuid-" + variables["id"]}}
    return None


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(LOG, "a") as log:
            log.write(json.dumps(body) + "\n")
        if self.headers.get("Authorization") != KEY:
            self.reply(400, {"errors": [{"message": "Authentication required, not authenticated"}]})
            return
        data = answer(body["query"], body.get("variables") or {})
        if data is None:
            self.reply(200, {"errors": [{"message": "Entity not found"}], "data": None})
        else:
            self.reply(200, {"data": data})

    def reply(self, code, payload):
        out = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()

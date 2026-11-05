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


def answer(query, variables):
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
    if "issues(" in query:
        return {"issues": {"nodes": [{"identifier": "ANB-31", "title": "keel skeleton", "url": "u", "state": {"name": "Todo"}}]}}
    if "teams(" in query:
        nodes = [{"id": "team-" + variables["key"]}] if variables["key"] in ("ANB", "OTH") else []
        return {"teams": {"nodes": nodes}, "organization": {"name": "Stub Org"}}
    if "projects(" in query:
        if variables["name"] != "keel":
            return {"projects": {"nodes": []}}
        return {"projects": {"nodes": [{"id": "project-keel", "name": "keel", "description": "s", "content": "c",
                                        "url": "u", "state": "started", "issues": {"nodes": []}}]}}
    if "states" in query:
        return {"issue": {"team": {"states": {"nodes": [{"id": "state-todo", "name": "Todo"},
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

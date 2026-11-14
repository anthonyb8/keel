"""Serve one file once on 127.0.0.1, for `keel dash` on a server reached over SSH.

`tether open` hands only http and https URLs to the laptop's browser, where
localhost is the server, so the page has to be served rather than opened as a
file. This binds a free port on 127.0.0.1, prints the URL, and detaches; the
detached process serves the file and exits after its first successful GET, or
after the timeout if nothing fetches it, so nothing outlives its use.

    python3 -I serve-once.py <file> [timeout seconds]
"""

import http.server
import os
import sys
import threading

TIMEOUT_S = 120


class Handler(http.server.BaseHTTPRequestHandler):
    body: bytes = b""
    served = threading.Event()

    def do_GET(self) -> None:  # the name http.server calls
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(self.body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(self.body)
        Handler.served.set()

    def log_message(self, format: str, *args: object) -> None:
        pass


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("usage: serve-once.py <file> [timeout seconds]", file=sys.stderr)
        return 2
    with open(sys.argv[1], "rb") as f:
        Handler.body = f.read()
    timeout = float(sys.argv[2]) if len(sys.argv) == 3 else TIMEOUT_S
    # Each connection gets its own thread, so one that sends nothing, such as
    # a browser's preconnect, cannot hold up the page or the exit.
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print(f"http://localhost:{server.server_address[1]}/", flush=True)
    # Detach, so keel dash returns at once and the server holds no terminal.
    if os.fork():
        return 0
    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    Handler.served.wait(timeout)
    return 0


if __name__ == "__main__":
    sys.exit(main())

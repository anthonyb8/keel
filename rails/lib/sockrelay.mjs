#!/usr/bin/env node
// Relays TCP ports across a network namespace boundary through Unix sockets in
// a directory both sides mount, then runs a command and exits with its code.
//
//   sockrelay.mjs host  <dir> <port>... -- <command...>
//   sockrelay.mjs guest <dir> <port>... -- <command...>
//
// `host` listens on <dir>/<port>.sock for each port and connects each client
// to localhost:<port>. `guest` runs inside a container on `--network none`: it
// listens on 127.0.0.1:<port>, and on [::1]:<port> where the namespace has
// IPv6, connecting each client to <dir>/<port>.sock. A socket file crosses a
// bind mount where TCP to the host would need a firewall rule for the Docker
// bridges, and the namespace never sees a host interface come or go.
//
// The app also loads from the internet, such as OCR models from a CDN, so the
// host side serves an HTTP proxy on <dir>/egress.sock, and the guest relays it
// to 127.0.0.1:EGRESS_PORT and points the command's https_proxy and
// http_proxy at it. Loopback stays direct.
import { spawn } from "node:child_process";
import { rmSync } from "node:fs";
import { createServer as createHttpServer, request } from "node:http";
import { connect, createServer } from "node:net";
import { join } from "node:path";

const EGRESS_PORT = 3128;

const [side, dir, ...rest] = process.argv.slice(2);
const split = rest.indexOf("--");
const ports = (split < 0 ? rest : rest.slice(0, split)).map(Number);
const command = split < 0 ? [] : rest.slice(split + 1);

if (
  !["host", "guest"].includes(side) ||
  !dir ||
  ports.length === 0 ||
  ports.some((p) => !Number.isInteger(p) || p <= 0 || p === EGRESS_PORT) ||
  command.length === 0
) {
  console.error(
    `usage: sockrelay.mjs host|guest <dir> <port>... -- <command...> (never port ${EGRESS_PORT})`,
  );
  process.exit(2);
}

const socketPath = (name) => join(dir, `${name}.sock`);

function pipe(client, upstream) {
  client.pipe(upstream).pipe(client);
  // Either end closing or failing closes the other, so a refused upstream
  // reads to the browser as a reset connection rather than a hang.
  const close = () => {
    client.destroy();
    upstream.destroy();
  };
  client.on("error", close);
  upstream.on("error", close);
  client.on("close", close);
  upstream.on("close", close);
}

function listen(server, options) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(options, () => {
      server.off("error", reject);
      resolve();
    });
  });
}

async function serveHost(port) {
  const path = socketPath(port);
  rmSync(path, { force: true });
  const server = createServer((client) =>
    pipe(client, connect({ host: "localhost", port, autoSelectFamily: true })),
  );
  await listen(server, { path });
}

// A forward proxy: CONNECT for https, absolute-form requests for plain http.
async function serveEgress() {
  const path = socketPath("egress");
  rmSync(path, { force: true });
  const proxy = createHttpServer((req, res) => {
    let target;
    try {
      target = new URL(req.url);
    } catch {
      res.writeHead(400).end();
      return;
    }
    const upstream = request(
      {
        host: target.hostname,
        port: target.port || 80,
        path: `${target.pathname}${target.search}`,
        method: req.method,
        headers: req.headers,
        autoSelectFamily: true,
      },
      (reply) => {
        res.writeHead(reply.statusCode ?? 502, reply.headers);
        reply.pipe(res);
      },
    );
    upstream.on("error", () => res.destroy());
    req.pipe(upstream);
  });
  proxy.on("connect", (req, client, head) => {
    const match = /^\[?([^\]]+?)\]?:(\d+)$/.exec(req.url ?? "");
    if (!match) {
      client.end("HTTP/1.1 400 Bad Request\r\n\r\n");
      return;
    }
    const upstream = connect(
      { host: match[1], port: Number(match[2]), autoSelectFamily: true },
      () => {
        client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
        if (head.length) upstream.write(head);
        pipe(client, upstream);
      },
    );
    upstream.once("error", () => client.destroy());
  });
  await listen(proxy, { path });
}

async function relayGuest(port, name) {
  const handle = (client) => pipe(client, connect({ path: socketPath(name) }));
  await listen(createServer(handle), { host: "127.0.0.1", port });
  try {
    await listen(createServer(handle), { host: "::1", port, ipv6Only: true });
  } catch (error) {
    // A namespace without IPv6 has no ::1, and Chrome then resolves localhost
    // to 127.0.0.1 alone.
    if (!["EADDRNOTAVAIL", "EAFNOSUPPORT"].includes(error.code)) throw error;
  }
}

let env = process.env;
if (side === "host") {
  await Promise.all([...ports.map(serveHost), serveEgress()]);
} else {
  await Promise.all([
    ...ports.map((port) => relayGuest(port, port)),
    relayGuest(EGRESS_PORT, "egress"),
  ]);
  const proxy = `http://127.0.0.1:${EGRESS_PORT}`;
  env = {
    ...process.env,
    https_proxy: proxy,
    http_proxy: proxy,
    no_proxy: "localhost,127.0.0.1,::1",
  };
}

const child = spawn(command[0], command.slice(1), { stdio: "inherit", env });
for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(signal, () => child.kill(signal));
}
child.on("error", (error) => {
  console.error(`sockrelay: ${command[0]}: ${error.message}`);
  process.exit(127);
});
child.on("exit", (code, signal) => {
  if (side === "host") {
    for (const name of [...ports, "egress"]) {
      rmSync(socketPath(name), { force: true });
    }
  }
  process.exit(code ?? (signal ? 128 : 1));
});

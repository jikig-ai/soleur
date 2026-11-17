#!/usr/bin/env node
// Egress injector spike (#12517): the per-session CONNECT router (CTO R24, R26). Test path only.
//
// iron-proxy v0.56.0 terminates every tunnel it is given (tracer item 2), so this router decides which tunnels reach
// it: exact github.com, api.github.com, uploads.github.com and codeload.github.com on port 443 go to that session's
// iron-proxy `tunnel_listen` with a router-only credential; an inject name on any other port is refused 403; every
// other CONNECT (other *.github.com names, IP literals, the Anthropic API, the open web) goes unchanged to the real
// egress forwarder with the forwarder credential, so it is tunneled and never terminated.
//
// It never terminates TLS and never logs a header value. The bounded head parse mirrors egress-forwarder.mjs
// (16 KiB cap, incremental delimiter search). The session credential is required on every CONNECT (407 without it)
// and stripped; the client's other headers are not forwarded.
//
// Run: connect-router.mjs <config.json>   (secrets come from files named in the config, never env or argv; R10)
import { timingSafeEqual } from "node:crypto";
import { readFileSync } from "node:fs";
import net from "node:net";
import { pathToFileURL } from "node:url";

export const HEAD_CAP = 16 * 1024;
export const INJECT_HOSTS = Object.freeze(["github.com", "api.github.com", "uploads.github.com", "codeload.github.com"]);
const HEADER_END = Buffer.from("\r\n\r\n");
const DNS_RE = /^[a-z0-9](?:[a-z0-9-]{0,62})(?:\.[a-z0-9](?:[a-z0-9-]{0,62}))*$/;
const IPV4_RE = /^(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;
const STATUS_TEXT = { 400: "Bad Request", 403: "Forbidden", 405: "Method Not Allowed", 407: "Proxy Authentication Required", 431: "Request Header Fields Too Large", 502: "Bad Gateway" };

/** Accumulates bytes until the blank line that ends the CONNECT head, refusing past HEAD_CAP. */
export function createHeadReader(cap = HEAD_CAP) {
  const chunks = [];
  let len = 0;
  let tail = Buffer.alloc(0);
  return {
    push(chunk) {
      chunks.push(chunk);
      len += chunk.length;
      const win = tail.length ? Buffer.concat([tail, chunk]) : chunk;
      if (win.indexOf(HEADER_END) === -1) {
        if (len > cap) return { state: "too-large" };
        tail = win.length > 3 ? win.subarray(win.length - 3) : win;
        return { state: "need-more" };
      }
      const buf = Buffer.concat(chunks);
      const end = buf.indexOf(HEADER_END);
      if (end > cap) return { state: "too-large" };
      return { state: "done", head: buf.subarray(0, end).toString("latin1"), rest: buf.subarray(end + HEADER_END.length) };
    },
  };
}

export function normalizeHost(raw) {
  const h = String(raw).toLowerCase();
  return h.endsWith(".") ? h.slice(0, -1) : h;
}

/** Parse a CONNECT head. `{ok:false, status}` for anything the router must refuse before authentication. */
export function parseConnectHead(head) {
  const lines = String(head).split("\r\n");
  const m = lines[0].match(/^([A-Za-z]+) (\S+) HTTP\/1\.[01]$/);
  if (!m) return { ok: false, status: 400 };
  const method = m[1].toUpperCase();
  if (method !== "CONNECT") return { ok: false, status: 405 };

  const target = m[2];
  let host;
  let portStr;
  let ip = false;
  const v6 = target.match(/^\[([0-9A-Fa-f:.]+)\]:([0-9]+)$/);
  if (v6) {
    if (!net.isIPv6(v6[1])) return { ok: false, status: 400 };
    host = v6[1].toLowerCase();
    portStr = v6[2];
    ip = true;
  } else {
    const hp = target.match(/^([^:]+):([0-9]+)$/);
    if (!hp) return { ok: false, status: 400 };
    portStr = hp[2];
    if (IPV4_RE.test(hp[1])) {
      host = hp[1];
      ip = true;
    } else {
      host = normalizeHost(hp[1]);
      if (!DNS_RE.test(host)) return { ok: false, status: 400 };
    }
  }
  if (!/^[0-9]{1,5}$/.test(portStr)) return { ok: false, status: 400 };
  const port = Number(portStr);
  if (port < 1 || port > 65535) return { ok: false, status: 400 };

  const proxyAuthorization = lines
    .slice(1)
    .filter((l) => /^proxy-authorization:/i.test(l))
    .map((l) => l.slice(l.indexOf(":") + 1).trim());
  return {
    ok: true,
    method,
    host,
    port,
    ip,
    proxyAuthorization: proxyAuthorization.length === 1 ? proxyAuthorization[0] : proxyAuthorization.length ? proxyAuthorization : undefined,
  };
}

/** R24: exact-match the four inject hosts on 443; refuse an inject name on another port; forward everything else. */
export function routeConnect(p, injectHosts = INJECT_HOSTS) {
  if (!p.ip && injectHosts.includes(p.host)) {
    return p.port === 443 ? { branch: "injector" } : { branch: "refused", status: 403 };
  }
  return { branch: "forwarder" };
}

/** Basic credentials whose password equals `expected` (any user name), compared in constant time. */
export function checkProxyAuthorization(value, expected) {
  if (typeof expected !== "string" || expected === "") throw new Error("checkProxyAuthorization: expected credential required");
  if (typeof value !== "string") return false; // absent, or more than one header
  const m = value.match(/^basic[ \t]+([A-Za-z0-9+/=]+)$/i);
  if (!m) return false;
  const decoded = Buffer.from(m[1], "base64").toString("utf8");
  const colon = decoded.indexOf(":");
  if (colon === -1) return false;
  const got = Buffer.from(decoded.slice(colon + 1), "utf8");
  const want = Buffer.from(expected, "utf8");
  return got.length === want.length && timingSafeEqual(got, want);
}

/** The head sent upstream: the normalized target, a Host line, the upstream credential. Nothing else is forwarded. */
export function rewriteHead(p, upstreamAuthorization) {
  const authority = p.ip && p.host.includes(":") ? `[${p.host}]:${p.port}` : `${p.host}:${p.port}`;
  return `CONNECT ${authority} HTTP/1.1\r\nHost: ${authority}\r\nProxy-Authorization: ${upstreamAuthorization}\r\n\r\n`;
}

function reply(sock, status, extra = "") {
  sock.end(`HTTP/1.1 ${status} ${STATUS_TEXT[status] ?? "Error"}\r\n${extra}Content-Length: 0\r\nConnection: close\r\n\r\n`);
}

/**
 * opts: { sessionCredential, injector: {host, port, credential}, forwarder: {host, port, credential}, log, sessionId,
 *         injectHosts? }. `credential` is the full Proxy-Authorization value sent upstream.
 */
export function createRouter(opts) {
  if (!opts?.sessionCredential) throw new Error("createRouter: sessionCredential required");
  const log = opts.log ?? (() => {});
  const sid = String(opts.sessionId ?? "session").replace(/[^A-Za-z0-9._-]/g, "_");
  const record = (fields) => log(`SOLEUR_EGRESS_ROUTE session=${sid} ${fields}`);

  return net.createServer((client) => {
    client.on("error", () => client.destroy());
    const reader = createHeadReader();
    const onData = (chunk) => {
      const r = reader.push(chunk);
      if (r.state === "need-more") return;
      client.off("data", onData);
      if (r.state === "too-large") {
        record("branch=refused status=431");
        reply(client, 431);
        return;
      }
      const p = parseConnectHead(r.head);
      if (!p.ok) {
        record(`branch=refused status=${p.status}`);
        reply(client, p.status);
        return;
      }
      const where = `host=${p.ip && p.host.includes(":") ? `[${p.host}]` : p.host} port=${p.port}`;
      if (!checkProxyAuthorization(p.proxyAuthorization, opts.sessionCredential)) {
        record(`branch=refused status=407 ${where}`);
        reply(client, 407, 'Proxy-Authenticate: Basic realm="soleur-router"\r\n');
        return;
      }
      const route = routeConnect(p, opts.injectHosts ?? INJECT_HOSTS);
      if (route.branch === "refused") {
        record(`branch=refused status=${route.status} ${where}`);
        reply(client, route.status);
        return;
      }
      const up = route.branch === "injector" ? opts.injector : opts.forwarder;
      record(`branch=${route.branch} ${where}`);
      client.pause();
      const upstream = net.connect(up.port, up.host, () => {
        upstream.write(rewriteHead(p, up.credential));
        if (r.rest.length) upstream.write(r.rest);
        client.pipe(upstream);
        upstream.pipe(client);
        client.resume();
      });
      upstream.on("error", () => client.destroy());
      client.on("close", () => upstream.destroy());
      upstream.on("close", () => client.destroy());
    };
    client.on("data", onData);
  });
}

function basicFromFile(path) {
  const userPass = readFileSync(path, "utf8").trim();
  if (!userPass.includes(":")) throw new Error(`credential file ${path} must hold user:password`);
  return "Basic " + Buffer.from(userPass, "utf8").toString("base64");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv[2]) {
    console.error("usage: connect-router.mjs <config.json>");
    process.exit(64);
  }
  const cfg = JSON.parse(readFileSync(process.argv[2], "utf8"));
  const sessionUserPass = readFileSync(cfg.sessionCredentialFile, "utf8").trim();
  const server = createRouter({
    sessionCredential: sessionUserPass.slice(sessionUserPass.indexOf(":") + 1),
    injector: { host: cfg.injector.host, port: cfg.injector.port, credential: basicFromFile(cfg.injector.credentialFile) },
    forwarder: { host: cfg.forwarder.host, port: cfg.forwarder.port, credential: basicFromFile(cfg.forwarder.credentialFile) },
    sessionId: cfg.sessionId,
    log: (l) => console.log(l),
  });
  // ppid watchdog, as in egress-forwarder.mjs: if the suite (our parent) dies, so do we.
  setInterval(() => {
    try {
      process.kill(process.ppid, 0);
    } catch {
      process.exit(0);
    }
  }, 5000).unref();
  server.listen(cfg.listenPort ?? 0, cfg.listenHost ?? "127.0.0.1", () => {
    console.log(`connect-router-listening ${server.address().port}`);
  });
}

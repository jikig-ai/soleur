#!/usr/bin/env node
// Egress injector spike (#12517): hermetic stub destinations (CTO F-f). Test path only.
//
// One TLS listener, serving a leaf (signed by the suite's TEST UPSTREAM root, never a public CA) whose SANs name
// github.com, api.github.com, uploads.github.com, codeload.github.com and the non-inject stub api.anthropic.com.
// iron-proxy verifies it against that root with verification on (tracer item 4).
//
//   github.com           git smart HTTP through the real `git http-backend` (CGI) over synthetic bare repositories
//                        the suite creates; push is enabled per repository (http.receivepack)
//   api.github.com       a REST and GraphQL stub (fixed JSON; no real content)
//   uploads/codeload     a fixed small body
//   api.anthropic.com    GET /sse streams 50 server-sent events (criterion 2's non-inject SSE); never an inject host
//
// Every request appends one JSON line to the record file: host, method, path (no query values), the Authorization
// CLASS (`real-decoy | other | none`), which session's decoy arrived (by decoy id, never its value), the number of
// Authorization headers, and whether an Idempotency-Key header arrived. Nothing logs a header value or a body.
// A request without the real decoy gets 401 on the GitHub hosts, as GitHub would.
//
// Run: server.mjs <config.json>
//   { "listen": {"host": "0.0.0.0", "port": 443}, "certFile", "keyFile", "repoRoot", "recordFile",
//     "decoys": [{"id": "sessA", "file": "/run/decoy-a"}, ...] }
import { spawn } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
import https from "node:https";
import { pathToFileURL } from "node:url";

const GITHUB_HOSTS = new Set(["github.com", "api.github.com", "uploads.github.com", "codeload.github.com"]);

/** Classify the Authorization header(s) a request carried, against the declared decoys. Exported for the suite. */
export function authClass(rawHeaders, decoys) {
  const values = [];
  for (let i = 0; i < rawHeaders.length; i += 2) if (rawHeaders[i].toLowerCase() === "authorization") values.push(rawHeaders[i + 1]);
  if (values.length === 0) return { cls: "none", count: 0, decoyId: null };
  if (values.length > 1) return { cls: "other", count: values.length, decoyId: null };
  const v = values[0];
  for (const d of decoys) {
    const basic = "Basic " + Buffer.from(`x-access-token:${d.value}`).toString("base64");
    if (v === basic || v === `token ${d.value}` || v === `Bearer ${d.value}`) return { cls: "real-decoy", count: 1, decoyId: d.id, scheme: v.split(" ")[0] };
  }
  return { cls: "other", count: 1, decoyId: null };
}

function hostOf(req) {
  const h = String(req.headers.host ?? req.socket.servername ?? "").toLowerCase();
  return h.replace(/:[0-9]+$/, "").replace(/\.$/, "");
}

function json(res, status, obj) {
  const b = Buffer.from(JSON.stringify(obj));
  res.writeHead(status, { "content-type": "application/json", "content-length": b.length });
  res.end(b);
}

function gitBackend(req, res, cfg, url) {
  const env = {
    PATH: process.env.PATH ?? "/usr/bin:/bin",
    GIT_PROJECT_ROOT: cfg.repoRoot,
    GIT_HTTP_EXPORT_ALL: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    REQUEST_METHOD: req.method,
    PATH_INFO: decodeURIComponent(url.pathname),
    QUERY_STRING: url.search.replace(/^\?/, ""),
    CONTENT_TYPE: req.headers["content-type"] ?? "",
    REMOTE_USER: "stub-user",
    REMOTE_ADDR: req.socket.remoteAddress ?? "",
    GIT_PROTOCOL: req.headers["git-protocol"] ?? "",
  };
  if (req.headers["content-encoding"]) env.HTTP_CONTENT_ENCODING = req.headers["content-encoding"];
  const child = spawn("git", ["http-backend"], { env, stdio: ["pipe", "pipe", "ignore"] });
  req.pipe(child.stdin);
  let head = Buffer.alloc(0);
  let headerDone = false;
  child.stdout.on("data", (chunk) => {
    if (headerDone) return void res.write(chunk);
    head = Buffer.concat([head, chunk]);
    const sep = head.indexOf("\r\n\r\n");
    if (sep === -1) return;
    headerDone = true;
    let status = 200;
    const headers = {};
    for (const line of head.subarray(0, sep).toString("latin1").split("\r\n")) {
      const i = line.indexOf(":");
      if (i === -1) continue;
      const k = line.slice(0, i).trim();
      const v = line.slice(i + 1).trim();
      if (k.toLowerCase() === "status") status = parseInt(v, 10) || 200;
      else headers[k] = v;
    }
    res.writeHead(status, headers);
    res.write(head.subarray(sep + 4));
  });
  child.on("close", () => res.end());
  child.on("error", () => {
    if (!res.headersSent) json(res, 500, { message: "http-backend failed" });
    else res.end();
  });
}

function restStub(req, res, url) {
  const p = url.pathname;
  const m = p.match(/^\/repos\/([^/]+)\/([^/]+)(\/.*)?$/);
  if (req.method === "POST" && p === "/graphql") return json(res, 200, { data: { stub: true } });
  if (m && req.method === "POST" && m[3] === "/pulls") return json(res, 201, { number: 1, stub: true });
  if (m && req.method === "POST" && m[3] === "/issues") return json(res, 201, { number: 2, stub: true });
  if (m && req.method === "POST" && /^\/issues\/[0-9]+\/comments$/.test(m[3] ?? "")) return json(res, 201, { id: 3, stub: true });
  if (m && (req.method === "GET" || req.method === "HEAD")) return json(res, 200, { full_name: `${m[1]}/${m[2]}`, private: true, stub: true });
  if (p === "/user" && req.method === "GET") return json(res, 200, { login: "stub-user" });
  return json(res, 404, { message: "Not Found" });
}

function sse(res) {
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
  let i = 0;
  const t = setInterval(() => {
    i += 1;
    res.write(`event: tick\ndata: {"n":${i}}\n\n`);
    if (i >= 50) {
      clearInterval(t);
      res.end("event: done\ndata: {}\n\n");
    }
  }, 20);
  res.on("close", () => clearInterval(t));
}

export function createStub(cfg) {
  const decoys = (cfg.decoys ?? []).map((d) => ({ id: d.id, value: d.value ?? readFileSync(d.file, "utf8").trim() }));
  let seq = 0;
  return https.createServer({ cert: readFileSync(cfg.certFile), key: readFileSync(cfg.keyFile) }, (req, res) => {
    const host = hostOf(req);
    const url = new URL(req.url ?? "/", `https://${host || "stub"}`);
    const a = authClass(req.rawHeaders, decoys);
    const rec = {
      seq: ++seq, ts: new Date().toISOString(), host, method: req.method, path: url.pathname,
      query_keys: [...url.searchParams.keys()], auth_class: a.cls, auth_count: a.count, decoy_id: a.decoyId, auth_scheme: a.scheme ?? null,
      idempotency_key: req.headers["idempotency-key"] !== undefined, sni: req.socket.servername ?? null,
    };
    appendFileSync(cfg.recordFile, JSON.stringify(rec) + "\n");
    if (host === "api.anthropic.com") {
      if (url.pathname === "/sse") return sse(res);
      return json(res, 404, { message: "Not Found" });
    }
    if (!GITHUB_HOSTS.has(host)) return json(res, 421, { message: "Misdirected Request" });
    if (a.cls !== "real-decoy") {
      res.writeHead(401, { "www-authenticate": 'Basic realm="GitHub"', "content-length": 0 });
      return void res.end();
    }
    if (host === "github.com") return gitBackend(req, res, cfg, url);
    if (host === "api.github.com") return restStub(req, res, url);
    return json(res, 200, { stub: true, host });
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv[2]) {
    console.error("usage: server.mjs <config.json>");
    process.exit(64);
  }
  const cfg = JSON.parse(readFileSync(process.argv[2], "utf8"));
  const server = createStub(cfg);
  server.listen(cfg.listen?.port ?? 443, cfg.listen?.host ?? "0.0.0.0", () => {
    console.log(`stub-github-listening ${server.address().port}`);
  });
  process.on("SIGTERM", () => process.exit(0));
}

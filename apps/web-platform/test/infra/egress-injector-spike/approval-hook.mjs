#!/usr/bin/env node
// Egress injector spike (#12517): the approval hook. Implements iron-proxy's transform.v1.TransformService.
//
// One process stands in for the dispatcher (CTO R9): it holds the service-role and HMAC keys, and each session
// reaches it through its own unix socket in a per-session directory the sandbox config masks. The channel is mutual
// TLS (R25): a call is accepted only when the injector's client certificate chains to the hook's client root and
// its CN equals the conversation bound to that socket. Before the service-role key is used, the hook refuses unless
// the Supabase URL host is a loopback literal and the URL and key match `supabase status` (R21).
//
// The decision logic is the exported pure-ish `createDecider(...).decide(request, session)`, tested hermetically in
// apps/web-platform/test/egress-injector-policy.test.ts over a fake RPC client. Decision order (plan, binding):
//   0. CONNECT: the router-only credential is required (407 without it); a CONNECT is not a vend (R26)
//   0b. any other request must arrive on a tunnel whose target is its own host on 443 (R28), over TLS whose SNI is
//       that host (R37), with a body under the iron-proxy cap (R40); else guard-refused
//   1. flag input off: REJECT every vend, reads included, no row (CTO R2)
//   2. unparseable / unclassifiable / unlisted write: REJECT not-allowlisted, no row
//   3. allowlisted read or push advertisement: CONTINUE
//   4. read outside the allowlist: REJECT not-allowlisted, no row
//   5. listed write: create_approval_request, then consume_approval when approved and live (service.ts's order)
//
// Nothing here logs a body, a header value or a token. Markers carry ids, classes and a 12-hex hash prefix only.
import { randomUUID, timingSafeEqual } from "node:crypto";
import { chmodSync, lstatSync, readFileSync, unlinkSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import * as policyLib from "./policy.mjs";

/** The one spike tool name (CTO D4): a credential vend must not look like a server-run tool in the audit record. */
export const SPIKE_TOOL_NAME = "egress_injector_spike__credential_vend";
const DEFAULT_DEADLINE_MS = 5000;
/**
 * iron-proxy's `proxy.max_request_body_bytes` (iron-proxy.config.tmpl.yaml). Above it iron-proxy CUTS the body with no
 * error and forwards the cut copy (internal/transform/body.go, v0.56.0), so a body of this size or more is refused:
 * the hook cannot tell a whole body at the cap from a cut one (CTO R40). It stays below grpc-js's 4 MiB default receive
 * limit for the body itself.
 */
export const BODY_CAP_BYTES = 3 * 1024 * 1024;
// The gRPC message also carries the headers (Go allows up to about 1 MiB), so a body just under the cap plus large
// headers can exceed the 4 MiB receive limit; the call then errors and iron-proxy fails the request closed (502).
const REASONS = new Set([
  "flag-off", "not-allowlisted", "pending", "rejected", "expired", "cap", "retry", "closed",
  "consume-failed", "rpc-error", "guard-refused", "hook-timeout", "no-hook-decision",
]);

// ---------------------------------------------------------------------------------------------------------------
// Markers
// ---------------------------------------------------------------------------------------------------------------

const MARKER_NAME_RE = /^SOLEUR_EGRESS_[A-Z_]+$/;

/** One log line. Values are restricted to a safe alphabet so no field can forge a second marker or carry a header. */
export function formatMarker(name, fields) {
  if (!MARKER_NAME_RE.test(name)) throw new Error(`formatMarker: bad marker name ${name}`);
  const parts = [name];
  for (const [k, v] of Object.entries(fields ?? {})) {
    if (v === undefined || v === null || v === "") continue;
    parts.push(`${k}=${String(v).replace(/[^A-Za-z0-9._:/@-]/g, "_").slice(0, 200)}`);
  }
  return parts.join(" ");
}

// ---------------------------------------------------------------------------------------------------------------
// Supabase target guard (R21)
// ---------------------------------------------------------------------------------------------------------------

function isLoopbackLiteral(hostname) {
  if (/^127(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}$/.test(hostname)) return true;
  return hostname === "[::1]" || hostname === "::1";
}

function sameSecret(a, b) {
  const x = Buffer.from(String(a ?? ""), "utf8");
  const y = Buffer.from(String(b ?? ""), "utf8");
  return x.length > 0 && x.length === y.length && timingSafeEqual(x, y);
}

/** status = the parsed `supabase status -o env` output (API_URL, SERVICE_ROLE_KEY). */
export function checkSupabaseTarget({ url, key, status }) {
  let u;
  try {
    u = new URL(url);
  } catch {
    return { ok: false, reason: "bad-url" };
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return { ok: false, reason: "bad-scheme" };
  if (!isLoopbackLiteral(u.hostname)) return { ok: false, reason: "not-loopback-literal" };
  const strip = (s) => String(s ?? "").replace(/\/+$/, "");
  if (!status?.API_URL || strip(status.API_URL) !== strip(u.href)) return { ok: false, reason: "url-differs-from-supabase-status" };
  if (!sameSecret(key, status.SERVICE_ROLE_KEY)) return { ok: false, reason: "key-differs-from-supabase-status" };
  return { ok: true };
}

/** Parse `supabase status -o env` (KEY="value" lines). */
export function parseStatusEnv(text) {
  const out = {};
  for (const line of String(text).split("\n")) {
    const m = line.match(/^([A-Z_][A-Z0-9_]*)=(?:"([^"]*)"|(\S*))\s*$/);
    if (m) out[m[1]] = m[2] ?? m[3];
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Decider
// ---------------------------------------------------------------------------------------------------------------

function proxyAuthPassword(headerValues) {
  if (!headerValues || headerValues.length !== 1) return null;
  const m = String(headerValues[0]).match(/^basic[ \t]+([A-Za-z0-9+/=]+)$/i);
  if (!m) return null;
  const decoded = Buffer.from(m[1], "base64").toString("utf8");
  const colon = decoded.indexOf(":");
  return colon === -1 ? null : decoded.slice(colon + 1);
}

/** A session may shorten its rows' TTL (criterion 3's expiry arm); only an integer in the RPC's own range counts. */
function sessionTtl(v) {
  return Number.isInteger(v) && v >= 60 && v <= 172800 ? v : undefined; // create_approval_request accepts 60..172800
}

function rpcFailureReason(err) {
  const code = String(err?.code ?? "");
  if (code === "AP429" || code === "AP430") return "cap";
  if (code === "40001") return "retry";
  if (code === "P0001" && /conversation closed/.test(String(err?.message ?? ""))) return "closed";
  return "rpc-error";
}

function body(reason, extra = {}) {
  const message = {
    pending: "This request needs approval in Soleur before the credential is attached.",
    rejected: "The previous approval for this request was declined; a new approval request was created.",
    expired: "The approval for this request expired; a new approval request was created.",
    "flag-off": "Credential injection is turned off for this workspace.",
    "not-allowlisted": "This request is not on the egress credential allowlist.",
  }[reason] ?? "The egress credential hook refused this request.";
  return JSON.stringify({ error: "egress_vend_refused", reason, message, ...extra });
}

/**
 * deps: { policy (compiled), hmacKey, rpc: {create, consume, status}, toolName, ttlSeconds, deadlineMs, now }.
 * session: { sessionId, conversationId, workspaceId, requesterId, repositories, flagOn, routerCredential, ttlSeconds? }.
 * request: { method, host, path, query, headers, body, tunnelTarget, sni, requestId? } (headers: name -> string | string[];
 *   tunnelTarget: the CONNECT target of the tunnel the request arrived on, or null (CTO R28); sni: the TLS server name
 *   iron-proxy terminated, or null for plain HTTP (CTO R36, R37)).
 * deps.bodyCapBytes: defaults to BODY_CAP_BYTES (CTO R40).
 */
export function createDecider(deps) {
  const { policy, hmacKey, rpc } = deps;
  if (!policy || !rpc) throw new Error("createDecider: policy and rpc are required");
  // Fail at construction, not on the first write, if the key is unusable.
  policyLib.actionHash({ probe: true }, hmacKey);
  const toolName = deps.toolName ?? SPIKE_TOOL_NAME;
  const ttlSeconds = deps.ttlSeconds ?? 600;
  const deadlineMs = deps.deadlineMs ?? DEFAULT_DEADLINE_MS;
  const bodyCap = deps.bodyCapBytes ?? BODY_CAP_BYTES;
  const now = deps.now ?? (() => Date.now());
  const lastId = new Map(); // `${conversation}:${hash}` -> last approval id seen

  async function decideInner(request, session, ctl) {
    const n = policyLib.normalizeRequest(request);
    // client_auth: how many Authorization headers reached the hook (a count, never a value). The hook runs before
    // the secrets transform, so a client that sent none shows 0; a reordered pipeline would show the injected one
    // (Guard 2 row 8, run 42820864911).
    let clientAuth = 0;
    for (const [k, v] of Object.entries(request?.headers ?? {})) if (k.toLowerCase() === "authorization") clientAuth += Array.isArray(v) ? v.length : 1;
    const base = { session: session.sessionId, request_id: ctl.requestId, source: "hook", host: n.ok ? n.host : "invalid", method: n.ok ? n.method : "invalid", client_auth: clientAuth };
    const refuse = (reason, extra = {}) => {
      if (!REASONS.has(reason)) throw new Error(`decide: unknown reason ${reason}`);
      const fields = { ...base, class: extra.class ?? "unknown", rule: extra.rule, reason, subreason: extra.subreason, approval_id: extra.approvalId, action_sha256: extra.hash?.slice(0, 12) };
      return {
        action: "REJECT", status: extra.status ?? 403, reason, subreason: extra.subreason, class: fields.class, rule: extra.rule,
        approvalId: extra.approvalId, hashPrefix: fields.action_sha256, requestId: ctl.requestId,
        body: body(reason, extra.approvalId ? { approval_id: extra.approvalId } : {}),
        marker: { name: "SOLEUR_EGRESS_VEND_REFUSED", fields },
      };
    };
    const vend = (cls, rule, approvalId) => ({
      action: "CONTINUE", class: cls, rule, approvalId, requestId: ctl.requestId,
      marker: { name: "SOLEUR_EGRESS_VEND", fields: { ...base, class: cls, rule, approval_id: approvalId ?? "read-allowlist" } },
    });

    // 0. CONNECT through iron-proxy's transform pipeline (R26): the router-only credential, never a vend. The hook
    // refuses a CONNECT with no SNI (one sent to http_listen) or with tunnel context (one sent inside a tunnel). It
    // cannot tell tunnel_listen's synthetic CONNECT (SNI = host, no tunnel; tunnel.go tunnelTransformCheck) from a
    // CONNECT sent over TLS to https_listen with SNI = host, which it therefore passes: for that one the secrets
    // rules' method list is the only control, and it keeps the credential off every CONNECT (CTO R36).
    if (n.ok && n.method === "CONNECT") {
      const pw = proxyAuthPassword(n.headers["proxy-authorization"]);
      const sni = request?.sni ? policyLib.normalizeHost(String(request.sni)) : null;
      let sub = null;
      if (!(pw !== null && sameSecret(pw, session.routerCredential))) sub = "credential";
      else if (request?.tunnelTarget) sub = "in-tunnel";
      else if (sni === null) sub = "no-sni";
      else if (sni !== n.host) sub = "sni-mismatch";
      const ok = sub === null;
      return {
        action: ok ? "CONTINUE" : "REJECT", status: ok ? undefined : 407, class: "connect", requestId: ctl.requestId,
        body: ok ? undefined : "", subreason: sub ?? undefined,
        headers: ok ? undefined : { "proxy-authenticate": ['Basic realm="soleur-injector"'] },
        marker: { name: "SOLEUR_EGRESS_CONNECT", fields: { ...base, outcome: ok ? "continue" : "refused-407", subreason: sub ?? undefined } },
      };
    }

    // 0b. Tunnel guard (CTO R28): every non-CONNECT request must come from a tunnel whose CONNECT target is this
    // request's host on 443. iron-proxy fills TransformContext.tunnel for requests on tunnel_listen (measured
    // 2026-11-10) and leaves it empty for http_listen and https_listen, which share the app container's loopback;
    // without this check a request sent straight to http_listen was vended.
    if (n.ok) {
      const t = String(request?.tunnelTarget ?? "");
      const tunnelHost = /:443$/.test(t) ? policyLib.normalizeHost(t) : null; // one host normalizer (review)
      if (tunnelHost !== n.host) return refuse("guard-refused", { subreason: "no-tunnel" });
      // iron-proxy sets SNI only on a TLS-terminated request and itself refuses SNI != Host, so an empty SNI means
      // plain HTTP inside the tunnel: the credential would cross the forwarder in cleartext (CTO R37).
      const sni = request?.sni ? policyLib.normalizeHost(String(request.sni)) : null;
      if (sni !== n.host) return refuse("guard-refused", { subreason: "no-tls" });
      if (n.body.length >= bodyCap) return refuse("guard-refused", { subreason: "body-over-cap" }); // CTO R40
    }

    // 1. Flag input off: every vend refused, reads included.
    if (session.flagOn !== true) return refuse("flag-off");

    // 2-4. Classify.
    const c = policyLib.classify(n, policy, { repositories: session.repositories });
    if (c.verdict === "refused") return refuse("not-allowlisted", { class: "refused", rule: c.rule, subreason: c.subreason });
    if (c.verdict === "read" || c.verdict === "push-advert") return vend(c.verdict, c.rule);
    if (c.verdict !== "write") return refuse("not-allowlisted", { subreason: "unparseable" });

    // 5. Listed write.
    const hash = policyLib.actionHash(c.canonical, hmacKey);
    const w = { class: "write", rule: c.rule, hash };
    let res;
    try {
      res = await rpc.create({
        workspaceId: session.workspaceId, conversationId: session.conversationId, requesterId: session.requesterId,
        toolName, hash, canonical: c.canonical, ttlSeconds: sessionTtl(session.ttlSeconds) ?? ttlSeconds,
      });
    } catch (err) {
      return refuse(rpcFailureReason(err), w);
    }
    const row = res?.approval;
    if (!row?.id) return refuse("rpc-error", w);
    const key = `${session.conversationId}:${hash}`;
    const prev = lastId.get(key);
    lastId.set(key, row.id);
    if (res.created === true && prev && prev !== row.id) {
      let st = null;
      try {
        st = await rpc.status(prev);
      } catch {
        st = null;
      }
      if (st?.status === "rejected" || st?.status === "expired") return refuse(st.status, { ...w, approvalId: row.id });
    }
    if (row.status === "approved") {
      if (!(Date.parse(row.expires_at) > now())) return refuse("expired", { ...w, approvalId: row.id });
      // Once consume starts, the deadline no longer races it (decide() below): a consume that commits must be followed
      // by the vend it paid for, never by a hook-timeout refusal (review 2026-11-10, four seats reproduced the race).
      // The RPC's own timeout still bounds it; an abort after the server committed is the residual ADR-311 Decision 5
      // records: `consumed` means the approval was spent, not that the write was delivered.
      if (ctl.timedOut) return refuse("hook-timeout", { ...w, approvalId: row.id });
      ctl.consuming = true;
      let cr;
      try {
        cr = await rpc.consume({ id: row.id, hash, conversationId: session.conversationId });
      } catch (err) {
        return refuse(rpcFailureReason(err), { ...w, approvalId: row.id });
      }
      if (cr?.consumed === true) return vend("write", c.rule, row.id);
      if (cr?.reason === "expired") return refuse("expired", { ...w, approvalId: row.id });
      return refuse("consume-failed", { ...w, approvalId: row.id, subreason: String(cr?.reason ?? "unknown") });
    }
    return refuse("pending", { ...w, approvalId: row.id });
  }

  async function decide(request, session) {
    const requestId = /^[A-Za-z0-9._:-]{1,80}$/.test(String(request?.requestId ?? "")) ? request.requestId : randomUUID();
    const ctl = { requestId, timedOut: false, consuming: false };
    let timer;
    const timeout = new Promise((resolve) => {
      timer = setTimeout(() => {
        ctl.timedOut = true;
        if (ctl.consuming) return; // the in-flight consume decides; see step 5
        resolve({
          action: "REJECT", status: 403, reason: "hook-timeout", class: "unknown", requestId, body: body("hook-timeout"),
          marker: { name: "SOLEUR_EGRESS_VEND_REFUSED", fields: { session: session?.sessionId, request_id: requestId, source: "hook", reason: "hook-timeout" } },
        });
      }, deadlineMs);
    });
    try {
      return await Promise.race([decideInner(request, session ?? {}, ctl), timeout]);
    } catch {
      return {
        action: "REJECT", status: 403, reason: "rpc-error", class: "unknown", requestId, body: body("rpc-error"),
        marker: { name: "SOLEUR_EGRESS_VEND_REFUSED", fields: { session: session?.sessionId, request_id: requestId, source: "hook", reason: "rpc-error" } },
      };
    } finally {
      clearTimeout(timer);
    }
  }

  return { decide };
}

// ---------------------------------------------------------------------------------------------------------------
// Supabase RPC adapter (service role; PostgREST /rest/v1/rpc)
// ---------------------------------------------------------------------------------------------------------------

export function supabaseRpc({ url, key, fetchImpl = fetch, timeoutMs = DEFAULT_DEADLINE_MS }) {
  const call = async (fn, args) => {
    const res = await fetchImpl(`${url.replace(/\/+$/, "")}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = null;
    }
    if (!res.ok) throw Object.assign(new Error(String(json?.message ?? `rpc ${fn} http ${res.status}`)), { code: json?.code });
    return json;
  };
  return {
    create: (a) => call("create_approval_request", {
      p_workspace_id: a.workspaceId, p_conversation_id: a.conversationId, p_requested_by: a.requesterId,
      p_tool_name: a.toolName, p_action_sha256: a.hash, p_canonical_action: a.canonical, p_ttl_seconds: a.ttlSeconds,
    }),
    consume: (a) => call("consume_approval", { p_id: a.id, p_hash: a.hash, p_conversation: a.conversationId }),
    status: (id) => call("get_approval_status", { p_id: id }),
  };
}

// ---------------------------------------------------------------------------------------------------------------
// gRPC server (only when run as a program)
// ---------------------------------------------------------------------------------------------------------------

/**
 * iron-proxy's HttpRequest -> the decider's request struct. iron-proxy v0.56.0 sends `url` as Go's req.URL.String(),
 * in origin form (`/path?query`, measured 2026-11-10) with the authority in `host`; an absolute `https://` url is
 * accepted only when its authority names the same host, otherwise the path is left empty so normalization refuses it
 * (Guard 2 row 14). The target is split by hand, never by a URL parser: WHATWG URL resolves `..` and `%2e%2e`, turns
 * `\` into `/` and reads `//x` as an authority, so canonicalSegments would see a cleaned path while the raw target
 * goes upstream (review 2026-11-10, security P1). A `#` is refused: it has no meaning in a request target.
 */
export function fromTransformRequest(httpReq, context) {
  let path = "";
  let query = "";
  const host = String(httpReq.host ?? "");
  let raw = String(httpReq.url ?? "");
  const abs = raw.match(/^https:\/\/([^/?#]*)(.*)$/i);
  if (abs) {
    const authority = policyLib.normalizeHost(abs[1]);
    raw = authority !== null && authority === policyLib.normalizeHost(host) ? abs[2] : "";
  } else if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(raw)) {
    raw = "";
  }
  if (raw.startsWith("/") && !raw.includes("#")) {
    const q = raw.indexOf("?");
    path = q === -1 ? raw : raw.slice(0, q);
    query = q === -1 ? "" : raw.slice(q + 1);
  }
  const headers = {};
  for (const [k, v] of Object.entries(httpReq.headers ?? {})) headers[k] = v?.values ?? [];
  const tunnelTarget = context?.tunnel?.target ? String(context.tunnel.target) : null;
  const sni = context?.sni ? String(context.sni) : null; // iron-proxy sets it only on TLS-terminated requests
  return { method: httpReq.method, host: httpReq.host, path, query, headers, body: Buffer.from(httpReq.body ?? []), tunnelTarget, sni };
}

/** Headers the hook removes on every request it lets through (criterion 2: a retried POST cannot reuse one approval). */
export const STRIPPED_HEADERS = Object.freeze(["idempotency-key"]);

/**
 * iron-proxy's HttpRequest with every STRIPPED_HEADERS name (any case) removed, or null when none was present (the
 * hook then returns no modified_request). The hook runs before the secrets transform, so this never handles a token.
 */
export function withoutStrippedHeaders(httpReq) {
  const headers = httpReq?.headers ?? {};
  const keep = {};
  let removed = false;
  for (const [k, v] of Object.entries(headers)) {
    if (STRIPPED_HEADERS.includes(k.toLowerCase())) removed = true;
    else keep[k] = v;
  }
  return removed ? { ...httpReq, headers: keep } : null;
}

function toHeaderMap(h) {
  const out = {};
  for (const [k, v] of Object.entries(h ?? {})) out[k] = { values: v };
  return out;
}

async function main(configPath) {
  const grpc = await import("@grpc/grpc-js");
  const protoLoader = await import("@grpc/proto-loader");
  const { parse: parseYaml } = await import("yaml");
  const here = dirname(fileURLToPath(import.meta.url));
  const cfg = JSON.parse(readFileSync(configPath, "utf8"));
  const read = (p) => readFileSync(p, "utf8").trim();
  const print = (name, fields) => console.log(formatMarker(name, fields));

  const serviceKey = read(cfg.serviceRoleKeyFile);
  const guard = checkSupabaseTarget({ url: cfg.supabaseUrl, key: serviceKey, status: parseStatusEnv(readFileSync(cfg.supabaseStatusFile, "utf8")) });
  if (!guard.ok) {
    print("SOLEUR_EGRESS_VEND_REFUSED", { source: "hook", reason: "guard-refused", subreason: guard.reason });
    process.exit(2);
  }

  let policyObj = parseYaml(readFileSync(cfg.policyFiles[0], "utf8"));
  for (const extra of cfg.policyFiles.slice(1)) policyObj = policyLib.mergePolicy(policyObj, parseYaml(readFileSync(extra, "utf8")));
  const decider = createDecider({
    policy: policyLib.compilePolicy(policyObj),
    hmacKey: Buffer.from(read(cfg.hmacKeyFile), "hex"),
    rpc: supabaseRpc({ url: cfg.supabaseUrl, key: serviceKey, timeoutMs: cfg.deadlineMs ?? DEFAULT_DEADLINE_MS }),
    toolName: cfg.toolName ?? SPIKE_TOOL_NAME,
    ttlSeconds: cfg.ttlSeconds ?? 600,
    deadlineMs: cfg.deadlineMs ?? DEFAULT_DEADLINE_MS,
  });

  const def = protoLoader.loadSync(join(here, "transform.proto"), { keepCase: true, longs: String, enums: Number, defaults: true, oneofs: true });
  const svc = grpc.loadPackageDefinition(def).transform.v1.TransformService.service;
  const clientRoot = readFileSync(cfg.clientRootCertFile);
  const CONTINUE = 1;
  const REJECT = 2;

  const servers = [];
  for (const s of cfg.sessions) {
    const session = {
      sessionId: s.sessionId, conversationId: s.conversationId, workspaceId: s.workspaceId, requesterId: s.requesterId,
      repositories: s.repositories, flagOn: s.flagOn === true, routerCredential: read(s.routerCredentialFile),
      ttlSeconds: s.ttlSeconds,
    };
    const server = new grpc.Server();
    server.addService(svc, {
      TransformRequest(call, cb) {
        const peer = call.getAuthContext?.()?.sslPeerCertificate;
        if (!peer || peer.subject?.CN !== session.conversationId) {
          print("SOLEUR_EGRESS_VEND_REFUSED", { session: session.sessionId, source: "hook", reason: "guard-refused", subreason: "client-identity" });
          cb(null, { action: REJECT, response: { status_code: 403, headers: {}, body: Buffer.from(body("guard-refused")) } });
          return;
        }
        const req = fromTransformRequest(call.request.request ?? {}, call.request.context);
        decider.decide(req, session).then((d) => {
          if (d.marker) print(d.marker.name, d.marker.fields);
          if (d.action === "CONTINUE") {
            const modified = d.class === "connect" ? null : withoutStrippedHeaders(call.request.request);
            cb(null, {
              action: CONTINUE,
              ...(modified ? { modified_request: modified } : {}),
              annotations: { soleur_request_id: d.requestId, soleur_class: d.class ?? "" },
            });
          } else {
            cb(null, {
              action: REJECT,
              response: { status_code: d.status ?? 403, headers: toHeaderMap({ "content-type": ["application/json"], ...(d.headers ?? {}) }), body: Buffer.from(d.body ?? "") },
              annotations: { soleur_request_id: d.requestId, soleur_reason: d.reason ?? "" },
            });
          }
        }).catch(() => {
          // A throw while building the reply must still answer, closed, with a marker (review 2026-11-10).
          print("SOLEUR_EGRESS_VEND_REFUSED", { session: session.sessionId, source: "hook", reason: "rpc-error", subreason: "reply" });
          cb(null, { action: REJECT, response: { status_code: 403, headers: {}, body: Buffer.from(body("rpc-error")) } });
        });
      },
      TransformResponse(_call, cb) {
        cb(null, { action: CONTINUE });
      },
    });
    const creds = grpc.ServerCredentials.createSsl(clientRoot, [{ private_key: readFileSync(s.serverKeyFile), cert_chain: readFileSync(s.serverCertFile) }], true);
    // A restarted hook (criterion 7's overlay pass, criterion 8) finds its previous socket file still present; remove
    // it only when it IS a socket, so a misconfigured path can never delete a regular file.
    try {
      if (lstatSync(s.socketPath).isSocket()) unlinkSync(s.socketPath);
    } catch (err) {
      if (err?.code !== "ENOENT") throw err;
    }
    await new Promise((resolve, reject) => server.bindAsync(`unix://${s.socketPath}`, creds, (err) => (err ? reject(err) : resolve())));
    chmodSync(s.socketPath, 0o600);
    servers.push(server);
  }
  console.log(`approval-hook-listening ${servers.length}`);
  const stop = () => {
    for (const sv of servers) sv.forceShutdown();
    process.exit(0);
  };
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv[2]) {
    console.error("usage: approval-hook.mjs <config.json>");
    process.exit(64);
  }
  main(process.argv[2]).catch((err) => {
    console.error(`approval-hook: ${err?.message ?? err}`);
    process.exit(1);
  });
}

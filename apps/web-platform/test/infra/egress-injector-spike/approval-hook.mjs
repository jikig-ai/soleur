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
//   1. flag input off: REJECT every vend, reads included, no row (CTO R2)
//   2. unparseable / unclassifiable / unlisted write: REJECT not-allowlisted, no row
//   3. allowlisted read or push advertisement: CONTINUE
//   4. read outside the allowlist: REJECT not-allowlisted, no row
//   5. listed write: create_approval_request, then consume_approval when approved and live (service.ts's order)
//
// Nothing here logs a body, a header value or a token. Markers carry ids, classes and a 12-hex hash prefix only.
import { randomUUID, timingSafeEqual } from "node:crypto";
import { chmodSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import * as policyLib from "./policy.mjs";

/** The one spike tool name (CTO D4): a credential vend must not look like a server-run tool in the audit record. */
export const SPIKE_TOOL_NAME = "egress_injector_spike__credential_vend";
const DEFAULT_DEADLINE_MS = 5000;
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
 * session: { sessionId, conversationId, workspaceId, requesterId, repositories, flagOn, routerCredential }.
 * request: { method, host, path, query, headers, body, requestId? } (headers: name -> string | string[]).
 */
export function createDecider(deps) {
  const { policy, hmacKey, rpc } = deps;
  if (!policy || !rpc) throw new Error("createDecider: policy and rpc are required");
  // Fail at construction, not on the first write, if the key is unusable.
  policyLib.actionHash({ probe: true }, hmacKey);
  const toolName = deps.toolName ?? SPIKE_TOOL_NAME;
  const ttlSeconds = deps.ttlSeconds ?? 600;
  const deadlineMs = deps.deadlineMs ?? DEFAULT_DEADLINE_MS;
  const now = deps.now ?? (() => Date.now());
  const lastId = new Map(); // `${conversation}:${hash}` -> last approval id seen

  async function decideInner(request, session, ctl) {
    const n = policyLib.normalizeRequest(request);
    const base = { session: session.sessionId, request_id: ctl.requestId, source: "hook", host: n.ok ? n.host : "invalid", method: n.ok ? n.method : "invalid" };
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

    // 0. CONNECT through iron-proxy's transform pipeline (R26): the router-only credential, never a vend.
    if (n.ok && n.method === "CONNECT") {
      const pw = proxyAuthPassword(n.headers["proxy-authorization"]);
      const ok = pw !== null && sameSecret(pw, session.routerCredential);
      return {
        action: ok ? "CONTINUE" : "REJECT", status: ok ? undefined : 407, class: "connect", requestId: ctl.requestId,
        body: ok ? undefined : "",
        headers: ok ? undefined : { "proxy-authenticate": ['Basic realm="soleur-injector"'] },
        marker: { name: "SOLEUR_EGRESS_CONNECT", fields: { ...base, outcome: ok ? "continue" : "refused-407" } },
      };
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
        toolName, hash, canonical: c.canonical, ttlSeconds,
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
      if (ctl.timedOut) return refuse("hook-timeout", { ...w, approvalId: row.id }); // never spend an approval late
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
    const ctl = { requestId, timedOut: false };
    let timer;
    const timeout = new Promise((resolve) => {
      timer = setTimeout(() => {
        ctl.timedOut = true;
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

export function supabaseRpc({ url, key, fetchImpl = fetch }) {
  const call = async (fn, args) => {
    const res = await fetchImpl(`${url.replace(/\/+$/, "")}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(DEFAULT_DEADLINE_MS),
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

/** iron-proxy's HttpRequest -> the decider's request struct. */
export function fromTransformRequest(httpReq) {
  let path = "/";
  let query = "";
  try {
    const u = new URL(httpReq.url);
    path = u.pathname;
    query = u.search.replace(/^\?/, "");
  } catch {
    path = "";
  }
  const headers = {};
  for (const [k, v] of Object.entries(httpReq.headers ?? {})) headers[k] = v?.values ?? [];
  return { method: httpReq.method, host: httpReq.host, path, query, headers, body: Buffer.from(httpReq.body ?? []) };
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
    rpc: supabaseRpc({ url: cfg.supabaseUrl, key: serviceKey }),
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
        const req = fromTransformRequest(call.request.request ?? {});
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
        });
      },
      TransformResponse(_call, cb) {
        cb(null, { action: CONTINUE });
      },
    });
    const creds = grpc.ServerCredentials.createSsl(clientRoot, [{ private_key: readFileSync(s.serverKeyFile), cert_chain: readFileSync(s.serverCertFile) }], true);
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

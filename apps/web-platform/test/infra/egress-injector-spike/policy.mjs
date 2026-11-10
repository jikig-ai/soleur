// Egress injector spike (#12517): the per-host classifier and the action-hash recipe.
//
// Pure functions over a normalized request struct `{method, host, path, query, headers, body}`. No server import, no
// network, no file read (the caller parses policy.yaml and passes the object in), and the HMAC key is a required
// parameter with no default, so #11637 can port this file into server/ unchanged. Guard 2's classifier chokepoint.
//
// Decision vocabulary (the hook maps it to reason codes):
//   read          allowlisted read; vends without a row
//   push-advert   the receive-pack ref advertisement GET; vends without a row (CTO R1)
//   write         a listed write; `canonical` is the action the approval row binds to
//   refused       never vended; `subreason` in unparseable | batched | unlisted-write | read-outside-allowlist |
//                 write-outside-allowlist
import { createHash, createHmac } from "node:crypto";
import { gunzipSync } from "node:zlib";
import { Kind, parse as parseGraphql, print as printGraphql } from "graphql";

const MAX_DECODED_BODY = 16 * 1024 * 1024;
const READ_METHODS = new Set(["GET", "HEAD"]);
const OWNER_RE = /^[a-z0-9](?:[a-z0-9-]{0,38})$/;
const REPO_RE = /^[a-z0-9._-]{1,100}$/;
const NUMBER_RE = /^[1-9][0-9]{0,9}$/;
const HOST_RE = /^[a-z0-9](?:[a-z0-9-]{0,62})(?:\.[a-z0-9](?:[a-z0-9-]{0,62}))*$/;
const OID_RE = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
const RECIPES = new Set(["git-push", "rest", "graphql"]);

const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");

/** JSON with object keys sorted at every depth, so equal values serialize equally. */
export function stableJson(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value ?? null);
  if (Array.isArray(value)) return "[" + value.map(stableJson).join(",") + "]";
  return "{" + Object.keys(value).sort().map((k) => JSON.stringify(k) + ":" + stableJson(value[k])).join(",") + "}";
}

/** Lowercase, drop one trailing dot, strip `:443`. Returns null for anything that is not a plain DNS name on 443. */
export function normalizeHost(raw) {
  if (typeof raw !== "string") return null;
  let h = raw.trim().toLowerCase();
  const colon = h.lastIndexOf(":");
  if (colon !== -1) {
    if (h.slice(colon + 1) !== "443") return null;
    h = h.slice(0, colon);
  }
  if (h.endsWith(".")) h = h.slice(0, -1);
  return HOST_RE.test(h) ? h : null;
}

/**
 * Split a request path into decoded segments, refusing every spelling that could make the allowlist match and the
 * destination disagree: traversal, encoded slashes, backslashes, encoded dots, double slashes, control bytes.
 */
export function canonicalSegments(rawPath) {
  if (typeof rawPath !== "string" || !rawPath.startsWith("/")) return null;
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x20\x7f\\]/.test(rawPath)) return null;
  if (rawPath.includes("//")) return null;
  if (/%(2f|5c|2e|00)/i.test(rawPath)) return null;
  const parts = rawPath.slice(1).split("/");
  if (parts.length > 1 && parts[parts.length - 1] === "") parts.pop(); // one trailing slash
  const out = [];
  for (const p of parts) {
    let d;
    try {
      d = decodeURIComponent(p);
    } catch {
      return null;
    }
    // eslint-disable-next-line no-control-regex
    if (d === "" || d === "." || d === ".." || /[/\\\x00-\x1f\x7f]/.test(d)) return null;
    out.push(d);
  }
  return out;
}

function lowerHeaders(headers) {
  const out = {};
  for (const [k, v] of Object.entries(headers ?? {})) {
    const key = k.toLowerCase();
    const val = Array.isArray(v) ? v.map(String) : [String(v)];
    out[key] = out[key] ? out[key].concat(val) : val;
  }
  return out;
}

/** Normalize a request into the struct classify() reads. Never throws. */
export function normalizeRequest(input) {
  const method = String(input?.method ?? "").toUpperCase();
  const host = normalizeHost(input?.host);
  if (!/^[A-Z]{3,10}$/.test(method) || host === null) return { ok: false, detail: "bad-method-or-host" };
  const headers = lowerHeaders(input.headers);
  if (headers.host) {
    if (headers.host.length !== 1 || normalizeHost(headers.host[0]) !== host) return { ok: false, detail: "host-header-mismatch" };
  }
  if (method === "CONNECT") return { ok: true, method, host, segments: [], query: "", headers, body: Buffer.alloc(0) };
  const segments = canonicalSegments(input.path);
  if (segments === null) return { ok: false, detail: "bad-path" };
  const body = Buffer.isBuffer(input.body) ? input.body : Buffer.from(input.body ?? "");
  return { ok: true, method, host, segments, query: String(input.query ?? "").replace(/^\?/, ""), headers, body };
}

function decodedBody(n) {
  const enc = (n.headers["content-encoding"] ?? []).join(",").trim().toLowerCase();
  if (enc === "" || enc === "identity") return n.body;
  if (enc === "gzip" || enc === "x-gzip") {
    try {
      return gunzipSync(n.body, { maxOutputLength: MAX_DECODED_BODY });
    } catch {
      return null;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------
// Policy compilation
// ---------------------------------------------------------------------------------------------------------------

function compilePattern(pattern) {
  if (typeof pattern !== "string" || !pattern.startsWith("/")) throw new Error(`policy: bad path pattern ${pattern}`);
  const toks = pattern.slice(1).split("/");
  toks.forEach((t, i) => {
    if (t === "**" && i !== toks.length - 1) throw new Error(`policy: ** must be last in ${pattern}`);
    if (t.startsWith("{") && !["{owner}", "{repo}", "{number}"].includes(t)) throw new Error(`policy: unknown placeholder ${t}`);
  });
  return toks;
}

function compileRule(rule, kind) {
  if (!rule || typeof rule.id !== "string" || !rule.id) throw new Error(`policy: ${kind} rule without id`);
  const methods = (rule.methods ?? []).map((m) => String(m).toUpperCase());
  if (methods.length === 0) throw new Error(`policy: rule ${rule.id} has no methods`);
  const out = {
    id: rule.id,
    host: normalizeHost(rule.host),
    methods: new Set(methods),
    pattern: compilePattern(rule.path),
    query: rule.query ?? null,
    graphql: rule.graphql ?? null,
    recipe: rule.recipe ?? null,
    mutationFields: new Set(rule.mutation_fields ?? []),
  };
  if (!out.host) throw new Error(`policy: rule ${rule.id} has a bad host`);
  if (kind === "writes" && !RECIPES.has(out.recipe)) throw new Error(`policy: rule ${rule.id} has an unknown recipe`);
  if (kind !== "writes" && out.recipe) throw new Error(`policy: read rule ${rule.id} names a recipe`);
  if (out.graphql !== null && out.graphql !== "query") throw new Error(`policy: rule ${rule.id} graphql must be "query"`);
  return out;
}

export function compilePolicy(obj) {
  if (!obj || obj.version !== 1) throw new Error("policy: version 1 required");
  const injectHosts = new Set((obj.inject_hosts ?? []).map(normalizeHost));
  if (injectHosts.size === 0 || injectHosts.has(null)) throw new Error("policy: inject_hosts must be DNS names");
  const ids = new Set();
  const compiled = {};
  for (const kind of ["reads", "push_advertisement", "writes"]) {
    compiled[kind] = (obj[kind] ?? []).map((r) => {
      const c = compileRule(r, kind);
      if (ids.has(c.id)) throw new Error(`policy: duplicate rule id ${c.id}`);
      if (!injectHosts.has(c.host)) throw new Error(`policy: rule ${c.id} names a host outside inject_hosts`);
      ids.add(c.id);
      return c;
    });
  }
  return Object.freeze({ injectHosts, reads: compiled.reads, pushAdvert: compiled.push_advertisement, writes: compiled.writes });
}

/** Overlay rules are appended; an overlay can never widen the inject-host set. */
export function mergePolicy(base, overlay) {
  if (overlay?.inject_hosts !== undefined) throw new Error("policy: an overlay cannot change inject_hosts");
  if (overlay?.version !== undefined && overlay.version !== base.version) throw new Error("policy: overlay version mismatch");
  const out = { ...base };
  for (const kind of ["reads", "push_advertisement", "writes"]) {
    out[kind] = [...(base[kind] ?? []), ...(overlay?.[kind] ?? [])];
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------------------------------------------

function matchPattern(pattern, segments) {
  const b = { owner: null, repo: null, canonical: [] };
  let i = 0;
  for (const tok of pattern) {
    if (tok === "**") {
      for (; i < segments.length; i++) b.canonical.push(encodeURIComponent(segments[i]));
      return b;
    }
    const seg = segments[i];
    if (seg === undefined) return null;
    if (tok === "{owner}") {
      const v = seg.toLowerCase();
      if (!OWNER_RE.test(v)) return null;
      b.owner = v;
      b.canonical.push(v);
    } else if (tok === "{repo}") {
      const v = seg.toLowerCase().replace(/\.git$/, "");
      if (!REPO_RE.test(v) || v === "." || v === "..") return null;
      b.repo = v;
      b.canonical.push(v);
    } else if (tok === "{number}") {
      if (!NUMBER_RE.test(seg)) return null;
      b.canonical.push(seg);
    } else if (tok !== seg) {
      return null;
    } else {
      // Literal segments are part of the canonical path, so two listed verbs on one repository never share a hash
      // (found 2026-11-10: /repos/o/r/pulls and /repos/o/r/issues both canonicalised to "/o/r").
      b.canonical.push(seg);
    }
    i++;
  }
  return i === segments.length ? b : null;
}

function queryMatches(ruleQuery, rawQuery) {
  if (ruleQuery === null) return true;
  const params = new URLSearchParams(rawQuery);
  const keys = [...params.keys()];
  const want = Object.keys(ruleQuery);
  if (keys.length !== want.length) return false;
  return want.every((k) => params.getAll(k).length === 1 && params.get(k) === String(ruleQuery[k]));
}

function sortedQuery(rawQuery) {
  return [...new URLSearchParams(rawQuery).entries()].sort((a, b) => (a[0] + "\0" + a[1] < b[0] + "\0" + b[1] ? -1 : 1));
}

function findRule(rules, n) {
  for (const r of rules) {
    if (r.graphql !== null || r.recipe === "graphql") continue;
    if (r.host !== n.host || !r.methods.has(n.method)) continue;
    if (!queryMatches(r.query, n.query)) continue;
    const b = matchPattern(r.pattern, n.segments);
    if (b) return { rule: r, bind: b };
  }
  return null;
}

const refused = (subreason, extra = {}) => ({ verdict: "refused", subreason, ...extra });

function repoOf(bind) {
  return bind.owner && bind.repo ? `${bind.owner}/${bind.repo}` : null;
}

function inAllowlist(repo, repositories) {
  if (repo === null) return false;
  return (repositories ?? []).some((r) => String(r).toLowerCase() === repo);
}

// ---------------------------------------------------------------------------------------------------------------
// Protocol parsers
// ---------------------------------------------------------------------------------------------------------------

/** The ref-update commands of a git-receive-pack request body (before the pack). Throws on any malformed pkt-line. */
export function parseReceivePackCommands(buf) {
  const updates = [];
  let off = 0;
  for (;;) {
    if (off + 4 > buf.length) throw new Error("receive-pack: truncated");
    const lenHex = buf.toString("latin1", off, off + 4);
    if (!/^[0-9a-f]{4}$/.test(lenHex)) throw new Error("receive-pack: bad pkt-line length");
    const len = parseInt(lenHex, 16);
    if (len === 0) break;
    if (len < 5 || off + len > buf.length) throw new Error("receive-pack: bad pkt-line");
    let line = buf.toString("latin1", off + 4, off + len);
    off += len;
    if (line.endsWith("\n")) line = line.slice(0, -1);
    const nul = line.indexOf("\0");
    if (nul !== -1) line = line.slice(0, nul);
    if (updates.length === 0 && /^shallow [0-9a-f]{40,64}$/.test(line)) continue;
    const m = line.match(/^(\S+) (\S+) (refs\/[^\s]+)$/);
    if (!m || !OID_RE.test(m[1]) || !OID_RE.test(m[2])) throw new Error("receive-pack: bad command");
    updates.push({ old: m[1], new: m[2], ref: m[3] });
  }
  if (updates.length === 0) throw new Error("receive-pack: no ref update");
  return updates;
}

/** The operation a GraphQL POST body selects, or a refusal subreason. */
export function selectGraphqlOperation(bodyBuf) {
  let body;
  try {
    body = JSON.parse(bodyBuf.toString("utf8"));
  } catch {
    return { error: "unparseable" };
  }
  if (Array.isArray(body)) return { error: "batched" };
  if (!body || typeof body !== "object" || typeof body.query !== "string") return { error: "unparseable" };
  if (body.variables !== undefined && body.variables !== null && (typeof body.variables !== "object" || Array.isArray(body.variables))) {
    return { error: "unparseable" };
  }
  let doc;
  try {
    doc = parseGraphql(body.query, { noLocation: true });
  } catch {
    return { error: "unparseable" };
  }
  const ops = doc.definitions.filter((d) => d.kind === Kind.OPERATION_DEFINITION);
  let op;
  if (body.operationName !== undefined && body.operationName !== null) {
    if (typeof body.operationName !== "string") return { error: "unparseable" };
    const named = ops.filter((o) => o.name?.value === body.operationName);
    if (named.length !== 1) return { error: "unparseable" };
    op = named[0];
  } else {
    if (ops.length !== 1) return { error: "unparseable" };
    op = ops[0];
  }
  const topFields = [];
  for (const sel of op.selectionSet.selections) {
    if (sel.kind !== Kind.FIELD) return { error: "unparseable" }; // a top-level fragment could hide a field
    topFields.push(sel.name.value);
  }
  return {
    type: op.operation,
    name: op.name?.value ?? null,
    topFields,
    documentSha256: sha256(printGraphql(doc)),
    variablesSha256: sha256(stableJson(body.variables ?? {})),
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------------------------------------------

function classifyGraphql(n, policy) {
  const readRule = policy.reads.find((r) => r.graphql === "query" && r.host === n.host && r.methods.has(n.method) && matchPattern(r.pattern, n.segments));
  const writeRule = policy.writes.find((r) => r.recipe === "graphql" && r.host === n.host && r.methods.has(n.method) && matchPattern(r.pattern, n.segments));
  if (!readRule && !writeRule) return null;
  const body = decodedBody(n);
  if (body === null) return refused("unparseable");
  const op = selectGraphqlOperation(body);
  if (op.error) return refused(op.error);
  if (op.type === "query") return readRule ? { verdict: "read", rule: readRule.id, repository: null } : refused("read-outside-allowlist");
  if (op.type !== "mutation" || !writeRule) return refused("unlisted-write");
  if (op.topFields.length === 0 || !op.topFields.every((f) => writeRule.mutationFields.has(f))) return refused("unlisted-write");
  return {
    verdict: "write",
    rule: writeRule.id,
    repository: null,
    canonical: {
      kind: "graphql",
      host: n.host,
      repository: null,
      operation_name: op.name,
      operation_type: op.type,
      fields: [...op.topFields].sort(),
      document_sha256: op.documentSha256,
      variables_sha256: op.variablesSha256,
    },
  };
}

function canonicalFor(rule, n, bind, repo) {
  if (rule.recipe === "git-push") {
    const body = decodedBody(n);
    if (body === null) return null;
    let updates;
    try {
      updates = parseReceivePackCommands(body);
    } catch {
      return null;
    }
    return { kind: "git-push", host: n.host, repository: repo, updates };
  }
  // rest
  const body = decodedBody(n);
  if (body === null) return null;
  return {
    kind: "rest",
    method: n.method,
    host: n.host,
    repository: repo,
    path: "/" + bind.canonical.join("/"),
    query: sortedQuery(n.query),
    body_sha256: sha256(body),
  };
}

/**
 * Classify a normalized request against a compiled policy and the session's repository allowlist.
 * Order: refusals of shape first, then GraphQL by selected operation, then reads, the push advertisement, writes.
 * @returns {{verdict: string, rule?: string, subreason?: string, detail?: string, repository?: string | null, canonical?: any}}
 */
export function classify(n, policy, { repositories } = {}) {
  if (!n?.ok) return refused("unparseable", { detail: n?.detail });
  if (!policy.injectHosts.has(n.host)) return refused("unparseable", { detail: "not-inject-host" });
  if (n.method === "CONNECT") return refused("unparseable", { detail: "connect" });

  const g = classifyGraphql(n, policy);
  if (g) return g;

  for (const [rules, verdict, outside] of [
    [policy.reads, "read", "read-outside-allowlist"],
    [policy.pushAdvert, "push-advert", "read-outside-allowlist"],
  ]) {
    const hit = findRule(rules, n);
    if (hit) {
      const repo = repoOf(hit.bind);
      return inAllowlist(repo, repositories) ? { verdict, rule: hit.rule.id, repository: repo } : refused(outside, { rule: hit.rule.id });
    }
  }

  const w = findRule(policy.writes, n);
  if (w) {
    const repo = repoOf(w.bind);
    if (!inAllowlist(repo, repositories)) return refused("write-outside-allowlist", { rule: w.rule.id });
    const canonical = canonicalFor(w.rule, n, w.bind, repo);
    if (canonical === null) return refused("unparseable", { rule: w.rule.id });
    return { verdict: "write", rule: w.rule.id, repository: repo, canonical };
  }

  return READ_METHODS.has(n.method) ? refused("read-outside-allowlist") : refused("unlisted-write");
}

/** HMAC-SHA-256 of the canonical action, hex. The key is required; there is no default. */
export function actionHash(canonical, key) {
  if (!canonical || typeof canonical !== "object") throw new Error("actionHash: canonical action required");
  const k = typeof key === "string" ? Buffer.from(key, "utf8") : key;
  if (!k || !(k instanceof Uint8Array) || k.length < 16) throw new Error("actionHash: an HMAC key of at least 16 bytes is required");
  return createHmac("sha256", k).update(stableJson(canonical)).digest("hex");
}

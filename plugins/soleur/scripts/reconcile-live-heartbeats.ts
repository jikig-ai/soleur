#!/usr/bin/env bun
// CLI wrapper for the source-vs-live Better Stack reconcile (#6549 item 2; monitors arm and
// unmanaged-live class #7884; logs_alert arm #8097).
//
// Reads the live payload from Better Stack, reconciles it against the executable MANIFEST +
// resolved `.tf` declarations (pure logic in ../lib/heartbeat-live-reconcile.ts), prints structured
// `SOLEUR_HEARTBEAT_RECONCILE_*` markers to stdout, and exits with a tri-state contract that the
// drift workflow branches on. It only READS; it never unpauses, creates or deletes anything.
//
// Better Stack API contract (list endpoints, measured 2026-09-15 with the READONLY token):
//   GET https://uptime.betterstack.com/api/v2/heartbeats
//   GET https://uptime.betterstack.com/api/v2/monitors
//   Authorization: Bearer <BETTERSTACK_API_TOKEN>
//   200 -> { data: [ { id: "<digits>", attributes: { … } } ],
//            pagination: { first, last, prev, next: "https://uptime.betterstack.com/api/v2/<ep>?page=2" | null } }
//
// Arms (each prints its markers; the exit code is derived from the emitted markers at the end —
// any ERROR line -> 1, else any MISMATCH line -> 2, else 0):
//   declarations  `for_each`/`count` resolved exactly from literal variable defaults (source defaults
//                 only — TF_VAR_* overrides are not seen); a shape it cannot resolve, or an
//                 override / *.tf.json file in the root:
//                 SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=unresolvable-declaration resource=<type.name|file>
//                 any other declaration failure (unbalanced block, unreadable dir), contained to its arm:
//                 SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=parse-error detail="<file>: <msg>"
//   heartbeats    (a) fed-but-paused / (b) absent-live per resolved instance, plus unmanaged-live:
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=<n> live=absent|paused reason=absent-live|fed-but-paused resource=<type.name> route=<reason>~resource.<type>.<name>[.<key>]
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=heartbeats reason=unmanaged-live id=<id> [dup=name] route=unmanaged-live~id.<id> name="<n>"
//                 SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats checked=<n> live=<n>
//   monitors      always runs (#7884):
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=<id> [dup=url] route=unmanaged-live~id.<id> url="<url>" name="<n>"
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=absent-live resource=<type.name> route=absent-live~resource.<type>.<name>[.<key>] url="<url>"
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=<id> resource=<type.name> field=<f> route=monitor-config-drift~id.<id>.<f> detail="declared=<v> live=<v>"
//                 SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=<n> live=<n> matched=<id,id,…>  (arm summary:
//                 printed whenever the read + declarations resolved, beside any MISMATCH rows)
//   logs_alert    (#8097 / ADR-218) reads GET https://telemetry.betterstack.com/api/v2/alerts (same
//                 global token) only when the root declares a `logtail_exploration_alert`:
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=<n> live=logs_alert reason=logs-alert-paused|logs-alert-absent resource=<type.name> route=<reason>~resource.<type>.<name> detail="<paused_reason>"
//   inventory     only when BOTH uptime reads succeeded:
//                 SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=<n> heartbeats=<n> total=<n>
//
// Per-read outcomes: 5xx/429/timeout (the per-request timeout covers the body read) after retries,
// or the overall run deadline passing -> `UNREACHABLE surface=<arm> detail="…"` (rc 0, no page);
// 401/403, a malformed body, a non-numeric row id, a non-boolean `paused` / alarm leaf, a row id
// already read, a monitors row without a string url, an off-endpoint / non-page-param / repeated
// `pagination.next`, or more than 50 pages -> `ERROR … reason=<kind> detail="…"` (rc 1). The arms are
// independent: one arm's ERROR never suppresses another arm's markers.
//
// Marker grammar: machine fields first; every MISMATCH line carries exactly one `route=` token
// (`ROUTE_TOKEN_RE`), unique per violation within a run; every vendor-sourced field (`url`, `name`,
// `detail`) last and double-quoted, with `"` percent-encoded as %22, line breaks / control / format
// (Cf) / private-use (Co) characters stripped and each vendor field capped at 200 characters.
// Routing tokens (`reason=`, `resource=`, `id=`, `surface=`, `route=`) are only ever read from the
// text before a line's first `"`, so vendor text cannot forge them.

import { readFileSync } from "node:fs";
import { join } from "node:path";

import { MANIFEST, type ManifestEntry } from "../lib/heartbeat-manifest";
import {
  assertNever,
  assertUniqueMonitorUrls,
  DeclarationParseError,
  type DiscoveredHeartbeat,
  type DiscoveredLogsAlert,
  type DiscoveredMonitor,
  findUnmanagedHeartbeats,
  type InfraVariables,
  type LiveHeartbeat,
  type LiveLogsAlert,
  type LiveMonitor,
  listTfFiles,
  matchedMonitorIds,
  parseHeartbeatBlocks,
  parseLogsAlertBlocks,
  parseMonitorBlocks,
  reconcileHeartbeats,
  reconcileLogsAlerts,
  reconcileMonitors,
  resolveInfraVariables,
  resolveInfraVariablesPerFile,
  routeToken,
  UnresolvableDeclaration,
  type Violation,
} from "../lib/heartbeat-live-reconcile";

export { ROUTE_TOKEN_RE, VIOLATION_REASONS, type ViolationReason } from "../lib/heartbeat-live-reconcile";

const UPTIME_HOST = "uptime.betterstack.com";
const HEARTBEATS_PATH = "/api/v2/heartbeats";
const MONITORS_PATH = "/api/v2/monitors";
const HEARTBEATS_URL = `https://${UPTIME_HOST}${HEARTBEATS_PATH}`;
export const MONITORS_URL = `https://${UPTIME_HOST}${MONITORS_PATH}`;
// (#8097) The Telemetry (Logs) API lives on a SECOND host. A second EXACT constant, deliberately —
// never a suffix match on `betterstack.com`: `telemetry.betterstack.com.evil.example` must be refused.
const LOGS_ALERTS_HOST = "telemetry.betterstack.com";
const LOGS_ALERTS_PATH = "/api/v2/alerts";
const LOGS_ALERTS_URL = `https://${LOGS_ALERTS_HOST}${LOGS_ALERTS_PATH}`;

/** A reader never follows more pages than this; hitting it is an ERROR, not a truncated OK. */
export const MAX_PAGES = 50;

/** Default overall run deadline (all arms, all pages, all retries). Past it, an arm is UNREACHABLE. */
export const RUN_DEADLINE_MS = 240_000;

/** The only query params a vendor `pagination.next` may carry. */
const PAGE_PARAMS = new Set(["page", "per_page"]);

/**
 * Only ever attach the Bearer token to the trusted Better Stack host over HTTPS, and only to the
 * arm's own endpoint. `pagination.next` comes from the RESPONSE BODY, so a MITM or a
 * malicious/compromised response could point it at an attacker host to exfiltrate the token, or at
 * another endpoint to substitute its payload — pin host, default port, no userinfo, the exact
 * pathname, and only `page` / `per_page` query params (SSRF / credential-exfiltration /
 * endpoint-switch / filtered-view guard). A `#fragment` is ignored (never sent, never part of a
 * page's identity).
 */
function isAllowedUrlFor(host: string, pathname: string, u: string): boolean {
  try {
    const parsed = new URL(u);
    return (
      parsed.protocol === "https:" &&
      parsed.hostname === host &&
      parsed.port === "" &&
      parsed.username === "" &&
      parsed.password === "" &&
      parsed.pathname === pathname &&
      [...parsed.searchParams.keys()].every((k) => PAGE_PARAMS.has(k))
    );
  } catch {
    return false;
  }
}

/**
 * A page's identity: origin + path + sorted page params, with `page` defaulting to 1 and numeric
 * values canonicalized (`01` -> `1`), fragment dropped — so equivalent spellings of one page collide.
 */
function pageKey(u: string): string {
  const parsed = new URL(u);
  const params = new Map<string, string>([["page", "1"]]);
  for (const [k, v] of parsed.searchParams) params.set(k, /^[0-9]+$/.test(v) ? String(Number(v)) : v);
  const query = [...params]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
  return `${parsed.origin}${parsed.pathname}?${query.join("&")}`;
}

function withoutHash(u: string): string {
  const parsed = new URL(u);
  parsed.hash = "";
  return parsed.href;
}

type PagedResult<T> =
  | { ok: true; live: T[] }
  | { ok: false; kind: "unreachable" | "auth" | "error"; detail?: string };
export type FetchResult = PagedResult<LiveHeartbeat>;
export type MonitorsFetchResult = PagedResult<LiveMonitor>;
export type LogsAlertsFetchResult = PagedResult<LiveLogsAlert>;

export interface FetchOptions {
  token: string;
  fetchImpl?: (url: string, init?: RequestInit) => Promise<Response>;
  sleepImpl?: (ms: number) => Promise<void>;
  /** Clock seam for the run deadline (ms). Default `Date.now`. */
  nowImpl?: () => number;
  /** Max attempts per page on a transient failure (5xx/429/network/timeout). Default 3. */
  maxAttempts?: number;
  /** Per-request timeout in ms, covering the response headers AND the body read. Default 10_000. */
  timeoutMs?: number;
  /** Overall run deadline in ms, from the start of the run (or of a direct fetch call). Default 240_000. */
  runDeadlineMs?: number;
  /** Absolute deadline (`nowImpl()` scale); set once by `runReconcile` so every arm shares one budget. */
  deadlineAt?: number;
}

const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** A list row the reader refuses (never skips): surfaces as `error`, rc 1. */
class RowError extends Error {}

/** A request (headers or body) that outlived its per-request timeout — transient. */
class RequestTimeout extends Error {}

/** Vendor row id as a numeric string, or a `RowError`. */
function numericId(id: unknown): string {
  if (typeof id === "string" && /^[0-9]+$/.test(id)) return id;
  if (typeof id === "number" && Number.isSafeInteger(id) && id >= 0) return String(id);
  throw new RowError("row id is not numeric");
}

/** A boolean leaf the reconcile compares: anything but a real boolean is refused (fail closed). */
function boolField(attrs: Record<string, unknown>, key: string, what: string): boolean {
  const v = attrs[key];
  if (typeof v !== "boolean") throw new RowError(`${what} has a non-boolean ${key}`);
  return v;
}

/** A numeric leaf: a finite number or null; anything else is refused. */
function numberOrNull(attrs: Record<string, unknown>, key: string, what: string): number | null {
  const v = attrs[key];
  if (v === null || v === undefined) return null;
  if (typeof v !== "number" || !Number.isFinite(v)) throw new RowError(`${what} has a non-numeric ${key}`);
  return v;
}

/** A string leaf: a string or null; anything else is refused. */
function stringOrNull(attrs: Record<string, unknown>, key: string, what: string): string | null {
  const v = attrs[key];
  if (v === null || v === undefined) return null;
  if (typeof v !== "string") throw new RowError(`${what} has a non-string ${key}`);
  return v;
}

/**
 * Fetch every live heartbeat (following `pagination.next`) with depth-bounded retry.
 *
 * - transient (5xx / 429 / thrown network/abort error / request timeout): retry up to
 *   `maxAttempts` with exponential backoff (1s/2s/4s); exhausted, or the run deadline passed ->
 *   `unreachable` (the caller must NOT page — Sentry stays ok).
 * - auth (401/403): NOT transient -> `auth` immediately, no retry.
 * - other non-2xx, a malformed 200 body, a non-numeric id, a non-string name or a non-boolean
 *   `paused`: `error`.
 *
 * Network is injected (`fetchImpl`/`sleepImpl`/`nowImpl`) so the retry/auth/pagination/deadline
 * branches are unit-testable without a token or the live API.
 */
export async function fetchLiveHeartbeats(opts: FetchOptions): Promise<FetchResult> {
  return fetchPaged(HEARTBEATS_URL, (u) => isAllowedUrlFor(UPTIME_HOST, HEARTBEATS_PATH, u), opts, (attrs, id) => {
    const rowId = numericId(id);
    const what = `heartbeat ${rowId}`;
    if (!attrs || typeof attrs.name !== "string") throw new RowError(`${what} has no string name`);
    return { id: rowId, name: attrs.name, paused: boolField(attrs, "paused", what) };
  });
}

/** (#7884) Every live uptime monitor (`GET /api/v2/monitors`), same retry/auth/pagination contract. */
export async function fetchLiveMonitors(opts: FetchOptions): Promise<MonitorsFetchResult> {
  return fetchPaged(MONITORS_URL, (u) => isAllowedUrlFor(UPTIME_HOST, MONITORS_PATH, u), opts, (attrs, id) => {
    const rowId = numericId(id);
    const what = `monitor ${rowId}`;
    if (!attrs || typeof attrs.url !== "string") throw new RowError(`${what} has no string url`);
    const days = attrs.maintenance_days;
    if (days !== null && days !== undefined && !(Array.isArray(days) && days.every((d) => typeof d === "string"))) {
      throw new RowError(`${what} has a malformed maintenance_days`);
    }
    return {
      id: rowId,
      url: attrs.url,
      name: typeof attrs.pronounceable_name === "string" ? attrs.pronounceable_name : "",
      monitorType: typeof attrs.monitor_type === "string" ? attrs.monitor_type : "",
      requiredKeyword: typeof attrs.required_keyword === "string" ? attrs.required_keyword : null,
      paused: boolField(attrs, "paused", what),
      email: boolField(attrs, "email", what),
      call: boolField(attrs, "call", what),
      sms: boolField(attrs, "sms", what),
      push: boolField(attrs, "push", what),
      verifySsl: boolField(attrs, "verify_ssl", what),
      followRedirects: boolField(attrs, "follow_redirects", what),
      confirmationPeriod: numberOrNull(attrs, "confirmation_period", what),
      checkFrequency: numberOrNull(attrs, "check_frequency", what),
      requestTimeout: numberOrNull(attrs, "request_timeout", what),
      recoveryPeriod: numberOrNull(attrs, "recovery_period", what),
      maintenanceFrom: stringOrNull(attrs, "maintenance_from", what),
      maintenanceTo: stringOrNull(attrs, "maintenance_to", what),
      maintenanceDays: (days as string[] | null | undefined) ?? null,
    };
  });
}

/** (#8097) Every live Logs alert (`GET /api/v2/alerts`), same retry/auth/pagination contract. */
export async function fetchLiveLogsAlerts(opts: FetchOptions): Promise<LogsAlertsFetchResult> {
  return fetchPaged(LOGS_ALERTS_URL, (u) => isAllowedUrlFor(LOGS_ALERTS_HOST, LOGS_ALERTS_PATH, u), opts, (attrs) => {
    if (attrs && typeof attrs.name === "string") {
      // Coalesced ONCE, here: null/absent/non-string -> "" so every consumer reads a plain string.
      return {
        name: attrs.name,
        paused: boolField(attrs, "paused", "logs alert"),
        pausedReason: typeof attrs.paused_reason === "string" ? attrs.paused_reason : "",
      };
    }
    return null;
  });
}

type Attempt =
  | { type: "retry"; detail: string }
  | { type: "final"; result: { ok: false; kind: "auth" | "error"; detail: string } }
  | { type: "body"; body: unknown };

/**
 * Fetch every page of a Better Stack list endpoint (following `pagination.next`) with
 * depth-bounded retry. The retry/auth/pagination contract documented on the heartbeat wrapper's
 * header lives here:
 * - transient (5xx / 429 / thrown network/abort error / a request — headers or body — outliving
 *   `timeoutMs`): retry up to `maxAttempts` with exponential backoff (1s/2s/4s); exhausted ->
 *   `unreachable` (the caller must NOT page). The run deadline is checked before every attempt;
 *   past it -> `unreachable` too.
 * - auth (401/403): NOT transient -> `auth` immediately, no retry.
 * - other non-2xx, an HTTP 3xx (never followed), a malformed 200 body, a row `mapAttrs` refuses
 *   (throws `RowError`), a row id already read (on this or an earlier page), a `pagination.next`
 *   that fails `isAllowedUrl` or names an already-read page (`pageKey`), or more than `MAX_PAGES`
 *   pages: `error`.
 */
async function fetchPaged<T>(
  startUrl: string,
  isAllowedUrl: (u: string) => boolean,
  opts: FetchOptions,
  mapAttrs: (attrs: Record<string, unknown> | undefined, id: unknown) => T | null,
): Promise<PagedResult<T>> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleepImpl = opts.sleepImpl ?? defaultSleep;
  const now = opts.nowImpl ?? Date.now;
  const maxAttempts = opts.maxAttempts ?? 3;
  const timeoutMs = opts.timeoutMs ?? 10_000;
  const deadlineAt = opts.deadlineAt ?? now() + (opts.runDeadlineMs ?? RUN_DEADLINE_MS);

  const attemptOnce = async (target: string): Promise<Attempt> => {
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const budget = Math.max(1, Math.min(timeoutMs, deadlineAt - now()));
    // ONE timer per attempt, raced against both the headers and the body read.
    const expired = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new RequestTimeout(`request timed out after ${budget}ms`));
      }, budget);
    });
    expired.catch(() => {});
    try {
      let resp: Response;
      try {
        resp = await Promise.race([
          fetchImpl(target, {
            headers: { Authorization: `Bearer ${opts.token}`, Accept: "application/json" },
            signal: controller.signal,
            // Do NOT auto-follow HTTP redirects: `fetch`'s default `redirect: "follow"` would re-issue
            // the request — with the Bearer token attached — to a `Location` we never validate (a
            // MITM/DNS-takeover/compromised-edge 3xx could exfiltrate the token). We inspect any 3xx
            // ourselves below and refuse it. The API paginates via the response body (`pagination.next`,
            // pinned by `isAllowedUrl`), never via HTTP redirects.
            redirect: "manual",
          }),
          expired,
        ]);
      } catch (err) {
        // Thrown network/abort/timeout error — transient.
        return { type: "retry", detail: String((err as Error)?.message ?? err) };
      }
      if (resp.status === 401 || resp.status === 403) {
        return { type: "final", result: { ok: false, kind: "auth", detail: `HTTP ${resp.status}` } };
      }
      // `redirect: "manual"` surfaces 3xx here instead of auto-following. The API never legitimately
      // redirects, so refuse fail-closed — the token is never re-sent to a redirect target.
      if (resp.status >= 300 && resp.status < 400) {
        return { type: "final", result: { ok: false, kind: "error", detail: `unexpected redirect (HTTP ${resp.status})` } };
      }
      if (resp.status === 429 || resp.status >= 500) return { type: "retry", detail: `HTTP ${resp.status}` };
      if (!resp.ok) return { type: "final", result: { ok: false, kind: "error", detail: `HTTP ${resp.status}` } };
      try {
        // The same timer covers the body: a server that sends headers then stalls cannot hang the run.
        return { type: "body", body: await Promise.race([resp.json(), expired]) };
      } catch (err) {
        if (err instanceof RequestTimeout) return { type: "retry", detail: err.message };
        return { type: "final", result: { ok: false, kind: "error", detail: `invalid JSON: ${String((err as Error)?.message ?? err)}` } };
      }
    } finally {
      clearTimeout(timer);
    }
  };

  const live: T[] = [];
  const seenPages = new Set<string>();
  const seenIds = new Set<string>();
  let url: string | null = startUrl;
  let pages = 0;

  while (url) {
    if (pages >= MAX_PAGES) {
      return { ok: false, kind: "error", detail: `pagination exceeded ${MAX_PAGES} pages` };
    }
    pages++;
    seenPages.add(pageKey(url));
    let body: unknown;
    let fetched = false;
    let lastDetail = "retries exhausted";
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      if (now() >= deadlineAt) return { ok: false, kind: "unreachable", detail: "run deadline exceeded" };
      const outcome = await attemptOnce(url);
      if (outcome.type === "final") return outcome.result;
      if (outcome.type === "body") {
        body = outcome.body;
        fetched = true;
        break;
      }
      lastDetail = outcome.detail;
      if (attempt < maxAttempts) await sleepImpl(1000 * 2 ** (attempt - 1));
    }
    if (!fetched) return { ok: false, kind: "unreachable", detail: lastDetail };

    const data = (body as { data?: unknown })?.data;
    if (!Array.isArray(data)) {
      return { ok: false, kind: "error", detail: "response has no `data` array" };
    }
    for (const row of data) {
      const r = row as { id?: unknown; attributes?: Record<string, unknown> } | null;
      if (typeof r?.id === "string" || typeof r?.id === "number") {
        const key = String(r.id);
        if (seenIds.has(key)) return { ok: false, kind: "error", detail: `row id ${key} was already read (pages overlap)` };
        seenIds.add(key);
      }
      let mapped: T | null;
      try {
        mapped = mapAttrs(r?.attributes, r?.id);
      } catch (err) {
        if (err instanceof RowError) return { ok: false, kind: "error", detail: err.message };
        throw err;
      }
      if (mapped !== null) live.push(mapped);
    }
    const next = (body as { pagination?: { next?: unknown } })?.pagination?.next;
    if (typeof next === "string" && next.length > 0) {
      if (!isAllowedUrl(next)) {
        // Fail loud rather than either following the token off-host / off-endpoint OR silently
        // reconciling against a truncated or filtered payload (which would false-OK a real mismatch).
        let where = "unparseable";
        try {
          const p = new URL(next);
          where = `${p.host}${p.pathname}`;
        } catch {
          /* keep placeholder */
        }
        return { ok: false, kind: "error", detail: `refusing off-endpoint pagination.next (${where})` };
      }
      if (seenPages.has(pageKey(next))) {
        return { ok: false, kind: "error", detail: "pagination.next repeats an already-read page" };
      }
      url = withoutHash(next);
    } else {
      url = null;
    }
  }

  return { ok: true, live };
}

/**
 * Read every `.tf` file in an infra directory whose text mentions `needle`, and parse it. A parse
 * failure that is not an `UnresolvableDeclaration` is rethrown as a `DeclarationParseError` naming
 * the file, so the marker says where to look.
 */
function discoverFromInfra<T>(infraDir: string, needle: string, parse: (tf: string) => T[]): T[] {
  const discovered: T[] = [];
  for (const file of listTfFiles(infraDir)) {
    try {
      const text = readFileSync(join(infraDir, file), "utf8");
      if (!text.includes(needle)) continue;
      discovered.push(...parse(text));
    } catch (err) {
      if (err instanceof UnresolvableDeclaration) throw err;
      throw new DeclarationParseError(file, String((err as Error)?.message ?? err));
    }
  }
  return discovered;
}
/** Every resolved heartbeat instance in the root. Throws `UnresolvableDeclaration` / `DeclarationParseError`. */
export function discoverHeartbeatsFromInfra(infraDir: string, vars: InfraVariables = resolveInfraVariables(infraDir)): DiscoveredHeartbeat[] {
  return discoverFromInfra(infraDir, "betteruptime_heartbeat", (t) => parseHeartbeatBlocks(t, vars));
}
/** (#7884) Every resolved monitor instance in the root, URL-unique. Throws `UnresolvableDeclaration` / `DeclarationParseError`. */
export function discoverMonitorsFromInfra(infraDir: string, vars: InfraVariables = resolveInfraVariables(infraDir)): DiscoveredMonitor[] {
  const declared = discoverFromInfra(infraDir, "betteruptime_monitor", (t) => parseMonitorBlocks(t, vars));
  assertUniqueMonitorUrls(declared);
  return declared;
}
/** (#8097) Every `logtail_exploration_alert` block in the root — the `logs_alert` arm's expected set. */
export function discoverLogsAlertsFromInfra(infraDir: string): DiscoveredLogsAlert[] {
  return discoverFromInfra(infraDir, "logtail_exploration_alert", parseLogsAlertBlocks);
}

/**
 * Sanitize a marker line: turn line breaks, C0 controls, DEL and backticks into a space (so a value
 * can never inject a GitHub Actions `::annotation::`, start a forged marker line, or break out of the
 * code fence in the auto-filed issue body), and remove C1 controls (U+0080-U+009F, incl. NEL
 * U+0085), every format character (`\p{Cf}`: zero-width U+200B-U+200F, soft hyphen U+00AD, bidi
 * embeddings/overrides/isolates U+202A-U+202E / U+2066-U+2069, word joiner U+2060, BOM U+FEFF, tag
 * characters U+E0001…), private-use characters (`\p{Co}`) and lone surrogates (`\p{Cs}`), so nothing
 * invisible can visually reorder or hide a routing token. Vendor free text (`paused_reason`, monitor
 * `url`/`pronounceable_name`, heartbeat `name`) flows through here.
 * Escapes only — cq-regex-unicode-separators-escape-only.
 */
const INVISIBLE = /[\p{Cf}\p{Co}\p{Cs}\u0080-\u009f]+/gu;
const BREAKING = /[\r\n\u2028\u2029\u0000-\u001f\u007f`]+/gu;
const oneLine = (s: string) => s.replace(INVISIBLE, "").replace(BREAKING, " ");

/** Max characters (code points) of any one vendor-sourced field in a marker, counted after sanitizing. */
export const VENDOR_FIELD_CAP = 200;

/** A vendor-sourced value for a quoted marker field: sanitized, capped, `"` -> `%22`. */
const quoted = (s: string) => Array.from(oneLine(s)).slice(0, VENDOR_FIELD_CAP).join("").replace(/"/g, "%22");

/** A source-derived value printed UNQUOTED before the first `"`: no quote or whitespace can split it. */
const bare = (s: string) => oneLine(s).replace(/"/g, "%22").replace(/\s/g, "%20");

interface RunResult {
  code: number;
  markers: string[];
}

export interface RunDeps {
  /** Injectable seam so harness rows can prove the arm's assertions are load-bearing. */
  reconcileMonitors?: typeof reconcileMonitors;
}

/** The one MISMATCH line for a violation. Exhaustive over the union (a new variant fails to compile). */
function mismatchMarker(v: Violation): string {
  const route = routeToken(v);
  const P = "SOLEUR_HEARTBEAT_RECONCILE_MISMATCH";
  switch (v.kind) {
    case "heartbeat":
      return `${P} name=${bare(v.liveName)} live=${v.live} reason=${v.reason} resource=betteruptime_heartbeat.${v.resourceName} ${route}`;
    case "logs_alert":
      // Prefix through `reason=` unchanged from ADR-218 / monitor-send-failed-alert.md; `resource=`
      // and `route=` follow, and the quoted vendor text stays last.
      return `${P} name=${bare(v.liveName)} live=${v.live} reason=${v.reason} resource=logtail_exploration_alert.${v.resourceName} ${route} detail="${quoted(v.detail ?? "")}"`;
    case "monitor":
      switch (v.reason) {
        case "absent-live":
          return `${P} surface=monitors reason=absent-live resource=betteruptime_monitor.${v.resourceName} ${route} url="${quoted(v.url)}"`;
        case "monitor-config-drift":
          return `${P} surface=monitors reason=monitor-config-drift id=${v.id} resource=betteruptime_monitor.${v.resourceName} field=${v.field} ${route} detail="${quoted(`declared=${v.declared} live=${v.live}`)}"`;
        default:
          return assertNever(v);
      }
    case "unmanaged":
      switch (v.surface) {
        case "monitors":
          return `${P} surface=monitors reason=unmanaged-live id=${v.id}${v.dup ? " dup=url" : ""} ${route} url="${quoted(v.url)}" name="${quoted(v.name)}"`;
        case "heartbeats":
          return `${P} surface=heartbeats reason=unmanaged-live id=${v.id}${v.dup ? " dup=name" : ""} ${route} name="${quoted(v.name)}"`;
        default:
          return assertNever(v);
      }
    default:
      return assertNever(v);
  }
}

type Discovery<T> = { ok: true; declared: T } | { ok: false; marker: string };

/** A declarations ERROR marker for any error: unresolvable shape, per-file parse failure, or anything else. */
function declarationErrorMarker(err: unknown, fallbackWhere: string): string {
  if (err instanceof UnresolvableDeclaration) {
    return oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=unresolvable-declaration resource=${bare(err.resource)}`);
  }
  const detail =
    err instanceof DeclarationParseError ? `${err.file}: ${err.detail}` : `${fallbackWhere}: ${String((err as Error)?.message ?? err)}`;
  return oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=parse-error detail="${quoted(detail)}"`);
}

function discover<T>(fn: () => T, where: string): Discovery<T> {
  try {
    return { ok: true, declared: fn() };
  } catch (err) {
    return { ok: false, marker: declarationErrorMarker(err, where) };
  }
}

export async function runReconcile(
  infraDir: string,
  opts: FetchOptions,
  manifest: readonly Pick<ManifestEntry, "name" | "feeder" | "arming_pending">[] = MANIFEST,
  deps: RunDeps = {},
): Promise<RunResult> {
  if (!opts.token) {
    return {
      code: 1,
      markers: ["SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=token-absent"],
    };
  }
  const reconcileMonitorsImpl = deps.reconcileMonitors ?? reconcileMonitors;
  // One deadline shared by every arm, page and retry.
  const now = opts.nowImpl ?? Date.now;
  const fetchOpts: FetchOptions = { ...opts, deadlineAt: opts.deadlineAt ?? now() + (opts.runDeadlineMs ?? RUN_DEADLINE_MS) };

  // ── Declarations: resolved once, per arm, and every failure contained to the arm it blinds ──
  const declMarkers = new Set<string>(); // a root-wide failure (override file) is reported once, not per arm
  let vars: InfraVariables = new Map();
  try {
    const resolution = resolveInfraVariablesPerFile(infraDir);
    vars = resolution.vars;
    for (const e of resolution.errors) declMarkers.add(declarationErrorMarker(e, infraDir));
  } catch (err) {
    declMarkers.add(declarationErrorMarker(err, infraDir));
  }
  const hbDecl = discover(() => discoverHeartbeatsFromInfra(infraDir, vars), infraDir);
  const monDecl = discover(() => discoverMonitorsFromInfra(infraDir, vars), infraDir);
  const alertDecl = discover(() => discoverLogsAlertsFromInfra(infraDir), infraDir);
  for (const d of [hbDecl, monDecl, alertDecl]) if (!d.ok) declMarkers.add(d.marker);

  // ── Arm 1: heartbeats (the original #6549 contract + #7884 unmanaged-live) ──
  const result = await fetchLiveHeartbeats(fetchOpts);
  const hbMarkers: string[] = [];
  if (!result.ok) {
    if (result.kind === "unreachable") {
      hbMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=heartbeats detail="${quoted(result.detail ?? "n/a")}"`));
    } else {
      // auth or malformed -> hard error (exit 1)
      hbMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=${result.kind} detail="${quoted(result.detail ?? "n/a")}"`));
    }
  } else if (hbDecl.ok) {
    const discovered = hbDecl.declared;
    const violations: Violation[] = [
      ...reconcileHeartbeats(manifest, discovered, result.live),
      ...findUnmanagedHeartbeats(discovered, result.live),
    ];
    for (const v of violations) hbMarkers.push(oneLine(mismatchMarker(v)));
    if (violations.length === 0) {
      hbMarkers.push(`SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats checked=${discovered.length} live=${result.live.length}`);
    }
  }

  // ── Arm 2 (#7884): uptime monitors — always runs, independent of arm 1's outcome ──
  const monitors = await fetchLiveMonitors(fetchOpts);
  const monMarkers: string[] = [];
  if (!monitors.ok) {
    if (monitors.kind === "unreachable") {
      monMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=monitors detail="${quoted(monitors.detail ?? "n/a")}"`));
    } else {
      monMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=monitors reason=${monitors.kind} detail="${quoted(monitors.detail ?? "n/a")}"`));
    }
  } else if (monDecl.ok) {
    const declared = monDecl.declared;
    for (const v of reconcileMonitorsImpl(declared, monitors.live)) monMarkers.push(oneLine(mismatchMarker(v)));
    // The monitors OK line is the arm's completion summary, printed whenever the read and the
    // declarations both resolved — even beside MISMATCH rows — so `matched=` is a positive control
    // that the arm saw each declared object (plan AC8: drift rows for 4226366 AND it in matched=).
    // It never lowers the combined code: the code is derived from the MISMATCH lines themselves.
    const ids = matchedMonitorIds(declared, monitors.live).join(",");
    monMarkers.push(`SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=${declared.length} live=${monitors.live.length} matched=${ids}`);
  }

  // ── Arm 3 (#8097): declared Logs alerts — INDEPENDENT of the uptime reads (different host), and
  // only when the root declares one, so a root without Logs alerts makes no telemetry read.
  const armMarkers: string[] = [];
  if (alertDecl.ok && alertDecl.declared.length > 0) {
    const declaredAlerts = alertDecl.declared;
    const alerts = await fetchLiveLogsAlerts(fetchOpts);
    if (!alerts.ok) {
      if (alerts.kind === "unreachable") {
        armMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=logs_alert detail="${quoted(alerts.detail ?? "n/a")}"`));
      } else {
        armMarkers.push(
          oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=logs_alert reason=${alerts.kind} detail="${quoted(alerts.detail ?? "n/a")}"`),
        );
      }
    } else {
      const violations = reconcileLogsAlerts(declaredAlerts, alerts.live);
      if (violations.length === 0) {
        armMarkers.push(`SOLEUR_HEARTBEAT_RECONCILE_OK surface=logs_alert declared=${declaredAlerts.length} live=${alerts.live.length}`);
      }
      for (const v of violations) armMarkers.push(oneLine(mismatchMarker(v)));
    }
  }

  // ── Inventory: a measured object count, only when both uptime lists were read in full ──
  const inventory: string[] = [];
  if (result.ok && monitors.ok) {
    const m = monitors.live.length;
    const h = result.live.length;
    inventory.push(`SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=${m} heartbeats=${h} total=${m + h}`);
  }

  // ERROR(1) > MISMATCH(2) > OK(0), derived from the rows actually emitted — combined only after
  // every arm has printed, so no code path can disagree with the markers.
  const markers = [...declMarkers, ...hbMarkers, ...monMarkers, ...armMarkers, ...inventory];
  const code = markers.some((m) => m.startsWith("SOLEUR_HEARTBEAT_RECONCILE_ERROR "))
    ? 1
    : markers.some((m) => m.startsWith("SOLEUR_HEARTBEAT_RECONCILE_MISMATCH "))
      ? 2
      : 0;
  return { code, markers };
}

async function main(): Promise<number> {
  const token = process.env.BETTERSTACK_API_TOKEN ?? "";
  // Repo-root-relative default; overridable for local dry-runs.
  const infraDir = process.env.RECONCILE_INFRA_DIR ?? "apps/web-platform/infra";
  const { code, markers } = await runReconcile(infraDir, { token });
  for (const m of markers) console.log(m);
  return code;
}

// Only auto-run as a CLI; importing for tests must not execute (bun `import.meta.main`).
if (import.meta.main) {
  main()
    .then((code) => process.exit(code))
    .catch((err) => {
      console.log(`SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=uncaught detail="${quoted(String(err?.message ?? err))}"`);
      process.exit(1);
    });
}

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
// Arms (each prints its markers; codes combine only at the end — ERROR(1) > MISMATCH(2) > OK(0)):
//   declarations  `for_each`/`count` resolved exactly from literal variable defaults; anything else:
//                 SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=unresolvable-declaration resource=<type.name>
//   heartbeats    (a) fed-but-paused / (b) absent-live per resolved instance, plus unmanaged-live:
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=<n> live=absent|paused reason=absent-live|fed-but-paused resource=<type.name>
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=heartbeats reason=unmanaged-live id=<id> [dup=name] name="<n>"
//                 SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats checked=<n> live=<n>
//   monitors      always runs (#7884):
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=<id> [dup=url] url="<url>" name="<n>"
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=absent-live resource=<type.name> url="<url>"
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=<id> resource=<type.name> field=<f> detail="declared=<v> live=<v>"
//                 SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=<n> live=<n> matched=<id,id,…>  (arm summary:
//                 printed whenever the read + declarations resolved, beside any MISMATCH rows)
//   logs_alert    (#8097 / ADR-218) reads GET https://telemetry.betterstack.com/api/v2/alerts (same
//                 global token) only when the root declares a `logtail_exploration_alert`:
//                 SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=<n> live=logs_alert reason=logs-alert-paused|logs-alert-absent resource=<type.name> detail="<paused_reason>"
//   inventory     only when BOTH uptime reads succeeded:
//                 SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=<n> heartbeats=<n> total=<n>
//
// Per-read outcomes: 5xx/429/timeout after retries → `UNREACHABLE surface=<arm> detail="…"` (rc 0, no
// page); 401/403, a malformed body, a non-numeric row id, a monitors row without a string url, an
// off-endpoint / repeated `pagination.next`, or more than 50 pages → `ERROR … reason=<kind> detail="…"`
// (rc 1). The arms are independent: one arm's ERROR never suppresses another arm's markers.
//
// Marker grammar: machine fields first; every vendor-sourced field (`url`, `name`, `detail`) last and
// double-quoted, with `"` percent-encoded as %22, invisible/bidi characters stripped and each vendor
// field capped at 200 characters. Routing tokens (`reason=`, `resource=`, `id=`, `surface=`) are only
// ever read from the text before a line's first `"`, so vendor text cannot forge them.

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { MANIFEST, type ManifestEntry } from "../lib/heartbeat-manifest";
import {
  assertUniqueMonitorUrls,
  type DiscoveredHeartbeat,
  type DiscoveredLogsAlert,
  type DiscoveredMonitor,
  findUnmanagedHeartbeats,
  type InfraVariables,
  type LiveHeartbeat,
  type LiveLogsAlert,
  type LiveMonitor,
  matchedMonitorIds,
  parseHeartbeatBlocks,
  parseLogsAlertBlocks,
  parseMonitorBlocks,
  reconcileHeartbeats,
  reconcileLogsAlerts,
  reconcileMonitors,
  resolveInfraVariables,
  UnresolvableDeclaration,
} from "../lib/heartbeat-live-reconcile";

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

/**
 * Only ever attach the Bearer token to the trusted Better Stack host over HTTPS, and only to the
 * arm's own endpoint. `pagination.next` comes from the RESPONSE BODY, so a MITM or a
 * malicious/compromised response could point it at an attacker host to exfiltrate the token, or at
 * another endpoint to substitute its payload — pin host, default port, no userinfo and the exact
 * pathname (SSRF / credential-exfiltration / endpoint-switch guard). The query is allowed: the
 * vendor's own `next` is `…?page=N` (plus `per_page` when one was sent).
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
      parsed.pathname === pathname
    );
  } catch {
    return false;
  }
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
  /** Max attempts per page on a transient failure (5xx/429/network). Default 3. */
  maxAttempts?: number;
  /** Per-request timeout in ms (AbortController). Default 10_000. */
  timeoutMs?: number;
}

const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** A list row the reader refuses (never skips): surfaces as `error`, rc 1. */
class RowError extends Error {}

/** Vendor row id as a numeric string, or a `RowError`. */
function numericId(id: unknown): string {
  if (typeof id === "string" && /^[0-9]+$/.test(id)) return id;
  if (typeof id === "number" && Number.isSafeInteger(id) && id >= 0) return String(id);
  throw new RowError("row id is not numeric");
}

/**
 * Fetch every live heartbeat (following `pagination.next`) with depth-bounded retry.
 *
 * - transient (5xx / 429 / thrown network/abort error): retry up to `maxAttempts` with exponential
 *   backoff (1s/2s/4s); exhausted -> `unreachable` (the caller must NOT page — Sentry stays ok).
 * - auth (401/403): NOT transient -> `auth` immediately, no retry.
 * - other non-2xx, a malformed 200 body, a non-numeric id or a non-string name: `error`.
 *
 * Network is injected (`fetchImpl`/`sleepImpl`) so the retry/auth/pagination branches are unit-
 * testable without a token or the live API.
 */
export async function fetchLiveHeartbeats(opts: FetchOptions): Promise<FetchResult> {
  return fetchPaged(HEARTBEATS_URL, (u) => isAllowedUrlFor(UPTIME_HOST, HEARTBEATS_PATH, u), opts, (attrs, id) => {
    const rowId = numericId(id);
    if (!attrs || typeof attrs.name !== "string") throw new RowError(`heartbeat ${rowId} has no string name`);
    return { id: rowId, name: attrs.name, paused: attrs.paused === true };
  });
}

/** (#7884) Every live uptime monitor (`GET /api/v2/monitors`), same retry/auth/pagination contract. */
export async function fetchLiveMonitors(opts: FetchOptions): Promise<MonitorsFetchResult> {
  return fetchPaged(MONITORS_URL, (u) => isAllowedUrlFor(UPTIME_HOST, MONITORS_PATH, u), opts, (attrs, id) => {
    const rowId = numericId(id);
    if (!attrs || typeof attrs.url !== "string") throw new RowError(`monitor ${rowId} has no string url`);
    return {
      id: rowId,
      url: attrs.url,
      name: typeof attrs.pronounceable_name === "string" ? attrs.pronounceable_name : "",
      monitorType: typeof attrs.monitor_type === "string" ? attrs.monitor_type : "",
      requiredKeyword: typeof attrs.required_keyword === "string" ? attrs.required_keyword : null,
      paused: attrs.paused === true,
    };
  });
}

/** (#8097) Every live Logs alert (`GET /api/v2/alerts`), same retry/auth/pagination contract. */
export async function fetchLiveLogsAlerts(opts: FetchOptions): Promise<LogsAlertsFetchResult> {
  return fetchPaged(LOGS_ALERTS_URL, (u) => isAllowedUrlFor(LOGS_ALERTS_HOST, LOGS_ALERTS_PATH, u), opts, (attrs) => {
    if (attrs && typeof attrs.name === "string") {
      // Coalesced ONCE, here: null/absent/non-string → "" so every consumer reads a plain string.
      return { name: attrs.name, paused: attrs.paused === true, pausedReason: typeof attrs.paused_reason === "string" ? attrs.paused_reason : "" };
    }
    return null;
  });
}

/**
 * Fetch every page of a Better Stack list endpoint (following `pagination.next`) with
 * depth-bounded retry. The retry/auth/pagination contract documented on the heartbeat wrapper's
 * header lives here:
 * - transient (5xx / 429 / thrown network/abort error): retry up to `maxAttempts` with exponential
 *   backoff (1s/2s/4s); exhausted -> `unreachable` (the caller must NOT page).
 * - auth (401/403): NOT transient -> `auth` immediately, no retry.
 * - other non-2xx, an HTTP 3xx (never followed), a malformed 200 body, a row `mapAttrs` refuses
 *   (throws `RowError`), a `pagination.next` that fails `isAllowedUrl` or repeats an already-read
 *   URL, or more than `MAX_PAGES` pages: `error`.
 */
async function fetchPaged<T>(
  startUrl: string,
  isAllowedUrl: (u: string) => boolean,
  opts: FetchOptions,
  mapAttrs: (attrs: Record<string, unknown> | undefined, id: unknown) => T | null,
): Promise<PagedResult<T>> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleepImpl = opts.sleepImpl ?? defaultSleep;
  const maxAttempts = opts.maxAttempts ?? 3;
  const timeoutMs = opts.timeoutMs ?? 10_000;

  const live: T[] = [];
  const seenUrls = new Set<string>();
  let url: string | null = startUrl;

  while (url) {
    if (seenUrls.size >= MAX_PAGES) {
      return { ok: false, kind: "error", detail: `pagination exceeded ${MAX_PAGES} pages` };
    }
    seenUrls.add(url);
    let pageOk = false;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      let resp: Response;
      try {
        resp = await fetchImpl(url, {
          headers: { Authorization: `Bearer ${opts.token}`, Accept: "application/json" },
          signal: controller.signal,
          // Do NOT auto-follow HTTP redirects: `fetch`'s default `redirect: "follow"` would re-issue
          // the request — with the Bearer token attached — to a `Location` we never validate (a
          // MITM/DNS-takeover/compromised-edge 3xx could exfiltrate the token). We inspect any 3xx
          // ourselves below and refuse it. The API paginates via the response body (`pagination.next`,
          // pinned by `isAllowedUrl`), never via HTTP redirects.
          redirect: "manual",
        });
      } catch (err) {
        // Thrown network/abort/timeout error — transient. Retry if attempts remain.
        clearTimeout(timer);
        if (attempt < maxAttempts) {
          await sleepImpl(1000 * 2 ** (attempt - 1));
          continue;
        }
        return { ok: false, kind: "unreachable", detail: String((err as Error)?.message ?? err) };
      } finally {
        clearTimeout(timer);
      }

      if (resp.status === 401 || resp.status === 403) {
        return { ok: false, kind: "auth", detail: `HTTP ${resp.status}` };
      }
      // `redirect: "manual"` surfaces 3xx here instead of auto-following. The API never legitimately
      // redirects, so refuse fail-closed — the token is never re-sent to a redirect target.
      if (resp.status >= 300 && resp.status < 400) {
        return { ok: false, kind: "error", detail: `unexpected redirect (HTTP ${resp.status})` };
      }
      if (resp.status === 429 || resp.status >= 500) {
        // Transient — retry if attempts remain.
        if (attempt < maxAttempts) {
          await sleepImpl(1000 * 2 ** (attempt - 1));
          continue;
        }
        return { ok: false, kind: "unreachable", detail: `HTTP ${resp.status}` };
      }
      if (!resp.ok) {
        return { ok: false, kind: "error", detail: `HTTP ${resp.status}` };
      }

      let body: unknown;
      try {
        body = await resp.json();
      } catch (err) {
        return { ok: false, kind: "error", detail: `invalid JSON: ${String((err as Error)?.message ?? err)}` };
      }
      const data = (body as { data?: unknown })?.data;
      if (!Array.isArray(data)) {
        return { ok: false, kind: "error", detail: "response has no `data` array" };
      }
      for (const row of data) {
        const r = row as { id?: unknown; attributes?: Record<string, unknown> } | null;
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
          // reconciling against a truncated payload (which would false-OK a real mismatch).
          let where = "unparseable";
          try {
            const p = new URL(next);
            where = `${p.host}${p.pathname}`;
          } catch {
            /* keep placeholder */
          }
          return { ok: false, kind: "error", detail: `refusing off-endpoint pagination.next (${where})` };
        }
        if (seenUrls.has(next)) {
          return { ok: false, kind: "error", detail: "pagination.next repeats an already-read page" };
        }
        url = next;
      } else {
        url = null;
      }
      pageOk = true;
      break;
    }
    if (!pageOk) return { ok: false, kind: "unreachable", detail: "retries exhausted" };
  }

  return { ok: true, live };
}

/** Read every `.tf` file in an infra directory whose text mentions `needle`, and parse it. */
function discoverFromInfra<T>(infraDir: string, needle: string, parse: (tf: string) => T[]): T[] {
  const discovered: T[] = [];
  for (const file of readdirSync(infraDir).sort()) {
    if (!file.endsWith(".tf")) continue;
    const text = readFileSync(join(infraDir, file), "utf8");
    if (!text.includes(needle)) continue;
    discovered.push(...parse(text));
  }
  return discovered;
}
/** Every resolved heartbeat instance in the root. Throws `UnresolvableDeclaration`. */
export function discoverHeartbeatsFromInfra(infraDir: string, vars: InfraVariables = resolveInfraVariables(infraDir)): DiscoveredHeartbeat[] {
  return discoverFromInfra(infraDir, "betteruptime_heartbeat", (t) => parseHeartbeatBlocks(t, vars));
}
/** (#7884) Every resolved monitor instance in the root, URL-unique. Throws `UnresolvableDeclaration`. */
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
 * Sanitize a marker line: strip CR/LF (so it can never inject a GitHub Actions `::annotation::`) and
 * backticks (so a name can never break out of the ``` code fence in the auto-filed issue body).
 * Vendor free text (`paused_reason`, monitor `url`/`pronounceable_name`, heartbeat `name`) flows
 * through here, so the class covers every line/paragraph separator and control character, and the
 * invisible/bidi class (zero-width U+200B-U+200F, embeddings/overrides U+202A-U+202E, isolates
 * U+2066-U+2069, BOM U+FEFF) is removed outright so it cannot visually reorder a routing token.
 * Escapes only — cq-regex-unicode-separators-escape-only.
 */
const INVISIBLE = /[\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]+/g;
const oneLine = (s: string) => s.replace(INVISIBLE, "").replace(/[\r\n\u2028\u2029\x00-\x1f\x7f`]+/g, " ");

/** Max characters of any one vendor-sourced field in a marker. */
export const VENDOR_FIELD_CAP = 200;

/** A vendor-sourced value for a quoted marker field: sanitized, capped, `"` → `%22`. */
const quoted = (s: string) => Array.from(oneLine(s)).slice(0, VENDOR_FIELD_CAP).join("").replace(/"/g, "%22");

interface RunResult {
  code: number;
  markers: string[];
}

export interface RunDeps {
  /** Injectable seam so harness rows can prove the arm's assertions are load-bearing. */
  reconcileMonitors?: typeof reconcileMonitors;
}

type Discovery<T> = { ok: true; declared: T } | { ok: false; marker: string };

function discover<T>(fn: () => T): Discovery<T> {
  try {
    return { ok: true, declared: fn() };
  } catch (err) {
    if (err instanceof UnresolvableDeclaration) {
      return {
        ok: false,
        marker: oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=unresolvable-declaration resource=${err.resource}`),
      };
    }
    throw err;
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

  // ── Declarations: resolved once, per arm, so an unresolvable heartbeat never blinds monitors ──
  const vars = resolveInfraVariables(infraDir);
  const hbDecl = discover(() => discoverHeartbeatsFromInfra(infraDir, vars));
  const monDecl = discover(() => discoverMonitorsFromInfra(infraDir, vars));
  const declMarkers: string[] = [];
  let declCode = 0;
  for (const d of [hbDecl, monDecl]) {
    if (!d.ok) {
      declCode = 1;
      declMarkers.push(d.marker);
    }
  }

  // ── Arm 1: heartbeats (the original #6549 contract + #7884 unmanaged-live) ──
  const result = await fetchLiveHeartbeats(opts);
  let hbCode = 0;
  const hbMarkers: string[] = [];
  if (!result.ok) {
    if (result.kind === "unreachable") {
      hbMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=heartbeats detail="${quoted(result.detail ?? "n/a")}"`));
    } else {
      // auth or malformed -> hard error (exit 1)
      hbCode = 1;
      hbMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=${result.kind} detail="${quoted(result.detail ?? "n/a")}"`));
    }
  } else if (hbDecl.ok) {
    const discovered = hbDecl.declared;
    const violations = reconcileHeartbeats(manifest, discovered, result.live);
    const unmanaged = findUnmanagedHeartbeats(discovered, result.live);
    for (const v of violations) {
      hbMarkers.push(
        oneLine(`SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=${v.liveName} live=${v.live} reason=${v.reason} resource=betteruptime_heartbeat.${v.resourceName}`),
      );
    }
    for (const u of unmanaged) {
      hbMarkers.push(
        oneLine(`SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=heartbeats reason=unmanaged-live id=${u.id}${u.dup ? " dup=name" : ""} name="${quoted(u.name)}"`),
      );
    }
    if (violations.length + unmanaged.length === 0) {
      hbMarkers.push(`SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats checked=${discovered.length} live=${result.live.length}`);
    } else {
      hbCode = 2;
    }
  }

  // ── Arm 2 (#7884): uptime monitors — always runs, independent of arm 1's outcome ──
  const monitors = await fetchLiveMonitors(opts);
  let monCode = 0;
  const monMarkers: string[] = [];
  if (!monitors.ok) {
    if (monitors.kind === "unreachable") {
      monMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=monitors detail="${quoted(monitors.detail ?? "n/a")}"`));
    } else {
      monCode = 1;
      monMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=monitors reason=${monitors.kind} detail="${quoted(monitors.detail ?? "n/a")}"`));
    }
  } else if (monDecl.ok) {
    const declared = monDecl.declared;
    const violations = reconcileMonitorsImpl(declared, monitors.live);
    for (const v of violations) {
      if (v.kind === "unmanaged" && v.surface === "monitors") {
        monMarkers.push(
          oneLine(
            `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=${v.id}${v.dup ? " dup=url" : ""} url="${quoted(v.url)}" name="${quoted(v.name)}"`,
          ),
        );
      } else if (v.kind === "monitor" && v.reason === "absent-live") {
        monMarkers.push(
          oneLine(`SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=absent-live resource=betteruptime_monitor.${v.resourceName} url="${quoted(v.url)}"`),
        );
      } else if (v.kind === "monitor" && v.reason === "monitor-config-drift") {
        monMarkers.push(
          oneLine(
            `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=${v.id} resource=betteruptime_monitor.${v.resourceName} field=${v.field} detail="${quoted(`declared=${v.declared} live=${v.live}`)}"`,
          ),
        );
      }
    }
    // The monitors OK line is the arm's completion summary, printed whenever the read and the
    // declarations both resolved — even beside MISMATCH rows — so `matched=` is a positive control
    // that the arm saw each declared object (plan AC8: drift rows for 4226366 AND it in matched=).
    // It never lowers the combined code; a mismatch still makes the run rc 2.
    const ids = matchedMonitorIds(declared, monitors.live).join(",");
    monMarkers.push(`SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=${declared.length} live=${monitors.live.length} matched=${ids}`);
    if (violations.length > 0) monCode = 2;
  }

  // ── Arm 3 (#8097): declared Logs alerts — INDEPENDENT of the uptime reads (different host), and
  // only when the root declares one, so a root without Logs alerts makes no telemetry read.
  const declaredAlerts = discoverLogsAlertsFromInfra(infraDir);
  const armMarkers: string[] = [];
  let armCode = 0;
  if (declaredAlerts.length > 0) {
    const alerts = await fetchLiveLogsAlerts(opts);
    if (!alerts.ok) {
      if (alerts.kind === "unreachable") {
        armMarkers.push(oneLine(`SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=logs_alert detail="${quoted(alerts.detail ?? "n/a")}"`));
      } else {
        armCode = 1;
        armMarkers.push(
          oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=logs_alert reason=${alerts.kind} detail="${quoted(alerts.detail ?? "n/a")}"`),
        );
      }
    } else {
      const violations = reconcileLogsAlerts(declaredAlerts, alerts.live);
      if (violations.length === 0) {
        armMarkers.push(
          `SOLEUR_HEARTBEAT_RECONCILE_OK surface=logs_alert declared=${declaredAlerts.length} live=${alerts.live.length}`,
        );
      }
      for (const v of violations) {
        armCode = 2;
        // Prefix byte-identical to ADR-218 / monitor-send-failed-alert.md; `resource=` sits
        // immediately before the quoted vendor text so the vendor text stays last.
        armMarkers.push(
          oneLine(
            `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=${v.liveName} live=${v.live} reason=${v.reason} resource=logtail_exploration_alert.${v.resourceName} detail="${quoted(v.detail ?? "")}"`,
          ),
        );
      }
    }
  }

  // ── Inventory: a measured object count, only when both uptime lists were read in full ──
  const inventory: string[] = [];
  if (result.ok && monitors.ok) {
    const m = monitors.live.length;
    const h = result.live.length;
    inventory.push(`SOLEUR_HEARTBEAT_RECONCILE_INVENTORY monitors=${m} heartbeats=${h} total=${m + h}`);
  }

  // ERROR(1) > MISMATCH(2) > OK(0) across every arm — combined only after all markers exist.
  const codes = [declCode, hbCode, monCode, armCode];
  const code = codes.includes(1) ? 1 : Math.max(...codes);
  return { code, markers: [...declMarkers, ...hbMarkers, ...monMarkers, ...armMarkers, ...inventory] };
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

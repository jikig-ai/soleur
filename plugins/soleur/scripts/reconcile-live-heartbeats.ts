#!/usr/bin/env bun
// CLI wrapper for the source-vs-live Better Stack heartbeat reconcile (#6549 item 2).
//
// Reads the live payload from Better Stack, reconciles it against the executable MANIFEST +
// discovered `.tf` blocks (pure logic in ../lib/heartbeat-live-reconcile.ts), prints structured
// `SOLEUR_HEARTBEAT_RECONCILE_*` markers to stdout, and exits with a tri-state contract that the
// drift workflow branches on. It only READS `GET /api/v2/heartbeats`; it never unpauses anything.
//
// Better Stack API contract (verified against canonical in-repo usage
// apply-web-platform-infra.yml:1947-1953 — the vendor doc pages 404'd on the deepen pass):
//   GET https://uptime.betterstack.com/api/v2/heartbeats
//   Authorization: Bearer <BETTERSTACK_API_TOKEN>
//   200 -> { data: [ { attributes: { name, status, paused } } ], pagination: { next: <url|null> } }
// <!-- verified: 2026-07-17 source: apps/web-platform/.github ../apply-web-platform-infra.yml:1950 -->
//
// Exit contract (D3):
//   0  OK           — all in-scope heartbeats reconcile               SOLEUR_HEARTBEAT_RECONCILE_OK
//   0  UNREACHABLE  — Better Stack 5xx/429/timeout after retries      SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE
//   2  MISMATCH     — condition (a) and/or (b)                        SOLEUR_HEARTBEAT_RECONCILE_MISMATCH ...
//   1  ERROR        — auth (401/403) / token absent / malformed body  SOLEUR_HEARTBEAT_RECONCILE_ERROR ...

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { MANIFEST, type ManifestEntry } from "../lib/heartbeat-manifest";
import {
  type DiscoveredHeartbeat,
  type LiveHeartbeat,
  parseHeartbeatBlocks,
  reconcileHeartbeats,
} from "../lib/heartbeat-live-reconcile";

const HEARTBEATS_HOST = "uptime.betterstack.com";
const HEARTBEATS_URL = `https://${HEARTBEATS_HOST}/api/v2/heartbeats`;

/**
 * Only ever attach the Bearer token to the trusted Better Stack host over HTTPS. `pagination.next`
 * comes from the RESPONSE BODY, so a MITM or a malicious/compromised response could point it at an
 * attacker host to exfiltrate the token — pin it (SSRF / credential-exfiltration guard).
 */
function isAllowedHeartbeatsUrl(u: string): boolean {
  try {
    const parsed = new URL(u);
    return parsed.protocol === "https:" && parsed.hostname === HEARTBEATS_HOST;
  } catch {
    return false;
  }
}

export type FetchResult =
  | { ok: true; live: LiveHeartbeat[] }
  | { ok: false; kind: "unreachable" | "auth" | "error"; detail?: string };

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

/**
 * Fetch every live heartbeat (following `pagination.next`) with depth-bounded retry.
 *
 * - transient (5xx / 429 / thrown network/abort error): retry up to `maxAttempts` with exponential
 *   backoff (1s/2s/4s); exhausted -> `unreachable` (the caller must NOT page — Sentry stays ok).
 * - auth (401/403): NOT transient -> `auth` immediately, no retry.
 * - other non-2xx or a malformed 200 body: `error`.
 *
 * Network is injected (`fetchImpl`/`sleepImpl`) so the retry/auth/pagination branches are unit-
 * testable without a token or the live API.
 */
export async function fetchLiveHeartbeats(opts: FetchOptions): Promise<FetchResult> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleepImpl = opts.sleepImpl ?? defaultSleep;
  const maxAttempts = opts.maxAttempts ?? 3;
  const timeoutMs = opts.timeoutMs ?? 10_000;

  const live: LiveHeartbeat[] = [];
  let url: string | null = HEARTBEATS_URL;

  while (url) {
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
          // host-pinned by `isAllowedHeartbeatsUrl`), never via HTTP redirects.
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
        const attrs = (row as { attributes?: { name?: unknown; paused?: unknown } })?.attributes;
        if (attrs && typeof attrs.name === "string") {
          live.push({ name: attrs.name, paused: attrs.paused === true });
        }
      }
      const next = (body as { pagination?: { next?: unknown } })?.pagination?.next;
      if (typeof next === "string" && next.length > 0) {
        if (!isAllowedHeartbeatsUrl(next)) {
          // Fail loud rather than either following the token off-host OR silently reconciling
          // against a truncated payload (which would false-OK a real mismatch).
          let host = "unparseable";
          try {
            host = new URL(next).host;
          } catch {
            /* keep placeholder */
          }
          return { ok: false, kind: "error", detail: `refusing off-host pagination.next (${host})` };
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

/** Read every `.tf` file in an infra directory and parse all heartbeat blocks. */
export function discoverHeartbeatsFromInfra(infraDir: string): DiscoveredHeartbeat[] {
  const discovered: DiscoveredHeartbeat[] = [];
  for (const file of readdirSync(infraDir)) {
    if (!file.endsWith(".tf")) continue;
    const text = readFileSync(join(infraDir, file), "utf8");
    if (!text.includes("betteruptime_heartbeat")) continue;
    discovered.push(...parseHeartbeatBlocks(text));
  }
  return discovered;
}

/**
 * Sanitize a marker line: strip CR/LF (so it can never inject a GitHub Actions `::annotation::`) and
 * backticks (so a heartbeat name can never break out of the ``` code fence in the auto-filed issue
 * body — defense-in-depth; the names are our own `.tf` `name =` literals, not raw API data).
 */
const oneLine = (s: string) => s.replace(/[\r\n`]+/g, " ");

interface RunResult {
  code: number;
  markers: string[];
}

export async function runReconcile(
  infraDir: string,
  opts: FetchOptions,
  manifest: readonly Pick<ManifestEntry, "name" | "feeder" | "arming_pending">[] = MANIFEST,
): Promise<RunResult> {
  if (!opts.token) {
    return {
      code: 1,
      markers: ["SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=token-absent"],
    };
  }

  const discovered = discoverHeartbeatsFromInfra(infraDir);
  const result = await fetchLiveHeartbeats(opts);

  if (!result.ok) {
    if (result.kind === "unreachable") {
      return {
        code: 0,
        markers: [oneLine(`SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE detail=${result.detail ?? "n/a"}`)],
      };
    }
    // auth or malformed -> hard error (exit 1)
    return {
      code: 1,
      markers: [oneLine(`SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=${result.kind} detail=${result.detail ?? "n/a"}`)],
    };
  }

  const violations = reconcileHeartbeats(manifest, discovered, result.live);
  if (violations.length === 0) {
    return {
      code: 0,
      markers: [`SOLEUR_HEARTBEAT_RECONCILE_OK checked=${discovered.length} live=${result.live.length}`],
    };
  }
  return {
    code: 2,
    markers: violations.map((v) =>
      oneLine(`SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=${v.liveName} live=${v.live} reason=${v.reason}`),
    ),
  };
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
      console.log(`SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=uncaught detail=${oneLine(String(err?.message ?? err))}`);
      process.exit(1);
    });
}

// scripts/live-verify/perf-probe.ts
//
// Committed authenticated perf probe (#8978 Phase 0.4). Reproduces the issue's
// ad-hoc cold/warm dashboard measurements reproducibly:
//   - document TTFB + FCP/LCP paint entries per navigation
//   - per-response Server-Timing (mw-auth / mw-revoke / mw-tc) on documents AND
//     /api/* fetches
//   - per-/api/* request wall-time waterfall
// Every request carries `x-perf-probe: 1` so sentry.server.config.ts's
// tracesSampler arms 1.0 server-side tracing for exactly these requests.
// The client-side sampler cannot see request headers, so each context also
// arms `localStorage["soleur.perf-probe"]=1` via addInitScript (#9178).
//
// Runner: `doppler run -c prd -- bun run scripts/live-verify/perf-probe.ts` —
// same env contract as run.ts (PRODUCTION_URL, NEXT_PUBLIC_SUPABASE_URL/
// ANON_KEY, LIVE_VERIFY_USER_PASSWORD / _EXPECTED_UID / _EXPECTED_REF,
// optional LIVE_VERIFY_BROWSER_CHANNEL / _BROWSER_PATH,
// PERF_PROBE_COLD_SAMPLES default 5, clamped to 25). Read-only by
// construction: the
// probe drives navigations only — no writes land, so teardown is session
// destruction (I-ephemerality) and nothing else. The allowlist invariants are
// reused verbatim from run.ts: bindProject BEFORE sign-in, verifyPrincipal
// (uid + email) BEFORE any launch.

import { chromium, type Browser, type Page } from "@playwright/test";

import {
  bindProject,
  buildInjectedCookies,
  buildLaunchOptions,
  makeJar,
  mintSession,
  readConfig,
  verifyPrincipal,
  type Config,
  type VerifiedPrincipal,
} from "./run";
import { redact } from "./redact";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface RequestSample {
  /** Pathname only — query strings can carry tokens. */
  path: string;
  /** Uppercase HTTP method — the duplicates census keys on method+path. */
  method: string;
  kind: "document" | "api" | "other";
  status: number;
  /** Wall time requestStart→responseEnd (ms). */
  durationMs: number;
  /** Time to first response byte (ms), when the browser reports it. */
  ttfbMs: number | null;
  /** Raw Server-Timing header value, when the server emitted one. */
  serverTiming: string | null;
}

export interface DuplicateCount {
  /** `${method} ${safePath}` — one GET key repeated within a navigation. */
  key: string;
  count: number;
}

export interface NavSample {
  label: string; // e.g. "cold-1", "warm-sw"
  docTtfbMs: number | null;
  docServerTiming: string | null;
  fcpMs: number | null;
  lcpMs: number | null;
  /** Unitless layout-shift score (NOT ms); null when the observer can't run. */
  cls: number | null;
  domContentLoadedMs: number | null;
  /** Same-mount GET keys observed >1 in THIS navigation (#8985 census). */
  duplicates: DuplicateCount[];
  requests: RequestSample[];
}

export interface ProbeSummary {
  samples: NavSample[];
  coldApi: { path: string; p50: number; p95: number; n: number }[];
  /** Per-key rollup of every sample's duplicates (empty = P1 met). */
  duplicates: { key: string; max: number; samples: string[] }[];
}

// Paths the probe may legitimately emit verbatim. Anything else is reduced to
// its first segment — a full path can carry a token (/shared/<t>, /invite/<t>).
// `<>` is allowed in the api arm only for the `<id>` substitution this file
// itself writes (UUID_TAIL_RE runs before this test).
const EMIT_PATH_RE = /^\/(?:dashboard(?:\/chat(?:\/new|\/(?:<id>|[0-9a-f-]{36}))?)?|api\/[a-z0-9\-_/<>]+|login|accept-terms|health)$/;
const UUID_TAIL_RE = /[0-9a-f]{8}-[0-9a-f-]{27}/g;

/** Reduce a request URL to an emit-safe path (token-bearing segments stripped). */
export function safePath(rawUrl: string): string {
  let pathname: string;
  try {
    pathname = new URL(rawUrl).pathname;
  } catch {
    return "<unparsable>";
  }
  pathname = pathname.replace(UUID_TAIL_RE, "<id>");
  if (EMIT_PATH_RE.test(pathname)) return pathname;
  // A single-segment path IS the thing the reduction exists to hide
  // (e.g. /TOKEN) — emit no segment at all for it.
  const first = pathname.split("/")[1] ?? "";
  if (!first || !pathname.slice(1).includes("/")) return "<reduced>";
  return `<reduced:/${first}>`;
}

/** Classify a request as document / api / other for the waterfall buckets. */
export function classifyRequest(url: string, resourceType: string): RequestSample["kind"] {
  if (resourceType === "document") return "document";
  try {
    if (new URL(url).pathname.startsWith("/api/")) return "api";
  } catch {
    // unparsable → other
  }
  return "other";
}

const NAV_PATH = "/dashboard";
// The first paint of an auth-gated route under a cold session can sit inside
// the measured 8–15s window; give the paint wait headroom, not the AC's target.
const NAV_TIMEOUT_MS = 60_000;
const PAINT_SETTLE_MS = 4_000;
// Renderer round-trips are bounded: a wedged page must degrade to null fields,
// never hang the probe without a RESULT line (the run.ts #7969/#8092 class).
const EVAL_BUDGET_MS = 15_000;

/**
 * Extract wall/TTFB from Playwright's `request.timing()`. EVERY field except
 * `startTime` is RELATIVE to startTime (startTime itself is epoch ms), and
 * unavailable fields read -1 — not zero. Exported + pure so the unit suite
 * pins the unit convention (PR #8984 review: the relative-vs-epoch mix-up
 * made the waterfall silently empty).
 */
export function durationsFromTiming(t: {
  responseStart: number;
  responseEnd: number;
}): { durationMs: number; ttfbMs: number | null } {
  return {
    durationMs: t.responseEnd >= 0 ? t.responseEnd : -1,
    ttfbMs: t.responseStart >= 0 ? t.responseStart : null,
  };
}

/** Race a renderer call against a bounded fallback — never hangs. */
async function bounded<T>(fn: () => Promise<T>, fallback: T): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      fn(),
      new Promise<T>((resolve) => {
        timer = setTimeout(() => resolve(fallback), EVAL_BUDGET_MS);
      }),
    ]);
  } catch {
    return fallback;
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

/**
 * Arm `x-perf-probe: 1` on requests to the prod origin ONLY. A context-wide
 * `extraHTTPHeaders` would also stamp the header on cross-origin legs
 * (supabase REST/realtime), forcing CORS preflights that skew the very
 * waterfall this probe measures (PR #8984 review).
 */
async function armProbeHeader(
  context: import("@playwright/test").BrowserContext,
  prodOrigin: string,
): Promise<void> {
  const base = new URL(prodOrigin).origin;
  await context.route(`${base}/**`, (route) =>
    route.continue({
      headers: { ...route.request().headers(), "x-perf-probe": "1" },
    }),
  );
}

/**
 * Arm the CLIENT-side probe marker. sentry.client.config.ts's tracesSampler
 * cannot see request headers, so it reads `localStorage["soleur.perf-probe"]`
 * instead (#9178) — addInitScript runs before any page script on every
 * navigation. localStorage is origin-scoped, so only the prod origin's own
 * sampler observes it; the try/catch swallows opaque-origin storage throws.
 */
async function armProbeMarker(
  context: import("@playwright/test").BrowserContext,
): Promise<void> {
  await context.addInitScript(() => {
    try {
      localStorage.setItem("soleur.perf-probe", "1");
    } catch {
      // about:blank & other opaque origins deny storage — harmless.
    }
  });
}

// ---------------------------------------------------------------------------
// Probe driver
// ---------------------------------------------------------------------------

async function captureNavigation(
  page: Page,
  url: string,
  label: string,
): Promise<NavSample> {
  const requests: RequestSample[] = [];
  const captures: Promise<unknown>[] = [];

  // Capture at requestfinished, not response: responseEnd/responseStart are
  // only populated once the body completes — at the `response` event they
  // read -1 and the waterfall lands empty (PR #8984 review).
  page.on("requestfinished", (req) => {
    captures.push(
      (async () => {
        const resp = await req.response();
        let durationMs = -1;
        let ttfbMs: number | null = null;
        try {
          ({ durationMs, ttfbMs } = durationsFromTiming(req.timing()));
        } catch {
          // timing() can throw on aborted/failed requests — keep duration -1.
        }
        requests.push({
          path: safePath(req.url()),
          method: req.method(),
          kind: classifyRequest(req.url(), req.resourceType()),
          status: resp?.status() ?? 0,
          durationMs,
          ttfbMs,
          serverTiming: resp?.headers()["server-timing"] ?? null,
        });
      })(),
    );
  });
  // Failed legs land in the waterfall too — a request that never completes
  // is often the interesting one in a cold-load incident (status 0).
  page.on("requestfailed", (req) => {
    let durationMs = -1;
    try {
      ({ durationMs } = durationsFromTiming(req.timing()));
    } catch {
      // timing() can throw on aborted/failed requests — keep duration -1.
    }
    requests.push({
      path: safePath(req.url()),
      method: req.method(),
      kind: classifyRequest(req.url(), req.resourceType()),
      status: 0,
      durationMs,
      ttfbMs: null,
      serverTiming: null,
    });
  });

  const nav = await page.goto(url, {
    waitUntil: "domcontentloaded",
    timeout: NAV_TIMEOUT_MS,
  });

  // Let the mount fan-out and paint entries land before sampling.
  await page.waitForLoadState("load", { timeout: NAV_TIMEOUT_MS }).catch(() => undefined);
  await page.waitForTimeout(PAINT_SETTLE_MS);

  // Settle in-flight response listeners so the waterfall is complete —
  // bounded: a streaming/long-lived leg must not hang the probe.
  await bounded(() => Promise.allSettled(captures), undefined);

  const paint = await bounded<{
    fcp: number | null;
    lcp: number | null;
    cls: number | null;
    domContentLoaded: number | null;
    ttfb: number | null;
  }>(
    () =>
      page.evaluate(() => {
      // startTime/responseStart here are ms since timeOrigin — the DOM
      // convention, distinct from req.timing()'s epoch+relative mix pinned
      // in durationsFromTiming.
      const paints = Object.fromEntries(
        performance
          .getEntriesByType("paint")
          .map((e) => [e.name, e.startTime]),
      );
      const nav = performance.getEntriesByType("navigation")[0] as
        | PerformanceNavigationTiming
        | undefined;
      // LCP is observer-only (not in getEntriesByType); a buffered observer
      // replays entries that already painted.
      const lcpPromise = new Promise<number | null>((resolve) => {
        try {
          const po = new PerformanceObserver((list) => {
            const entries = list.getEntries();
            resolve(
              entries.length > 0 ? entries[entries.length - 1].startTime : null,
            );
          });
          po.observe({ type: "largest-contentful-paint", buffered: true });
          setTimeout(() => resolve(null), 1_000);
        } catch {
          resolve(null);
        }
      });
      // CLS is observer-only too, and `value` is a UNITLESS score (not ms):
      // sum layout-shift entries without recent input. Buffered replay can
      // deliver several callbacks, so settle before reporting.
      const clsPromise = new Promise<number | null>((resolve) => {
        try {
          let cls = 0;
          const po = new PerformanceObserver((list) => {
            for (const e of list.getEntries()) {
              const shift = e as PerformanceEntry & {
                value?: number;
                hadRecentInput?: boolean;
              };
              if (typeof shift.value === "number" && !shift.hadRecentInput) {
                cls += shift.value;
              }
            }
          });
          po.observe({ type: "layout-shift", buffered: true });
          setTimeout(() => resolve(cls), 1_000);
        } catch {
          resolve(null);
        }
      });
        return Promise.all([lcpPromise, clsPromise]).then(([lcp, cls]) => ({
          fcp: paints["first-contentful-paint"] ?? null,
          lcp,
          cls,
          domContentLoaded: nav?.domContentLoadedEventEnd ?? null,
          ttfb: nav?.responseStart ?? null,
        }));
      }),
    { fcp: null, lcp: null, cls: null, domContentLoaded: null, ttfb: null },
  );

  const kept = requests.filter(
    (r) => r.kind !== "other" || r.serverTiming !== null,
  );
  return {
    label,
    docTtfbMs: paint.ttfb,
    docServerTiming: nav ? (await nav.headerValue("server-timing")) ?? null : null,
    fcpMs: paint.fcp,
    lcpMs: paint.lcp,
    cls: paint.cls,
    domContentLoadedMs: paint.domContentLoaded,
    duplicates: countDuplicateGets(kept),
    requests: kept,
  };
}

function quantile(sorted: number[], q: number): number {
  if (sorted.length === 0) return -1;
  const idx = Math.min(sorted.length - 1, Math.floor(q * sorted.length));
  return sorted[idx];
}

/** Aggregate the cold-pass /api/* legs into a p50/p95 table (pure; testable). */
export function summarizeColdApi(samples: NavSample[]): ProbeSummary["coldApi"] {
  const byPath = new Map<string, number[]>();
  for (const s of samples) {
    for (const r of s.requests) {
      if (r.kind !== "api" || r.durationMs < 0) continue;
      const arr = byPath.get(r.path) ?? [];
      arr.push(r.durationMs);
      byPath.set(r.path, arr);
    }
  }
  return Array.from(byPath.entries())
    .map(([path, durs]) => {
      const sorted = [...durs].sort((a, b) => a - b);
      return { path, p50: quantile(sorted, 0.5), p95: quantile(sorted, 0.95), n: sorted.length };
    })
    .sort((a, b) => b.p95 - a.p95);
}

/**
 * Same-mount duplicate census (#8985): count GETs keyed on method+safePath
 * within ONE navigation's request list and report keys observed >1. Pure +
 * exported so the unit suite pins it — the "duplicates empty" AC reads this.
 */
export function countDuplicateGets(
  requests: RequestSample[],
): DuplicateCount[] {
  const byKey = new Map<string, number>();
  for (const r of requests) {
    if (r.method !== "GET") continue;
    const key = `${r.method} ${r.path}`;
    byKey.set(key, (byKey.get(key) ?? 0) + 1);
  }
  return Array.from(byKey.entries())
    .filter(([, n]) => n > 1)
    .map(([key, count]) => ({ key, count }))
    .sort((a, b) => b.count - a.count || a.key.localeCompare(b.key));
}

/** Roll per-sample duplicates into a worst-count + sample-label table. */
export function summarizeDuplicates(
  samples: NavSample[],
): ProbeSummary["duplicates"] {
  const byKey = new Map<string, { max: number; samples: string[] }>();
  for (const s of samples) {
    for (const d of s.duplicates) {
      const cur = byKey.get(d.key) ?? { max: 0, samples: [] };
      cur.max = Math.max(cur.max, d.count);
      cur.samples.push(s.label);
      byKey.set(d.key, cur);
    }
  }
  return Array.from(byKey.entries())
    .map(([key, v]) => ({ key, max: v.max, samples: v.samples }))
    .sort((a, b) => b.max - a.max || a.key.localeCompare(b.key));
}

// The probe is read-only: it cannot produce a FAIL verdict, only a measured
// PASS or a CANT-RUN. The narrower union keeps `outcome.summary` reachable.
type ProbeOutcome =
  | { kind: "PASS"; summary: ProbeSummary }
  | { kind: "CANT-RUN"; reason: string };

async function drive(
  // `verified` is intentionally unread: its brand makes the browser launch
  // unreachable without verifyPrincipal — a call-ordering gate, not data.
  verified: VerifiedPrincipal,
  cfg: Config,
  jar: ReturnType<typeof makeJar>,
): Promise<ProbeOutcome> {
  void verified;
  const prodHost = new URL(cfg.productionUrl).hostname;
  const coldSamples = Math.min(
    25,
    Math.max(
      1,
      Number.parseInt(process.env.PERF_PROBE_COLD_SAMPLES ?? "5", 10) || 5,
    ),
  );

  let browser: Browser | null = null;
  try {
    browser = await chromium.launch(
      buildLaunchOptions({
        channel: cfg.browserChannel,
        executablePath: cfg.browserPath,
      }),
    );
  } catch (err) {
    return { kind: "CANT-RUN", reason: `browser-launch:${(err as Error).name}` };
  }

  const samples: NavSample[] = [];
  try {
    // Cold passes: a fresh context per sample — no service worker has ever
    // registered in it, so the navigation is pre-SW (the issue's cold shape).
    for (let i = 0; i < coldSamples; i++) {
      const context = await browser.newContext({ serviceWorkers: "allow" });
      await armProbeHeader(context, cfg.productionUrl);
      await armProbeMarker(context);
      await context.addCookies(buildInjectedCookies(jar.cookies.entries(), prodHost));
      const page = await context.newPage();
      samples.push(
        await captureNavigation(page, `${cfg.productionUrl}${NAV_PATH}`, `cold-${i + 1}`),
      );
      await context.close();
    }

    // Warm pass: one context, two navigations. Nav A registers + activates the
    // service worker; nav B is SW-controlled (the dominant real-session shape).
    const warmContext = await browser.newContext({ serviceWorkers: "allow" });
    await armProbeHeader(warmContext, cfg.productionUrl);
    await armProbeMarker(warmContext);
    await warmContext.addCookies(buildInjectedCookies(jar.cookies.entries(), prodHost));
    const warmPage = await warmContext.newPage();
    await warmPage.goto(`${cfg.productionUrl}${NAV_PATH}`, {
      waitUntil: "load",
      timeout: NAV_TIMEOUT_MS,
    });
    // Wait for SW control — bounded so an absent/failed registration degrades
    // to a second cold sample rather than a hang.
    await bounded(
      () =>
        warmPage.evaluate(() =>
          Promise.race([
            navigator.serviceWorker.ready.then(() => "ready"),
            new Promise<string>((r) => setTimeout(() => r("timeout"), 15_000)),
          ]),
        ),
      "unreadable",
    );
    samples.push(
      await captureNavigation(warmPage, `${cfg.productionUrl}${NAV_PATH}`, "warm-sw"),
    );
    await warmContext.close();

    return {
      kind: "PASS",
      summary: {
        samples,
        coldApi: summarizeColdApi(samples.filter((s) => s.label.startsWith("cold-"))),
        duplicates: summarizeDuplicates(samples),
      },
    };
  } catch (err) {
    return {
      kind: "CANT-RUN",
      reason: `drive:${(err as Error).name}:${redact((err as Error).message).slice(0, 120)}`,
    };
  } finally {
    if (browser) await browser.close();
  }
}

// ---------------------------------------------------------------------------
// Orchestrator
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  let cfg: Config;
  try {
    cfg = readConfig();
  } catch (err) {
    console.log(`RESULT: CANT-RUN:CONFIG:${redact((err as Error).message)}`);
    process.exitCode = 1;
    return;
  }

  const jar = makeJar();
  let supabase: Awaited<ReturnType<typeof mintSession>> | null = null;
  try {
    bindProject(cfg);
    supabase = await mintSession(cfg, jar);
    const verified = await verifyPrincipal(supabase, cfg);

    const outcome = await drive(verified, cfg, jar);

    if (outcome.kind === "PASS") {
      // Redacted summary: every string field passed through redact() so a
      // captured value (cookie fragment, token-shaped path) cannot reach the
      // log. Paths are already allowlist-reduced at capture time.
      const json = JSON.stringify(outcome.summary);
      console.log(`PERF_JSON:${redact(json)}`);
      console.log("RESULT: PASS — perf probe captured cold+warm dashboard measurements");
    } else {
      console.log(`RESULT: CANT-RUN:${redact(outcome.reason)}`);
      // CANT-RUN and FAIL both exit non-zero: neither produced a measurement.
      process.exitCode = 1;
    }
  } catch (err) {
    console.log(`RESULT: CANT-RUN:${redact((err as Error).message)}`);
    process.exitCode = 1;
  } finally {
    // Session destruction on EVERY arm — a mintSession/verifyPrincipal/drive
    // throw must not leave the live-verify principal's refresh token live.
    if (supabase) await supabase.auth.signOut().catch(() => undefined);
    jar.cookies.clear();
  }
}

if ((import.meta as { main?: boolean }).main) {
  void main();
}

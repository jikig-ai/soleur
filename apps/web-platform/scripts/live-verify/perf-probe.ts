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
//
// Runner: `bun run scripts/live-verify/perf-probe.ts` — same env contract as
// run.ts (PRODUCTION_URL, NEXT_PUBLIC_SUPABASE_URL/ANON_KEY,
// LIVE_VERIFY_USER_PASSWORD / _EXPECTED_UID / _EXPECTED_REF, optional
// LIVE_VERIFY_BROWSER_CHANNEL / _BROWSER_PATH). Read-only by construction: the
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
  kind: "document" | "api" | "other";
  status: number;
  /** Wall time requestStart→responseEnd (ms). */
  durationMs: number;
  /** Time to first response byte (ms), when the browser reports it. */
  ttfbMs: number | null;
  /** Raw Server-Timing header value, when the server emitted one. */
  serverTiming: string | null;
}

export interface NavSample {
  label: string; // e.g. "cold-1", "warm-sw"
  docTtfbMs: number | null;
  docServerTiming: string | null;
  fcpMs: number | null;
  lcpMs: number | null;
  domContentLoadedMs: number | null;
  requests: RequestSample[];
}

export interface ProbeSummary {
  samples: NavSample[];
  coldApi: { path: string; p50: number; p95: number; n: number }[];
}

// Paths the probe may legitimately emit verbatim. Anything else is reduced to
// its first segment — a full path can carry a token (/shared/<t>, /invite/<t>).
// `<>` is allowed in the api arm only for the `<id>` substitution this file
// itself writes (UUID_TAIL_RE runs before this test).
const EMIT_PATH_RE = /^\/(?:dashboard(?:\/chat(?:\/new|\/[0-9a-f-]{36})?)?|api\/[a-z0-9\-_/<>]+|login|accept-terms|health)$/;
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
  return `<reduced:/${pathname.split("/")[1] ?? ""}>`;
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

  page.on("response", (response) => {
    captures.push(
      (async () => {
        const req = response.request();
        const path = safePath(req.url());
        const kind = classifyRequest(req.url(), req.resourceType());
        let durationMs = -1;
        let ttfbMs: number | null = null;
        try {
          const t = await req.timing();
          // timing() reports zeroed fields for requests the browser didn't
          // time (e.g. SW-served or pre-renderer) — a real responseEnd strictly
          // after startTime is the validity test; zeros would misreport as a
          // 0ms request instead of "unknown".
          if (t && t.responseEnd > t.startTime) {
            durationMs = t.responseEnd - t.startTime;
            ttfbMs =
              t.responseStart > t.startTime
                ? t.responseStart - t.startTime
                : null;
          }
        } catch {
          // timing() can throw on aborted/failed requests — keep duration -1.
        }
        requests.push({
          path,
          kind,
          status: response.status(),
          durationMs,
          ttfbMs,
          serverTiming: response.headers()["server-timing"] ?? null,
        });
      })(),
    );
  });

  const nav = await page.goto(url, {
    waitUntil: "domcontentloaded",
    timeout: NAV_TIMEOUT_MS,
  });

  // Let the mount fan-out and paint entries land before sampling.
  await page.waitForLoadState("load", { timeout: NAV_TIMEOUT_MS }).catch(() => undefined);
  await page.waitForTimeout(PAINT_SETTLE_MS);

  // Settle in-flight response listeners so the waterfall is complete.
  await Promise.allSettled(captures);

  const paint = await page
    .evaluate(() => {
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
      return lcpPromise.then((lcp) => ({
        fcp: paints["first-contentful-paint"] ?? null,
        lcp,
        domContentLoaded: nav?.domContentLoadedEventEnd ?? null,
        ttfb: nav?.responseStart ?? null,
      }));
    })
    .catch(() => ({ fcp: null, lcp: null, domContentLoaded: null, ttfb: null }));

  return {
    label,
    docTtfbMs: paint.ttfb,
    docServerTiming: nav ? (await nav.headerValue("server-timing")) ?? null : null,
    fcpMs: paint.fcp,
    lcpMs: paint.lcp,
    domContentLoadedMs: paint.domContentLoaded,
    requests: requests.filter((r) => r.kind !== "other" || r.serverTiming !== null),
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

// The probe is read-only: it cannot produce a FAIL verdict, only a measured
// PASS or a CANT-RUN. The narrower union keeps `outcome.summary` reachable.
type ProbeOutcome =
  | { kind: "PASS"; summary: ProbeSummary }
  | { kind: "CANT-RUN"; reason: string };

async function drive(
  verified: VerifiedPrincipal,
  cfg: Config,
  jar: ReturnType<typeof makeJar>,
): Promise<ProbeOutcome> {
  const prodHost = new URL(cfg.productionUrl).hostname;
  const coldSamples = Math.max(
    1,
    Number.parseInt(process.env.PERF_PROBE_COLD_SAMPLES ?? "5", 10) || 5,
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
      const context = await browser.newContext({
        extraHTTPHeaders: { "x-perf-probe": "1" },
        serviceWorkers: "allow",
      });
      await context.addCookies(buildInjectedCookies(jar.cookies.entries(), prodHost));
      const page = await context.newPage();
      samples.push(
        await captureNavigation(page, `${cfg.productionUrl}${NAV_PATH}`, `cold-${i + 1}`),
      );
      await context.close();
    }

    // Warm pass: one context, two navigations. Nav A registers + activates the
    // service worker; nav B is SW-controlled (the dominant real-session shape).
    const warmContext = await browser.newContext({
      extraHTTPHeaders: { "x-perf-probe": "1" },
      serviceWorkers: "allow",
    });
    await warmContext.addCookies(buildInjectedCookies(jar.cookies.entries(), prodHost));
    const warmPage = await warmContext.newPage();
    await warmPage.goto(`${cfg.productionUrl}${NAV_PATH}`, {
      waitUntil: "load",
      timeout: NAV_TIMEOUT_MS,
    });
    // Wait for SW control — bounded so an absent/failed registration degrades
    // to a second cold sample rather than a hang.
    await warmPage
      .evaluate(() =>
        Promise.race([
          navigator.serviceWorker.ready.then(() => "ready"),
          new Promise<string>((r) => setTimeout(() => r("timeout"), 15_000)),
        ]),
      )
      .catch(() => "unreadable");
    samples.push(
      await captureNavigation(warmPage, `${cfg.productionUrl}${NAV_PATH}`, "warm-sw"),
    );
    await warmContext.close();

    return {
      kind: "PASS",
      summary: { samples, coldApi: summarizeColdApi(samples.filter((s) => s.label.startsWith("cold-"))) },
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
    console.log(`RESULT: CANT-RUN:CONFIG:${(err as Error).message}`);
    process.exitCode = 1;
    return;
  }

  const jar = makeJar();
  try {
    bindProject(cfg);
    const supabase = await mintSession(cfg, jar);
    const verified = await verifyPrincipal(supabase, cfg);

    const outcome = await drive(verified, cfg, jar);
    await supabase.auth.signOut().catch(() => undefined);

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
    jar.cookies.clear();
  }
}

if ((import.meta as { main?: boolean }).main) {
  void main();
}

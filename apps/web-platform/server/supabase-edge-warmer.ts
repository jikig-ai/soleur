// supabase-edge-warmer.ts — periodic cheap request to the Supabase edge so
// the undici/TLS pool and PostgREST compute stay warm between real requests
// (#8978 residual cold tiers).
//
// Why this exists: the Phase-0 probe + Sentry span pull measured 20–38 s
// stalls on individual outbound PostgREST/auth calls after idle — cold
// TCP+TLS + PostgREST warm-up, not query time (the queries are indexed
// one-row selects). A fixed-cadence `GET /rest/v1/` with the anon key
// exercises the same edge path a real request pays, amortizing the cold
// start OFF the request path.
//
// Caveat recorded in the plan: middleware runs on a Next-managed fetch
// dispatcher that MAY be a separate undici pool from this Node-path fetch —
// the warmer provably warms the render/API-path dispatcher; whether it also
// warms the middleware isolate is unproven. The per-leg AbortSignal bounds
// (middleware.ts) cap the damage either way.
//
// Failure-tolerant by contract: a tick failure logs a warn and never throws
// (a dead warmer must not crash the server — the AC fixture asserts this).

import { createChildLogger } from "./logger";

const log = createChildLogger("supabase-edge-warmer");

// ~18 s cadence: inside Supabase's observed idle-to-cold window (stalls
// recur across minutes, not seconds) and cheap enough to keep both the
// undici pool and PostgREST compute warm continuously.
const WARM_INTERVAL_MS = 18_000;
// A warmer tick that itself stalls must not pile up — bounded like the
// request-path legs.
const WARM_TICK_TIMEOUT_MS = 10_000;
// Heartbeat every ~6 min (20 ticks): the emitted tick line IS the liveness
// signal — its absence in the log stream is the detection (plan
// §Observability failure_modes).
const HEARTBEAT_EVERY_N_TICKS = 20;

export interface EdgeWarmerOptions {
  /** Injectable for tests — defaults to global fetch. */
  fetchImpl?: typeof fetch;
  /** Injectable for tests — defaults to setInterval/clearInterval. */
  setIntervalImpl?: typeof setInterval;
  intervalMs?: number;
  tickTimeoutMs?: number;
}

/**
 * One warm-up tick: GET the PostgREST root with the anon key. Returns the
 * observed duration in ms, or null when the tick failed (network abort,
 * timeout, non-2xx is still a warm path — only a THROW counts as failure).
 * Exported for direct fixture invocation.
 */
export async function supabaseEdgeWarmerTick(
  supabaseUrl: string,
  anonKey: string,
  tickTimeoutMs = WARM_TICK_TIMEOUT_MS,
  fetchImpl: typeof fetch = fetch,
): Promise<number | null> {
  const start = performance.now();
  try {
    // GET /rest/v1/ serves the PostgREST OpenAPI root — the cheapest request
    // that exercises edge routing + compute. The anon key authenticates the
    // edge path exactly as a real request does; no user data is touched.
    const res = await fetchImpl(`${supabaseUrl}/rest/v1/`, {
      headers: { apikey: anonKey },
      signal: AbortSignal.timeout(tickTimeoutMs),
    });
    // Consume the body: an unconsumed body pins the socket in undici (out of
    // the pool until GC), which would make every tick pay a fresh TCP+TLS —
    // churn instead of the warmth this mechanism exists to amortize.
    await res.arrayBuffer();
    return performance.now() - start;
  } catch (err) {
    // The tick promise must NEVER reject — a throwing logger would produce
    // an unhandled rejection under the void-dispatch below. The warn is
    // best-effort; the heartbeat's absence remains the failure signal.
    try {
      log.warn(
        { err, op: "supabase_edge_warmer.tick_failed" },
        "supabase edge warm-up tick failed",
      );
    } catch {
      // logging failure — swallowed per the never-throw contract
    }
    return null;
  }
}

/**
 * Start the periodic warmer. Returns the interval handle (unref'd) so tests
 * can stop it; production callers ignore the return. No-op when env vars are
 * absent (dev without Doppler) — the request path then pays its own cold
 * legs exactly as before.
 */
export function startSupabaseEdgeWarmer(opts: EdgeWarmerOptions = {}) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !anonKey) {
    log.info(
      { op: "supabase_edge_warmer.disabled" },
      "supabase edge warm-up disabled — NEXT_PUBLIC_SUPABASE_* unset",
    );
    return undefined;
  }

  const intervalMs = opts.intervalMs ?? WARM_INTERVAL_MS;
  const tickTimeoutMs = opts.tickTimeoutMs ?? WARM_TICK_TIMEOUT_MS;
  const fetchImpl = opts.fetchImpl ?? fetch;
  const setIntervalImpl = opts.setIntervalImpl ?? setInterval;

  let tickCount = 0;
  const timer = setIntervalImpl(() => {
    // Fire-and-forget; a tick promise never rejects (tick swallows its own
    // errors into a warn log), so no unhandled rejection is possible.
    void supabaseEdgeWarmerTick(
      supabaseUrl,
      anonKey,
      tickTimeoutMs,
      fetchImpl,
    ).then((durMs) => {
      // The continuation must not throw either — a throwing logger inside
      // `.then` would reject the chained promise unobserved (the same
      // never-crash contract the tick body honours).
      try {
        tickCount += 1;
        if (durMs !== null && tickCount % HEARTBEAT_EVERY_N_TICKS === 0) {
          log.info(
            {
              op: "supabase_edge_warmer.tick",
              durMs: Math.round(durMs),
              ticks: tickCount,
            },
            "supabase edge warm-up heartbeat",
          );
        }
      } catch {
        // logging failure — swallowed per the never-throw contract
      }
    });
  }, intervalMs);
  timer.unref();

  log.info(
    { op: "supabase_edge_warmer.armed", intervalMs },
    "supabase edge warm-up armed",
  );
  return timer;
}

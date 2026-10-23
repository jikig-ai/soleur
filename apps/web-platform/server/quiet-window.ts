// #8211 T2 build 1 — the quiet-window control for the git-data cutover rehearsal.
//
// Two halves, one module:
//
//  1. A kill-switch that refuses NEW agent sessions with a maintenance message
//     (`newAgentSessionsRefused`, backed by the runtime flag `new-sessions-paused`).
//     It is consulted ONLY where NEW work starts on a host: cc-dispatcher
//     `dispatchSoleurGo` on a conversation with no live Query, agent-runner
//     `startAgentSession` before its supersede-abort, `POST /api/repo/setup` (a clone
//     writes a working tree) and `triggerHeadlessSync` (the auto-sync agent), plus `POST
//     /api/repo/create` and the first-message check in ws-handler. It never reads or touches
//     a live session, so a refusal cannot drop or corrupt one. Exactly one configured
//     synthetic account (QUIET_WINDOW_EXEMPT_USER_ID, below) passes every gate except
//     auto-sync, which passes no id and so refuses everyone.
//
//  2. A counts-only read of live agent sessions per web host
//     (`startQuietWindowReporter`): one fixed-grammar log line, shipped to Better
//     Stack by Vector, keyed on its `host_name`. web-2 has no SSH ingress, so this
//     line is the only way to read it. The line carries integers and one bit; it
//     never carries a user id, a conversation id, a path or any content.
//
// Fail-open on purpose: an unreadable flag allows sessions (flag ABSENT means
// allowed). The reporter reads the SAME resolution path as the gate, so
// `new_sessions_paused=1` on a host is the proof that host is refusing.

import { isNewAgentSessionsPaused } from "@/lib/feature-flags/server";
import { infoSilentFallback, warnSilentFallback } from "@/server/observability";
import { createChildLogger } from "@/server/logger";

const FEATURE = "quiet-window";

/** Shown to the user whose NEW session was refused. No ids, no internals. */
export const QUIET_WINDOW_MESSAGE =
  "Soleur is in a short maintenance window and is not starting new sessions right now. Your existing work is safe, but this message was not sent. Please try again in a few minutes.";

// #8211 rehearsal (CTO ruling 2026-10-23): ONE named Soleur-owned synthetic account may run its Level 2
// session while the pause is on. The id is a lowercase UUID in Doppler `prd` (not a secret; logged only
// as a hash). Anything malformed (absent, empty, whitespace, uppercase, a list, two ids) exempts nobody.
// That makes a malformed value safe, NOT a wrong one: a well-formed UUID that is not the synthetic
// account exempts whichever account owns it, so the owner verifies the id before setting it (runbook).
// Exact match, no normalisation of the caller's id. The variable is read on each call; the container's
// environment is fixed at its `docker run`, so only a redeploy changes what a host sees.
const EXEMPT_USER_ENV = "QUIET_WINDOW_EXEMPT_USER_ID";
const EXEMPT_USER_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// An exempt pass is mirrored to Sentry at most once per interval with the passes it covers: the gates run
// two or three times per message, and the owner needs "it happened", not a per-message stream.
const EXEMPT_MIRROR_INTERVAL_MS = 60_000;
let lastExemptMirrorAt = 0;
let exemptPassesSinceMirror = 0;
let warnedInvalidExemptConfig = false;

function configuredExemptId(): string | null {
  const raw = process.env[EXEMPT_USER_ENV];
  return typeof raw === "string" && EXEMPT_USER_PATTERN.test(raw) ? raw : null;
}

/**
 * True when the exemption variable holds a well-formed id (the reporter publishes it per host, so the
 * owner can read "loaded" before the window opens). A non-empty value that does not parse warns ONCE
 * per process with its length only: the value could be a pasted secret.
 */
export function exemptionConfigured(): boolean {
  const raw = process.env[EXEMPT_USER_ENV];
  const ok = configuredExemptId() !== null;
  if (!ok && typeof raw === "string" && raw !== "" && !warnedInvalidExemptConfig) {
    warnedInvalidExemptConfig = true;
    warnSilentFallback(null, {
      feature: FEATURE,
      op: "exempt-config-invalid",
      message: "QUIET_WINDOW_EXEMPT_USER_ID is set but is not one lowercase UUID; nobody is exempt",
      extra: { length: raw.length },
    });
  }
  return ok;
}

/**
 * True when a NEW agent session must be refused. Anything other than a strict
 * `true` from the flag read (absent, off, a thrown read) allows the session.
 *
 * `userId` is the caller's raw id: only the one configured exempt account passes while the pause is
 * on. A call without a string `userId` (the reporter's read, auto-sync, a runtime null) is never
 * exempt. An exempt pass is mirrored to Sentry (hashed id, at most once per interval) and is not
 * counted in `refused_since_last`.
 */
export async function newAgentSessionsRefused(
  opts: { observe?: boolean; userId?: string } = {},
): Promise<boolean> {
  try {
    const refused = (await isNewAgentSessionsPaused()) === true;
    const exempt = refused ? configuredExemptId() : null;
    if (exempt !== null && typeof opts.userId === "string" && opts.userId === exempt) {
      if (opts.observe !== true) {
        exemptPassesSinceMirror += 1;
        const now = Date.now();
        if (now - lastExemptMirrorAt >= EXEMPT_MIRROR_INTERVAL_MS) {
          const passes = exemptPassesSinceMirror;
          lastExemptMirrorAt = now;
          exemptPassesSinceMirror = 0;
          infoSilentFallback(null, {
            feature: FEATURE,
            op: "exempt-pass",
            message: "quiet-window: the exempt synthetic account passed the pause",
            extra: { userId: opts.userId, passes },
          });
        }
      }
      return false;
    }
    // Each REAL refusal is counted so the per-minute line proves off-box that the gates fired (the
    // refusal log itself is info level and never leaves the container). The reporter's own read
    // passes observe:true and is not a refusal.
    if (refused && opts.observe !== true) refusedSinceLastEmit += 1;
    return refused;
  } catch (err) {
    warnSilentFallback(err, {
      feature: FEATURE,
      op: "flag-read",
      message: "new-sessions-paused read failed; allowing the session (fail-open)",
    });
    return false;
  }
}

let refusedSinceLastEmit = 0;
let inFlightStarts = 0;

/**
 * Mark an agent-session entry call (dispatch / start / send) as in flight until the returned
 * release function runs. A start that passed the gate before the flip registers its Query only after
 * the workspace resolve, clone and lease, so a count of registered sessions alone can read 0 while a
 * clone is mid-flight (review P2). Held for the WHOLE call, so the figure is an UPPER BOUND on live
 * work: it can over-count a running session (counted again as cc_queries/legacy_sessions) and never
 * under-counts, which is the safe direction for a "live = 0" proof. Idempotent release.
 */
export function trackSessionStart(): () => void {
  inFlightStarts += 1;
  let released = false;
  return () => {
    if (released) return;
    released = true;
    inFlightStarts = Math.max(0, inFlightStarts - 1);
  };
}

export function inFlightStartCount(): number {
  return inFlightStarts;
}

/** Test seam: module-level counters would otherwise leak between cases. */
export function __resetQuietWindowCountersForTests(): void {
  inFlightStarts = 0;
  refusedSinceLastEmit = 0;
  lastExemptMirrorAt = 0;
  exemptPassesSinceMirror = 0;
  warnedInvalidExemptConfig = false;
}

export interface LiveAgentSessionCounts {
  /** Live cc-soleur-go Queries (the Concierge / Command Center path). */
  ccQueries: number;
  /** In-flight legacy-leader sessions (agent-session-registry). */
  legacySessions: number;
  /** Entry calls in flight (passed or about to pass the gate, not yet finished). Optional: 0 if absent. */
  startingSessions?: number;
  /** Real refusals since the previous emit. Optional: 0 if absent. */
  refusedSinceLast?: number;
}

// Capped so no reading can ever render in exponent form ("1e+21"), which would break the closed grammar.
const MAX_REPORTED_COUNT = 1_000_000_000;

function safeCount(n: number): number {
  return Number.isFinite(n) && n > 0 ? Math.min(Math.floor(n), MAX_REPORTED_COUNT) : 0;
}

/**
 * The closed-grammar line the owner (and the evidence collector) reads:
 * `agent_sessions_live=<n> cc_queries=<n> legacy_sessions=<n> starting=<n> new_sessions_paused=<0|1>
 * refused_since_last=<n>`. Integers and one bit only; live = cc + legacy + starting (an upper bound).
 */
export function formatLiveSessionsLine(
  counts: LiveAgentSessionCounts,
  paused: boolean,
): string {
  const cc = safeCount(counts.ccQueries);
  const legacy = safeCount(counts.legacySessions);
  const starting = safeCount(counts.startingSessions ?? 0);
  const refused = safeCount(counts.refusedSinceLast ?? 0);
  return `agent_sessions_live=${cc + legacy + starting} cc_queries=${cc} legacy_sessions=${legacy} starting=${starting} new_sessions_paused=${paused ? 1 : 0} refused_since_last=${refused}`;
}

export const DEFAULT_REPORT_INTERVAL_MS = 60_000;

export interface QuietWindowReporterDeps {
  readCounts: () => LiveAgentSessionCounts;
  intervalMs?: number;
}

async function emitOnce(readCounts: () => LiveAgentSessionCounts): Promise<void> {
  let counts: LiveAgentSessionCounts;
  try {
    counts = readCounts();
  } catch (err) {
    warnSilentFallback(err, {
      feature: FEATURE,
      op: "read-counts",
      message: "live agent-session count read failed; no line emitted",
    });
    return;
  }
  // Same resolution path as the gate (fail-open to false on a throw); observe:true so the read is not
  // counted as a refusal.
  const paused = await newAgentSessionsRefused({ observe: true });
  const withTotals: LiveAgentSessionCounts = {
    ...counts,
    startingSessions: inFlightStarts,
    refusedSinceLast: refusedSinceLastEmit,
  };
  refusedSinceLastEmit = 0;
  counts = withTotals;
  const cc = safeCount(counts.ccQueries);
  const legacy = safeCount(counts.legacySessions);
  const starting = safeCount(counts.startingSessions ?? 0);
  // warn level on purpose: it is the level the git_data_store= readback line
  // ships at, and Vector's host_name field keys the per-host read. The child
  // logger is created here, not at module load, so importing this module for the
  // flag gate alone (the /api/repo/setup route graph) never touches the logger.
  createChildLogger("quiet-window").warn(
    {
      agentSessionsLive: cc + legacy + starting,
      ccQueries: cc,
      legacySessions: legacy,
      startingSessions: starting,
      newSessionsPaused: paused,
      refusedSinceLast: safeCount(counts.refusedSinceLast ?? 0),
      // A boolean, never the id: the owner reads "the exemption loaded on this host" before the window.
      exemptConfigured: exemptionConfigured(),
    },
    formatLiveSessionsLine(counts, paused),
  );
}

/**
 * Emit the live-session line once now and then on an interval. The timer is
 * unref'd and every tick is fenced: observability must never take the process
 * down or block shutdown. Returns the timer so SIGTERM can clear it.
 */
export function startQuietWindowReporter(
  deps: QuietWindowReporterDeps,
): NodeJS.Timeout {
  const tick = () => {
    void emitOnce(deps.readCounts).catch((err) => {
      warnSilentFallback(err, {
        feature: FEATURE,
        op: "emit",
        message: "live agent-session line emit failed",
      });
    });
  };
  tick();
  const timer = setInterval(tick, deps.intervalMs ?? DEFAULT_REPORT_INTERVAL_MS);
  timer.unref();
  return timer;
}

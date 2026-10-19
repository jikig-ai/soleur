// #8211 T2 build 1 — the quiet-window control for the git-data cutover rehearsal.
//
// Two halves, one module:
//
//  1. A kill-switch that refuses NEW agent sessions with a maintenance message
//     (`newAgentSessionsRefused`, backed by the runtime flag `new-sessions-paused`).
//     It is consulted ONLY where NEW work starts on a host: cc-dispatcher
//     `dispatchSoleurGo` on a conversation with no live Query, agent-runner
//     `startAgentSession` before its supersede-abort, `POST /api/repo/setup` (a clone
//     writes a working tree) and `triggerHeadlessSync` (the auto-sync agent). It never
//     reads or touches a live session, so a refusal cannot drop or corrupt one.
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
import { warnSilentFallback } from "@/server/observability";
import { createChildLogger } from "@/server/logger";

const FEATURE = "quiet-window";

/** Shown to the user whose NEW session was refused. No ids, no internals. */
export const QUIET_WINDOW_MESSAGE =
  "Soleur is in a short maintenance window and is not starting new sessions right now. Your existing work is safe. Please try again in a few minutes.";

/**
 * True when a NEW agent session must be refused. Anything other than a strict
 * `true` from the flag read (absent, off, a thrown read) allows the session.
 */
export async function newAgentSessionsRefused(): Promise<boolean> {
  try {
    return (await isNewAgentSessionsPaused()) === true;
  } catch (err) {
    warnSilentFallback(err, {
      feature: FEATURE,
      op: "flag-read",
      message: "new-sessions-paused read failed; allowing the session (fail-open)",
    });
    return false;
  }
}

export interface LiveAgentSessionCounts {
  /** Live cc-soleur-go Queries (the Concierge / Command Center path). */
  ccQueries: number;
  /** In-flight legacy-leader sessions (agent-session-registry). */
  legacySessions: number;
}

function safeCount(n: number): number {
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

/**
 * The closed-grammar line the owner (and the evidence collector) reads:
 * `agent_sessions_live=<n> cc_queries=<n> legacy_sessions=<n> new_sessions_paused=<0|1>`.
 * Integers and one bit only.
 */
export function formatLiveSessionsLine(
  counts: LiveAgentSessionCounts,
  paused: boolean,
): string {
  const cc = safeCount(counts.ccQueries);
  const legacy = safeCount(counts.legacySessions);
  return `agent_sessions_live=${cc + legacy} cc_queries=${cc} legacy_sessions=${legacy} new_sessions_paused=${paused ? 1 : 0}`;
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
  // Same resolution path as the gate (fail-open to false on a throw).
  const paused = await newAgentSessionsRefused();
  const cc = safeCount(counts.ccQueries);
  const legacy = safeCount(counts.legacySessions);
  // warn level on purpose: it is the level the git_data_store= readback line
  // ships at, and Vector's host_name field keys the per-host read. The child
  // logger is created here, not at module load, so importing this module for the
  // flag gate alone (the /api/repo/setup route graph) never touches the logger.
  createChildLogger("quiet-window").warn(
    {
      agentSessionsLive: cc + legacy,
      ccQueries: cc,
      legacySessions: legacy,
      newSessionsPaused: paused,
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

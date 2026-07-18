// routine_run_progress live-state helpers (#5766).
//
// Makes an in-flight HEAVY claude-loop cron a queryable DB fact. The writer lives
// at the instrumentation point (spawnClaudeEval): upsert on entry + heartbeat
// every ~HEARTBEAT_INTERVAL_MS while the child runs. finishRoutineRunProgress is
// called from the run-log middleware transformOutput AFTER the terminal write
// succeeds (arch-A-2), so live-row domain ≡ heartbeat domain by construction (no
// isHeavyCron predicate — only spawnClaudeEval callers ever write a row).
//
// All writes are service-role (getServiceClient bypasses RLS) and FAIL-SOFT: a DB
// error mirrors to Sentry and NEVER throws into the cron handler (mirrors the
// run-log fail-soft contract; cq-silent-fallback-must-mirror-to-sentry).
//
// Attribution-free table (no PII) — see migration 120.

import * as Sentry from "@sentry/nextjs";
import { getServiceClient } from "@/lib/supabase/service";

const TABLE = "routine_run_progress";

// Heartbeat cadence + staleness thresholds (shared with the reader so the four
// states are contiguous — DI-P1-B invariant: STUCK_THRESHOLD_MS < ORPHAN_IGNORE_MS).
//   running:  last_heartbeat_at within STUCK_THRESHOLD_MS
//   stuck:    STUCK_THRESHOLD_MS < staleness ≤ ORPHAN_IGNORE_MS (evicted, reader-computed)
//   ignored:  staleness > ORPHAN_IGNORE_MS (dead orphan; reader drops it, delete-stale reaps it)
// Heavy claude-loop crons run for minutes, so the ignore bound sits well above
// the longest expected run; the heartbeat is emitted every ~60s DURING the run.
// Interval raised 30s→60s (Disk-IO write reduction, 2026-07-18) with
// STUCK_THRESHOLD_MS kept at 3× interval so the missed-beat tolerance is
// unchanged (two missed beats before "stuck").
export const HEARTBEAT_INTERVAL_MS = 60_000;
export const STUCK_THRESHOLD_MS = 180_000; // 3× interval — two missed heartbeats
export const ORPHAN_IGNORE_MS = 60 * 60_000; // 60 min — above the longest heavy run

function mirror(op: string, e: unknown, runId: string): void {
  try {
    Sentry.captureException(e instanceof Error ? e : new Error(String(e)), {
      tags: { surface: "routine-run-progress", op, "inngest.run_id": runId },
    });
  } catch {
    // captureException failure must not propagate either.
  }
}

/**
 * Upsert the live row on run entry. ON CONFLICT (run_id) DO UPDATE refreshes
 * attempt + last_heartbeat_at so a replay (attempt>1) reuses the SAME row with no
 * unique-collision (P0-2). `started_at` is deliberately OMITTED from the payload:
 * on first INSERT it takes the column DEFAULT now(); on conflict it is untouched,
 * preserving the original clock across a resume (DI-P2-D) so the "resumed after
 * ~Xm" elapsed framing stays honest. Also reaps a genuinely-dead prior orphan of
 * the SAME routine (defense-in-depth — concurrency:1 makes same-routine overlap
 * impossible, but the staleness guard keeps it safe regardless — DI-P1-A).
 */
export async function upsertRoutineRunProgress(
  fnId: string,
  runId: string,
  attempt: number,
): Promise<void> {
  const svc = getServiceClient();
  try {
    const { error } = await svc
      .from(TABLE)
      .upsert(
        {
          routine_id: fnId,
          run_id: runId,
          attempt,
          last_heartbeat_at: new Date().toISOString(),
        },
        { onConflict: "run_id" },
      );
    if (error) throw error;
  } catch (e) {
    mirror("upsert", e, runId);
  }
  // Separate, staleness-GUARDED delete-stale (never an unconditional run_id<>$2
  // delete, which could drop a concurrently-live sibling — DI-P1-A).
  try {
    const staleBefore = new Date(Date.now() - ORPHAN_IGNORE_MS).toISOString();
    const { error } = await svc
      .from(TABLE)
      .delete()
      .eq("routine_id", fnId)
      .neq("run_id", runId)
      .lt("last_heartbeat_at", staleBefore);
    if (error) throw error;
  } catch (e) {
    mirror("delete-stale", e, runId);
  }
}

/**
 * Bump last_heartbeat_at. UPDATE-only (DI-P2-E) — never an upsert: a tick that
 * lands after finishRoutineRunProgress hits 0 rows (harmless no-op) instead of
 * resurrecting a completed run as a phantom live row.
 */
export async function heartbeatRoutineRunProgress(runId: string): Promise<void> {
  try {
    const { error } = await getServiceClient()
      .from(TABLE)
      .update({ last_heartbeat_at: new Date().toISOString() })
      .eq("run_id", runId);
    if (error) throw error;
  } catch (e) {
    mirror("heartbeat", e, runId);
  }
}

/**
 * Delete the live row on terminal completion. Called from run-log transformOutput
 * AFTER the terminal write succeeds (arch-A-2): if the terminal write failed, this
 * is never reached, so the live row survives and the reader shows "stuck" rather
 * than vanishing the run (DI-P1-C). Its own fail-soft mirror keeps a delete error
 * from being misattributed to the terminal write.
 */
export async function finishRoutineRunProgress(runId: string): Promise<void> {
  try {
    const { error } = await getServiceClient()
      .from(TABLE)
      .delete()
      .eq("run_id", runId);
    if (error) throw error;
  } catch (e) {
    mirror("finish", e, runId);
  }
}

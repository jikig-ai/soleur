// cron-agent-spawn-stale-settle — the stale-"Working" backstop (#8839).
//
// WHY THIS EXISTS. `agent-on-spawn-requested` settles its row through two
// lifecycle signals (`onFailure` → `agent.spawn.orphaned`, and
// `inngest/function.cancelled`). Two cases produce NO signal: rows already
// stuck on "Working" before the #8803 settle deployed, and a run Inngest
// loses entirely (no lifecycle event ever fires). In both the Today card
// reads "Working" forever with no `failure_reason`, no dead-letter page and
// no Retry affordance. This sweep is the liveness backstop that does not
// depend on an Inngest lifecycle event — the fix #8839 asked for. The
// render-side alternative (deriveTodayCardState reads a stale Working as
// failed) was REJECTED: it displays the failure but never settles the row —
// no `failure_reason` write, no dead-letter, no Retry — and it pulls the
// change through the BLOCKING Product/UX gate plus a `.pen` wireframe.
//
// THE PREDICATE, AND WHY IT IS THE LIVE-RUN DISCRIMINATOR. A row is stale
// iff its `current_turn_started_at` (or `created_at`, for a run that never
// reached turn-1-progress-write) is older than FINISH_TIMEOUT_MS +
// STALE_WORKING_MARGIN_MS. This is not a heuristic: `timeouts.finish` on
// agent-on-spawn-requested is an ABSOLUTE bound on the run's lifetime, and
// the function's `idempotency: "event.data.actionSendId"` means at most ONE
// Inngest run can ever own a row. Any live run must have started its newest
// turn within the last finish-timeout — so a row older than the bound CANNOT
// have a live run attached; it is orphaned by construction. The margin
// covers step-boundary jitter and the settle grace, so a run inside its
// deadline is never touched. The conditional UPDATE inside the shared settle
// (`.is("failure_reason", null)`) is the second, atomic guard: a row the
// lifecycle settle wins concurrently writes 0 rows and reports nothing.
//
// THE WRITE PATH IS THE SHARED ONE. Each stale row settles through
// `settleOrphanedSpawn` — the same memoized step `agent-on-spawn-settle`
// runs — never a new write path. `stopEligible: true` so a pending operator
// Stop settles as `cancelled_by_operator` (warning, no page) rather than
// `leader_internal_error` (a page): a stale row with a pending Stop is a
// lost run whose last ask was honoured, which is exactly the polarity the
// lifecycle path gives it. Settled rows are reported to spawn-dead-letter
// under the `(stale_working)` suffix so the triage runbook can tell them
// apart from an evented settle. Idempotency: a re-tick over a settled row
// is a no-op by the Working predicate; a re-run mid-tick replays only the
// unmemoized steps.
//
// ADR-033 invariants: all IO inside step.run (I1); no claude / BYOK (I2);
// no subprocess (I3); no Inngest events emitted (I6) — the settle is a
// direct shared-path call, not an `agent.spawn.orphaned` send, because the
// orphaned run's id is unrecoverable (the row never stored one) and a
// synthesized ULID would falsify `extra.failedRunId` for triage.

import { inngest } from "@/server/inngest/client";
import { getServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "@/server/observability";
import { reportSpawnDeadLetter } from "@/server/spawn-dead-letter";
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";
import {
  FINISH_TIMEOUT_MS,
  settleOrphanedSpawn,
} from "./agent-on-spawn-requested";

export const SENTRY_MONITOR_SLUG = "scheduled-agent-spawn-stale-settle";

const CRON_NAME = "cron-agent-spawn-stale-settle";

/**
 * The fixed margin past `timeouts.finish` (10m). Chosen so a run inside its
 * deadline — including one whose newest turn write is minutes old while a
 * turn-`claude` step runs — is never swept: the bound is 1.5× the absolute
 * run lifetime. Named per #8839's "10-minute finish timeout plus a margin".
 */
export const STALE_WORKING_MARGIN_MS = 5 * 60_000;

/** Cap per tick: each settle is one memoized step; a large historical backlog drains across ticks. */
const MAX_SETTLE_PER_TICK = 50;

interface StaleRow {
  id: string;
  user_id: string;
  message_id: string;
  action_class: string | null;
  source_ref: string | null;
  current_turn_started_at: string | null;
  created_at: string;
}

export interface StaleSettleResult {
  ok: boolean;
  /** Rows the sweep selected as stale-Working. */
  candidates: number;
  /** Rows this tick actually settled (wrote a terminal failure_reason). */
  settled: number;
  /** Rows the settle skipped (already terminal — a concurrent writer won). */
  skipped: number;
  /** Selected rows left for the next tick (the per-tick cap bound the work). */
  deferred: number;
}

/** The Working triple the Today card and the shared settle both use. */
function isWorkingRow(row: {
  failure_reason: string | null;
  acknowledged_at: string | null;
  undone_at: string | null;
}): boolean {
  return (
    row.failure_reason === null &&
    row.acknowledged_at === null &&
    row.undone_at === null
  );
}

/**
 * The stale predicate = the live-run discriminator. A row is stale iff its
 * last turn-write (`current_turn_started_at`, or `created_at` for a run lost
 * before turn-1-progress-write) predates `now - boundMs`. No live run can
 * satisfy this: `timeouts.finish` bounds every run's lifetime below the
 * bound, so a row this old is orphaned by construction — the property the
 * live-run-must-survive test pins from the negative side.
 */
export function isStaleWorkingRow(
  row: {
    failure_reason: string | null;
    acknowledged_at: string | null;
    undone_at: string | null;
    current_turn_started_at: string | null;
    created_at: string;
  },
  nowMs: number,
  boundMs: number = FINISH_TIMEOUT_MS + STALE_WORKING_MARGIN_MS,
): boolean {
  if (!isWorkingRow(row)) return false;
  const lastWrite = Date.parse(row.current_turn_started_at ?? row.created_at);
  if (Number.isNaN(lastWrite)) return false; // unparseable time ≠ stale; never guessed
  return lastWrite < nowMs - boundMs;
}

interface SelectRow extends StaleRow {
  failure_reason: string | null;
  acknowledged_at: string | null;
  undone_at: string | null;
}

export async function cronAgentSpawnStaleSettleHandler({
  step,
  logger,
}: HandlerArgs): Promise<StaleSettleResult> {
  // Step 1: the Working set, filtered stale in-process. "Working" is the
  // `.is(null)` triple the Today card and the shared settle both use; the
  // age predicate stays in code (isStaleWorkingRow) so it is a tested
  // function, not a PostgREST `.or` string no suite can see. Caught and
  // reported, never thrown: the 15-minute schedule is the retry.
  const selected = await step.run(
    "select-stale-working",
    async (): Promise<{ ok: true; rows: StaleRow[] } | { ok: false }> => {
      try {
        const sb = getServiceClient();
        const { data, error } = await sb
          .from("action_sends")
          .select(
            "id,user_id,message_id,action_class,source_ref,current_turn_started_at,created_at,failure_reason,acknowledged_at,undone_at",
          )
          .is("failure_reason", null)
          .is("acknowledged_at", null)
          .is("undone_at", null);
        if (error) throw error;
        const now = Date.now();
        const stale = ((data ?? []) as SelectRow[])
          .filter((r) => isStaleWorkingRow(r, now))
          // Oldest first, so a capped tick drains the longest-stuck rows.
          .sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at));
        return { ok: true, rows: stale };
      } catch (err) {
        reportSilentFallback(err instanceof Error ? err : new Error(String(err)), {
          feature: "spawn-agent",
          op: "agent-spawn-stale-settle",
          message: "cron-agent-spawn-stale-settle: stale-Working select failed",
          tags: { reason: "sweep_select_failed" },
          extra: { cron: CRON_NAME },
        });
        return { ok: false };
      }
    },
  );

  if (!selected.ok) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: CRON_NAME,
        logger,
      });
    });
    return { ok: false, candidates: 0, settled: 0, skipped: 0, deferred: 0 };
  }

  const rows = selected.rows.slice(0, MAX_SETTLE_PER_TICK);
  const deferred = Math.max(0, selected.rows.length - MAX_SETTLE_PER_TICK);
  let settled = 0;
  let skipped = 0;

  for (const row of rows) {
    // One memoized step per row — the shared settle path, never a new write.
    const outcome = await settleOrphanedSpawn(
      step,
      {
        actionSendId: row.id,
        founderId: row.user_id,
        messageId: row.message_id,
        // A pending Stop is honoured exactly as the lifecycle path honours it:
        // cancelled_by_operator reports at warning level and pages no one.
        stopEligible: true,
      },
      0,
      `settle-stale-${row.id}`,
    );
    if (!outcome.wrote) {
      skipped += 1;
      continue;
    }
    settled += 1;
    // After the memoized steps so a replay never re-reports (the #8841
    // convention). reason is leader_internal_error (paged) unless a Stop was
    // pending (cancelled_by_operator, warning) — the settle decided.
    reportSpawnDeadLetter({
      reason: outcome.reason,
      actionClass: row.action_class ?? "unknown",
      err: new Error(
        "spawn row stale on Working past finish-timeout+margin — no Inngest lifecycle event settled it (#8839 backstop)",
      ),
      lifecycle: "stale_working",
      extra: {
        founderId: row.user_id,
        messageId: row.message_id,
        sourceRef: row.source_ref,
        actionSendId: row.id,
        currentTurnStartedAt: row.current_turn_started_at,
        createdAt: row.created_at,
      },
    });
  }

  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: true,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: CRON_NAME,
      logger,
    });
  });

  return { ok: true, candidates: selected.rows.length, settled, skipped, deferred };
}

export const cronAgentSpawnStaleSettle = inngest.createFunction(
  {
    id: "cron-agent-spawn-stale-settle",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: `"${CRON_NAME}"`, limit: 1 },
    ],
    // `retries: 1` covers a throw outside the steps; a failed select is caught
    // and the next tick retries — the same convention cron-approval-expiry runs.
    retries: 1,
    triggers: [
      // */15: at-or-below the finish-timeout granularity, so a lost run cannot
      // sit visibly stale for multiples of the bound (Task Design, #8839).
      { cron: "*/15 * * * *" },
      { event: "cron/agent-spawn-stale-settle.manual-trigger" },
    ],
  },
  cronAgentSpawnStaleSettleHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[1],
);

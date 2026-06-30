// Proactive prod Supabase Disk-IO early-warning monitor (2026-06-02).
//
// WHY THIS SHAPE: Supabase's Disk IO Budget is a vendor metric that is NOT in
// Sentry's event store, and the Management API exposes no stable
// `disk_io_budget` metric endpoint (probed: infra-monitoring/metrics,
// daily-stats, usage all 404). So a `sentry_metric_alert` cannot see it. The
// only signal that works is to poll Postgres' own stat views and emit our own
// verdict. This cron calls the read-only `disk_io_pressure_signal()` RPC
// (migration 095) via the service-role client, applies a deterministic
// threshold verdict, files/auto-closes a GitHub [disk-io] issue, and posts a
// Sentry Crons heartbeat — mirroring cron-gh-pages-cert-state.ts.
//
// WHY AN RPC, NOT THE MANAGEMENT API: the signal lives in pg_catalog stat views
// PostgREST does not expose, and the runtime container has the service-role key
// but NOT a Management API PAT. The SECURITY DEFINER RPC bridges that without
// provisioning a high-privilege account token into the web container.
//
// SIGNAL + VERDICT (deterministic, no dashboard eyeballing — hr-no-dashboard-eyeball):
//   * cache_hit_pct < CACHE_HIT_FLOOR_PCT  → read-pressure regression. The
//     2026-06-02 baseline was 100.000% (writes, not reads, drive the burn); a
//     drop below 98% means a change introduced table scans.
//   * any dedup table > DEDUP_TABLE_ROW_CEIL → the 094 retention sweep stopped.
//     processed_github_events was the unbounded outlier (65,240 rows); a climb
//     past 100k is the early warning that re-depletion is coming.
//   Each breach is reported independently so the operator sees WHICH lever fired.
//   A failed signal read trips too (fail-loud: a monitor that can't read its
//   own signal is itself a failure worth surfacing).
//
// ADR-033 invariants: all outbound IO inside step.run (I1); no claude/BYOK (I2);
// no long-running subprocess (I3); deterministic step.run returns (I5); emits no
// Inngest events (I6).
//
// Plan: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md Phase 3

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

export const SENTRY_MONITOR_SLUG = "scheduled-supabase-disk-io";

const ISSUE_TITLE_PREFIX = "[disk-io]";

// Installation-token lifetime floor: 15-min headroom for a couple of API calls.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

// Threshold calibration from the 2026-06-02 prod baseline (27-day window):
//   cache_hit_pct = 100.000%; processed_github_events = 65,240 live rows.
// Floor below 100 so a real read regression is detectable; ceiling above the
// observed outlier so the healthy baseline is not a false positive AND a
// stopped retention sweep is caught well before re-depletion.
export const CACHE_HIT_FLOOR_PCT = 98.0;
export const DEDUP_TABLE_ROW_CEIL = 100_000;

// WAL-concentration ceiling (#5736). When the single largest statement's share
// of total WAL (max_wal_pct from migration 114) exceeds this, ONE statement is
// dominating the prod Disk-IO budget — the exact class of the webhook dedup
// INSERT that was 63% of WAL yet shipped green. Surfaced as its own Sentry
// capture (op=wal-concentration), INDEPENDENT of the budget verdict, so a single
// write hogging WAL pages without a dashboard (hr-no-dashboard-eyeball). 40 is a
// conservative floor: a healthy app spreads WAL across many statements, so a
// single statement past 40% is already an outlier worth a human look.
export const WAL_CONCENTRATION_PCT_CEIL = 40;

// =============================================================================
// Types
// =============================================================================

// One row of pg_stat_statements ranked by WAL (migration 114). `query` is the
// normalized statement text (literals → $1, no row values) truncated to ~120
// chars; `wal_bytes` is the cumulative WAL this statement has emitted.
export interface WalStatement {
  query: string;
  calls: number;
  wal_bytes: number;
  pct_of_wal: number;
}

export interface DiskIoSignal {
  // numeric from pg; null if pg_stat_database has no rows for the current DB.
  cache_hit_pct: number | null;
  // table name → live-row estimate (n_live_tup) for the unbounded dedup tables.
  dedup_table_rows: Record<string, number> | null | undefined;
  // top public tables by (ins+upd+del); diagnostic context ONLY — surfaced in
  // the issue body to point the operator at the write driver, never a verdict
  // input (the verdict gates on cache_hit_pct + dedup_table_rows).
  top_write_churn: Array<{ table: string; writes: number }>;
  // top-5 statements by pg_stat_statements.wal_bytes (migration 114). Optional:
  // a pre-114 RPC (or a DB without pg_stat_statements) omits it → treated as
  // "no WAL signal", never a false alert.
  top_wal_statements?: WalStatement[] | null;
  // the single largest statement's share of total WAL (max(wal_bytes)/sum*100).
  // Optional for the same back-compat reason as top_wal_statements.
  max_wal_pct?: number | null;
  sampled_at: string;
}

export interface DiskIoVerdict {
  tripped: boolean;
  reasons: string[];
  detail: string;
}

// WAL-concentration is evaluated SEPARATELY from the budget verdict: it does not
// flip the heartbeat (that stays ok = !tripped), it emits its own Sentry capture.
export interface WalConcentrationVerdict {
  concentrated: boolean;
  maxPct: number | null;
  detail: string;
  topStatement: WalStatement | null;
}

// =============================================================================
// Verdict (pure — unit-tested without a live DB)
// =============================================================================

export function evaluateDiskIoSignal(signal: DiskIoSignal): DiskIoVerdict {
  const reasons: string[] = [];

  // Read-pressure regression. A null/undefined cache_hit_pct (no stat rows) is
  // NOT a regression — only a real number below the floor trips. Guard null
  // explicitly: Number(null) === 0 would otherwise false-trip the floor.
  const cacheHit = signal.cache_hit_pct == null ? NaN : Number(signal.cache_hit_pct);
  if (Number.isFinite(cacheHit) && cacheHit < CACHE_HIT_FLOOR_PCT) {
    reasons.push(
      `cache_hit_pct=${cacheHit} < floor ${CACHE_HIT_FLOOR_PCT} (read-pressure regression — a change likely introduced table scans)`,
    );
  }

  // Unbounded-growth guard: a dedup table over the ceiling means its retention
  // sweep is not bounding the table. Two distinct causes (issue #5225, 2026-06-14
  // was the second): the cron job stopped, OR the cron is alive but its DELETE
  // window exceeds the table's replay horizon so every run reports DELETE 0 and
  // the table grows unbounded. The reason text names both so the operator checks
  // the schedule AND the interval, not just whether the job exists.
  const dedupRows = signal.dedup_table_rows ?? {};
  for (const [table, rowsRaw] of Object.entries(dedupRows)) {
    const rows = Number(rowsRaw);
    if (Number.isFinite(rows) && rows > DEDUP_TABLE_ROW_CEIL) {
      reasons.push(
        `${table}=${rows} rows > ceil ${DEDUP_TABLE_ROW_CEIL} (retention sweep stopped OR its window exceeds the table's replay horizon so it deletes nothing — check cron.job schedule AND the DELETE interval)`,
      );
    }
  }

  const tripped = reasons.length > 0;
  const detail = tripped
    ? reasons.join("; ")
    : `cache_hit_pct=${signal.cache_hit_pct}, dedup_rows=${JSON.stringify(dedupRows)} — all within thresholds`;
  return { tripped, reasons, detail };
}

// WAL-concentration lens (#5736, pure — unit-tested without a live DB). A single
// statement past WAL_CONCENTRATION_PCT_CEIL of total WAL is the write-amplification
// class our review lenses missed. A null/undefined max_wal_pct (pre-114 RPC, or no
// pg_stat_statements) is NOT concentration — only a real number over the ceiling
// concentrates. Guard null explicitly: Number(null) === 0 would otherwise read as
// "0% concentration" (harmless here) but Number(undefined) === NaN must not throw.
export function evaluateWalConcentration(signal: DiskIoSignal): WalConcentrationVerdict {
  const raw = signal.max_wal_pct == null ? NaN : Number(signal.max_wal_pct);
  const maxPct = Number.isFinite(raw) ? raw : null;
  const topStatement = (signal.top_wal_statements ?? [])[0] ?? null;
  const concentrated = maxPct != null && maxPct > WAL_CONCENTRATION_PCT_CEIL;
  const detail = concentrated
    ? `max_wal_pct=${maxPct} > ceil ${WAL_CONCENTRATION_PCT_CEIL} — one statement dominates prod WAL` +
      (topStatement
        ? ` (top: "${topStatement.query}" — ${topStatement.calls} calls, ${topStatement.pct_of_wal}% of WAL)`
        : "")
    : `max_wal_pct=${maxPct ?? "n/a"} within ceil ${WAL_CONCENTRATION_PCT_CEIL}`;
  return { concentrated, maxPct, detail, topStatement };
}

// =============================================================================
// Handler
// =============================================================================

export async function cronSupabaseDiskIoHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; tripped: boolean; detail: string }> {
  // Step 1: read the disk-IO signal via the service-role RPC. A read failure is
  // reported to Sentry here (keeps outbound IO inside step.run) and surfaced as
  // a tripped verdict below.
  const signalResult = await step.run("read-disk-io-signal", async () => {
    try {
      const { createServiceClient } = await import("@/lib/supabase/service");
      const service = createServiceClient();
      const { data, error } = await service.rpc("disk_io_pressure_signal");
      if (error) {
        reportSilentFallback(new Error(error.message), {
          feature: "cron-supabase-disk-io",
          op: "read-signal",
          message: "disk_io_pressure_signal RPC returned an error",
          extra: { fn: "cron-supabase-disk-io" },
        });
        return { ok: false as const, error: error.message };
      }
      return { ok: true as const, signal: data as DiskIoSignal };
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-supabase-disk-io",
        op: "read-signal",
        message: "disk_io_pressure_signal RPC call threw",
        extra: { fn: "cron-supabase-disk-io" },
      });
      return { ok: false as const, error: (err as Error).message };
    }
  });

  // Compute the verdict (pure). A failed read is fail-loud → tripped.
  const verdict: DiskIoVerdict = signalResult.ok
    ? evaluateDiskIoSignal(signalResult.signal)
    : {
        tripped: true,
        reasons: [`signal read failed: ${signalResult.error}`],
        detail: `disk-io signal RPC unavailable: ${signalResult.error}`,
      };
  const signal = signalResult.ok ? signalResult.signal : null;

  // Step 1.5: WAL-concentration early-warning (#5736), INDEPENDENT of the budget
  // verdict above. A single statement dominating prod WAL is the write-amplification
  // class our review lenses missed (the webhook dedup INSERT that was 63% of WAL);
  // surface it as its own Sentry capture (op=wal-concentration) so it pages without
  // a dashboard (hr-no-dashboard-eyeball-pull-data-yourself). The emit lives inside
  // step.run (ADR-033 I1: all outbound IO inside a step) and does NOT change the
  // heartbeat — WAL concentration is a write-cost signal, not a budget breach.
  if (signal) {
    const wal = evaluateWalConcentration(signal);
    if (wal.concentrated) {
      await step.run("wal-concentration-alert", async () => {
        reportSilentFallback(new Error(`WAL concentration: ${wal.detail}`), {
          feature: "cron-supabase-disk-io",
          op: "wal-concentration",
          message: "A single statement dominates prod WAL writes (#5736 class)",
          extra: {
            fn: "cron-supabase-disk-io",
            maxWalPct: wal.maxPct,
            ceil: WAL_CONCENTRATION_PCT_CEIL,
            topStatement: wal.topStatement,
          },
        });
      });
      logger.warn(
        { fn: "cron-supabase-disk-io", maxWalPct: wal.maxPct },
        "WAL concentration over ceiling",
      );
    }
  }

  // Step 2: issue handling — file/comment on trip, auto-close on recovery.
  await step.run("issue-handling", async () => {
    try {
      const installationToken = await mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
      });
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });

      const search = await octokit.request("GET /search/issues", {
        q: `repo:${REPO_OWNER}/${REPO_NAME} is:issue is:open in:title "${ISSUE_TITLE_PREFIX}"`,
        per_page: 1,
      });
      const existing = (search.data.items ?? [])[0];

      if (verdict.tripped) {
        const bodyLines = [
          "## Supabase Disk-IO pressure alert",
          "",
          "A proactive tripwire fired before the Disk IO Budget depleted.",
          "",
          "### Tripped levers",
          ...verdict.reasons.map((r) => `- ${r}`),
          "",
          "### Signal snapshot",
          "```json",
          JSON.stringify(signal ?? { error: verdict.detail }, null, 2),
          "```",
          "",
          `- **Detected at:** ${new Date().toISOString()}`,
          "",
          "### What to do",
          "",
          "- A `*_rows` breach → check the dedup retention crons are live:",
          "  `SELECT jobname, schedule FROM cron.job WHERE jobname LIKE '%_retention';`",
          "- A `cache_hit_pct` breach → a recent change likely introduced table",
          "  scans; review the top_write_churn / recent query changes.",
          "- A `signal read failed` → the disk_io_pressure_signal RPC (migration",
          "  095) or the service-role client is broken; the monitor cannot see state.",
          "",
          "_Auto-created by the [cron-supabase-disk-io Inngest function](https://github.com/jikig-ai/soleur/blob/main/apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts)._",
        ];
        if (existing) {
          await octokit.request(
            "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: existing.number,
              body: `Disk-IO still degraded at ${new Date().toISOString()} — ${verdict.detail}`,
            },
          );
          logger.info(
            { fn: "cron-supabase-disk-io", issueNumber: existing.number },
            "Commented on existing disk-io issue",
          );
        } else {
          await octokit.request("POST /repos/{owner}/{repo}/issues", {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            title: `${ISSUE_TITLE_PREFIX} Supabase Disk-IO pressure detected`,
            labels: ["action-required", "infra-drift"],
            body: bodyLines.join("\n"),
          });
          logger.info(
            { fn: "cron-supabase-disk-io" },
            "Filed new disk-io issue",
          );
        }
      } else if (existing) {
        // Recovery: comment + close the open disk-io issue.
        await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: existing.number,
            body: `Disk-IO healthy at ${new Date().toISOString()} — auto-closing. ${verdict.detail}`,
          },
        );
        await octokit.request(
          "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: existing.number,
            state: "closed",
          },
        );
        logger.info(
          { fn: "cron-supabase-disk-io", issueNumber: existing.number },
          "Auto-closed disk-io issue on recovery",
        );
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-supabase-disk-io",
        op: "issue-handling",
        message: "Failed to handle disk-io issue",
        extra: { fn: "cron-supabase-disk-io", detail: verdict.detail },
      });
    }
  });

  // Step 3: Sentry heartbeat. ok = !tripped → a trip turns the monitor red.
  const ok = !verdict.tripped;
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-supabase-disk-io",
      logger,
    });
  });

  return { ok, tripped: verdict.tripped, detail: verdict.detail };
}

// =============================================================================
// Registration
// =============================================================================

export const cronSupabaseDiskIo = inngest.createFunction(
  {
    id: "cron-supabase-disk-io",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    // 6-hourly: frequent enough for early warning on a budget that depletes over
    // hours-to-days, infrequent enough to add negligible IO (one read-only RPC).
    { cron: "0 */6 * * *" },
    { event: "cron/supabase-disk-io.manual-trigger" },
  ],
  cronSupabaseDiskIoHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);

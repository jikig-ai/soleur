// #cost-attribution (plan Phase 3) — daily Anthropic Admin cost/usage report.
//
// The `Ref #5674` deferred follow-up (cron-anthropic-credit-probe.ts:15-20):
// pull the Anthropic **Admin Cost & Usage API** once a day and emit an
// authoritative per-model / org-total spend marker, self-servable from Better
// Stack without the Anthropic Console. Attribution only — this does NOT add the
// pre-exhaustion spend-vs-budget alert (still the other half of #5674).
//
// Reads an org-billing key `ANTHROPIC_ADMIN_KEY` (sk-ant-admin01-…). This cron
// only ever GETs, and the key cannot spend or read conversations.
//
// ‼️ CORRECTION (#6297, verified 2026-07-20 in the Console): the key is NOT
// scope-limited. Console Admin keys carry **no selectable scopes** — every one
// grants full Admin-API access. An earlier version of this comment claimed
// "the real blast-radius control is its read-only scope"; that was false, and
// no such control exists. Read-only is a property of THIS CALLER's usage, not
// of the credential, so treat the key as full-Admin-API-privileged wherever it
// is stored or handled. (Same correction applied to ADR-108.)
//
// While the key is unprovisioned the cron self-reports `key-missing` BENIGNLY —
// a positive `SOLEUR_CLAUDE_COST_DAILY {status:"key-missing"}` marker (obs P4),
// NOT a fleet-down page. That state is currently indefinite, not a short mint
// window: the Admin API is unavailable to individual accounts and this org is
// one, so the key is un-mintable until the org converts to a team organization
// (an operator decision — see #6297).
//
// Classify-fatal (mirrors the credit-probe):
//   - 401 / 403 (bad/revoked admin key) → RED heartbeat (fatal).
//   - 429 / 5xx / network (transient)   → RETHROW → Inngest retry; the error
//     heartbeat is gated on the FINAL attempt so a recovered transient never pages.
//   - success                           → GREEN heartbeat + the daily marker.

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import {
  postSentryHeartbeat,
  getAnthropicAdminReport,
  AnthropicApiError,
  type HandlerArgs,
} from "./_cron-shared";
import {
  emitClaudeCostDailyMarker,
  type ClaudeCostDailyModelEntry,
} from "@/server/claude-cost-marker";

const SENTRY_MONITOR_SLUG = "scheduled-anthropic-cost-report";
const CRON_NAME = "cron-anthropic-cost-report";

const ADMIN_REPORT_TIMEOUT_MS = 30_000;

// -----------------------------------------------------------------------------
// Pure parse helpers (unit-tested against synthesized fixtures — AC6/AC6b).
// -----------------------------------------------------------------------------

// First observed dark fire (Sentry e0e6f356764b4bb6be8b0a8e74898e9f, release
// web-platform@0.208.0). A frozen historical date, NOT a window start — see the
// field comment on `days_since_first_dark` in claude-cost-marker.ts. Measured
// from here rather than process start so a container restart never resets it.
const FIRST_DARK_FIRE = "2026-07-10";

// Whole UTC days elapsed since FIRST_DARK_FIRE, floored at 0. Pure and
// inert — nothing branches on the result; it is reporting data only, so a
// stale reading can never page. Floored so clock skew or a backfill cannot
// produce a negative count.
export function daysSinceFirstDark(now: Date = new Date()): number {
  const first = Date.parse(`${FIRST_DARK_FIRE}T00:00:00Z`);
  const days = Math.floor((now.getTime() - first) / 86_400_000);
  return days > 0 ? days : 0;
}

// `YYYY-MM-DD` for the prior UTC day (the bucket the daily report covers).
export function priorUtcDay(now: Date = new Date()): string {
  const d = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - 1),
  );
  return d.toISOString().slice(0, 10);
}

/**
 * Sum the org-total cost from an Admin `/v1/organizations/cost_report` response.
 *
 * UNVERIFIED (plan R-D / Phase-0 `amount` unit): the live probe requires the
 * minted admin key (a follow-up that lands after the vendor-console mint). The
 * documented shape is `data[].results[].amount` as a decimal STRING alongside
 * `currency: "USD"`, which we treat as **dollars**. If the live probe shows
 * cents, divide by 100 here and update the fixture in the test.
 */
export function parseCostReportTotal(json: unknown): number | null {
  const root = json as { data?: Array<{ results?: Array<{ amount?: unknown }> }> };
  if (!Array.isArray(root?.data)) return null;
  let total = 0;
  let sawAny = false;
  for (const bucket of root.data) {
    for (const r of bucket?.results ?? []) {
      const amt =
        typeof r.amount === "number"
          ? r.amount
          : typeof r.amount === "string"
            ? Number.parseFloat(r.amount)
            : NaN;
      if (Number.isFinite(amt)) {
        total += amt;
        sawAny = true;
      }
    }
  }
  return sawAny ? total : null;
}

/**
 * Build the per-model entries from an Admin `/v1/organizations/usage_report/
 * messages` response grouped by model. FIELD-ALLOWLIST (named picks) ONLY — the
 * API rows carry `api_key_id` / `workspace_id`; a `...row` spread would ship
 * those to Better Stack (security F2). `cost_usd` is null (usage_report reports
 * tokens, not $; the org total $ comes from cost_report). Per-model $ derivation
 * is out of scope (attribution only).
 */
export function parseUsageReportModels(
  json: unknown,
): ClaudeCostDailyModelEntry[] {
  const root = json as {
    data?: Array<{
      results?: Array<{
        model?: unknown;
        input_tokens?: unknown;
        output_tokens?: unknown;
        uncached_input_tokens?: unknown;
        cache_read_input_tokens?: unknown;
        cache_creation_input_tokens?: unknown;
      }>;
    }>;
  };
  if (!Array.isArray(root?.data)) return [];
  const byModel = new Map<string, ClaudeCostDailyModelEntry>();
  const num = (v: unknown): number =>
    typeof v === "number" && Number.isFinite(v) ? v : 0;
  for (const bucket of root.data) {
    for (const r of bucket?.results ?? []) {
      const model = typeof r.model === "string" ? r.model : "unknown";
      const prev = byModel.get(model) ?? {
        model,
        input_tokens: 0,
        output_tokens: 0,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
        cost_usd: null,
      };
      byModel.set(model, {
        model,
        input_tokens:
          (prev.input_tokens ?? 0) +
          num(r.input_tokens ?? r.uncached_input_tokens),
        output_tokens: (prev.output_tokens ?? 0) + num(r.output_tokens),
        cache_read_input_tokens:
          (prev.cache_read_input_tokens ?? 0) + num(r.cache_read_input_tokens),
        cache_creation_input_tokens:
          (prev.cache_creation_input_tokens ?? 0) +
          num(r.cache_creation_input_tokens),
        cost_usd: null,
      });
    }
  }
  return [...byModel.values()];
}

// -----------------------------------------------------------------------------
// Handler
// -----------------------------------------------------------------------------

export async function cronAnthropicCostReportHandler({
  step,
  logger,
  attempt,
  maxAttempts,
}: HandlerArgs): Promise<{ ok: boolean; status: "ok" | "key-missing" | "error" }> {
  // Inngest delivers a zero-indexed `attempt`; retries:1 → maxAttempts 2, final
  // is index 1. Legacy/test shape (neither passed) → attempt=0/maxAttempts=1 →
  // isFinalAttempt=true (page on the sole attempt). Mirrors cron-stale-deferred.
  const isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1);

  const adminKey = process.env.ANTHROPIC_ADMIN_KEY;
  if (!adminKey) {
    // Optional-key-missing is NOT fleet-down: self-report benignly (no page) +
    // a POSITIVE dark marker so the daily Better Stack surface is positively
    // dark, not absent (obs P4 — an absent row is mis-triageable during the
    // code-merges-first → mint window).
    const daysDark = daysSinceFirstDark();
    // WARNING, not ERROR. Sentry derives issue priority from level, and the
    // operator's "high priority issues" notification rule fires on the derived
    // priority — so an `error`-level emit here paged daily for a state this
    // function's own header calls BENIGN (#6297).
    //
    // Two INDEPENDENT emissions leave this branch; do not conflate them:
    //   1. this `warnSilentFallback` — the diagnostic line. Rides the SHARED
    //      logger at pino 40 (≥ Vector's `app_container_warn_filter` cut) and
    //      raises a Sentry `captureMessage` at level=warning. Dropping it to
    //      `info` would silence THIS line in both Better Stack and Sentry.
    //   2. `emitClaudeCostDailyMarker` below — the SOLEUR_CLAUDE_COST_DAILY
    //      row. Ships from claude-cost-marker.ts's own dedicated pino instance
    //      at a hard-coded `log.warn`, with no Sentry mirror (ADR-108 item 2).
    //      Its delivery does NOT depend on the level chosen here.
    // Keeping the Sentry mirror at all is required by
    // cq-silent-fallback-must-mirror-to-sentry.
    warnSilentFallback(null, {
      feature: CRON_NAME,
      op: "anthropic-admin-key-missing",
      message:
        "ANTHROPIC_ADMIN_KEY unset — daily cost report is dark until the key is provisioned (expected during the mint window)",
      extra: { fn: CRON_NAME, days_since_first_dark: daysDark },
    });
    emitClaudeCostDailyMarker({
      status: "key-missing",
      date: priorUtcDay(),
      cost_usd: null,
      models: [],
      days_since_first_dark: daysDark,
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: CRON_NAME,
        logger,
      });
    });
    return { ok: true, status: "key-missing" };
  }

  const day = priorUtcDay();

  // Single consolidated step.run (learning 2026-06-14 — Inngest memoizes return
  // values, not side effects): BOTH Admin pulls live in one step so a replay
  // re-fetches deterministically. cost_report = authoritative org-total $;
  // usage_report(group_by=model) = per-model token split.
  let decision:
    | { ok: true; costUsd: number | null; models: ClaudeCostDailyModelEntry[] }
    | { ok: false; fatal: true; status: number };
  try {
    decision = await step.run("anthropic-admin-report", async () => {
      try {
        const [costReport, usageReport] = await Promise.all([
          getAnthropicAdminReport({
            adminKey,
            path: "/v1/organizations/cost_report",
            query: { starting_at: day, bucket_width: "1d" },
            timeoutMs: ADMIN_REPORT_TIMEOUT_MS,
          }),
          getAnthropicAdminReport({
            adminKey,
            path: "/v1/organizations/usage_report/messages",
            query: {
              starting_at: day,
              bucket_width: "1d",
              "group_by[]": ["model"],
            },
            timeoutMs: ADMIN_REPORT_TIMEOUT_MS,
          }),
        ]);
        return {
          ok: true as const,
          costUsd: parseCostReportTotal(costReport),
          models: parseUsageReportModels(usageReport),
        };
      } catch (err) {
        if (
          err instanceof AnthropicApiError &&
          (err.status === 401 || err.status === 403)
        ) {
          // Bad/revoked admin key — fatal RED (no retry recovers a bad key).
          reportSilentFallback(
            new Error("Anthropic Admin API auth failure (invalid/revoked admin key)"),
            {
              feature: CRON_NAME,
              op: "anthropic-admin-key-invalid",
              message:
                "ANTHROPIC_ADMIN_KEY is invalid or revoked — the daily cost report cannot run",
              extra: { fn: CRON_NAME, status: err.status },
            },
          );
          return { ok: false as const, fatal: true as const, status: err.status };
        }
        // Transient (429/5xx/network) — RETHROW so Inngest retries; the
        // missed-checkin margin backstops.
        throw err;
      }
    });
  } catch (err) {
    // Transient rethrow reached the handler. Gate the RED heartbeat on the
    // FINAL attempt so a recovered transient never pages (mirrors cron-stale-
    // deferred-scope-outs). Non-final: rethrow for the next Inngest retry.
    if (!isFinalAttempt) throw err;
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: CRON_NAME,
        logger,
      });
    });
    return { ok: false, status: "error" };
  }

  if (!decision.ok) {
    // Classified fatal (401/403) — RED heartbeat, no retry.
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: CRON_NAME,
        logger,
      });
    });
    return { ok: false, status: "error" };
  }

  // Success — emit the authoritative daily marker (field-allowlist per model)
  // and a GREEN heartbeat.
  emitClaudeCostDailyMarker({
    status: "ok",
    date: day,
    cost_usd: decision.costUsd,
    models: decision.models,
  });
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: true,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: CRON_NAME,
      logger,
    });
  });
  return { ok: true, status: "ok" };
}

// =============================================================================
// Registration
// =============================================================================
// Daily, off-peak (06:17 UTC — `17 6 * * *`). retries:1; account-scope concurrency limits to 1
// simultaneous cron-* invocation across the node. Manual-trigger event
// `cron/anthropic-cost-report.manual-trigger`.

export const cronAnthropicCostReport = inngest.createFunction(
  {
    id: "cron-anthropic-cost-report",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "17 6 * * *" },
    { event: "cron/anthropic-cost-report.manual-trigger" },
  ],
  cronAnthropicCostReportHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);

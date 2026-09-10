// PR-C §2.3 (#3244): the conversations SELECT below now uses tenant-
// scoped JWT (`getFreshTenantClient(userId)`) — RLS on `conversations`
// enforces `auth.uid() = user_id`, layered on top of the explicit
// `.eq("user_id", userId)` filter. The `sum_user_mtd_cost_by_workflow`
// and `sum_user_mtd_cost` RPCs stay service-role because migration
// 136 (and 027:68 before it) REVOKEd EXECUTE FROM authenticated — a
// tenant-JWT call would 42501 silently. Callers MUST still pass the
// authenticated session's userId; the UUID validation below is the
// IDOR guardrail.

import { createServiceClient } from "@/lib/supabase/service";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import { relativeTime } from "@/lib/relative-time";
import { reportSilentFallback } from "@/server/observability";
import { isWorkflowBucket, workflowLabel } from "@/lib/messages/workflow-copy";

// Re-exported so consumers import time-formatting from the same module as the
// loader. Canonical implementation lives in @/lib/relative-time.
export { relativeTime };

export const MAX_USAGE_ROWS = 50;

export interface ApiUsageRow {
  id: string;
  domainLabel: string;
  createdAt: Date;
  inputTokens: number;
  outputTokens: number;
  // Cache tokens — `0` when prompt caching was not engaged for this
  // conversation. Widened 2026-05-12 (migration 041) so the dashboard's
  // "Input" pill can render `(uncached + cache_read + cache_creation)`
  // — matching the Anthropic Console's headline total input.
  cacheReadTokens: number;
  cacheCreationTokens: number;
  costUsd: number;
}

// One bucket of the month-to-date spend partition (#1055). `bucket` is the
// normalised key emitted by `sum_user_mtd_cost_by_workflow` — never the raw
// `__unrouted__` storage sentinel, which migration 136 folds to `unrouted`.
export interface WorkflowCostRow {
  bucket: string;
  /** Founder-facing name from `lib/messages/workflow-copy.ts`. */
  label: string;
  totalUsd: number;
  count: number;
  /** `totalUsd / count`. Division, not accumulation — nothing is summed here. */
  avgUsd: number;
}

export interface ApiUsage {
  mtdTotalUsd: number;
  mtdCount: number;
  rows: ApiUsageRow[];
  // `null` means the per-workflow aggregate FAILED; `[]` means it succeeded
  // and there are no buckets. Collapsing the two is how a partial failure
  // becomes a wrong number on screen — the UI renders a different thing for
  // each (an "unavailable" line vs. nothing at all).
  byWorkflow: WorkflowCostRow[] | null;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const DOMAIN_LABEL_MAP = new Map<string, string>(
  DOMAIN_LEADERS.map((l) => [l.id, l.domain]),
);

export function computeMonthStartIso(now: Date = new Date()): string {
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
  ).toISOString();
}

export function resolveDomainLabel(
  leaderId: string | null | undefined,
): string {
  if (!leaderId) return "—";
  return DOMAIN_LABEL_MAP.get(leaderId) ?? "—";
}

export function formatUsd(n: number): string {
  if (!Number.isFinite(n) || n < 0) return "$0.00";
  if (n > 0 && n < 0.01) return `$${n.toFixed(4)}`;
  return `$${n.toFixed(2)}`;
}

interface ConversationListRow {
  id: string;
  domain_leader: string | null;
  created_at: string;
  input_tokens: number | string | null;
  output_tokens: number | string | null;
  cache_read_input_tokens: number | string | null;
  cache_creation_input_tokens: number | string | null;
  total_cost_usd: number | string | null;
}

// Typed explicitly instead of inferring from the client — Supabase JS v2
// RPC return inference can collapse to `never` in some consumer contexts
// (see learning 2026-04-05-supabase-returntype-resolves-to-never).
interface MonthSumRow {
  total: string | number | null;
  n: number | null;
}

// `sum_user_mtd_cost_by_workflow` RETURNS TABLE(bucket, total, n, is_total).
// Exactly one row carries `is_total = true` — the ROLLUP super-aggregate, and
// the ONLY place the headline may be read from.
interface WorkflowSumRow {
  bucket: string | null;
  total: string | number | null;
  n: number | string | null;
  is_total: boolean | null;
}

/** Narrow an unknown rejection/error to its PostgREST SQLSTATE, if any. */
function errCode(err: unknown): string | null {
  return (err as { code?: string } | null | undefined)?.code ?? null;
}

export async function loadApiUsageForUser(
  userId: string,
): Promise<ApiUsage | null> {
  if (!UUID_RE.test(userId)) {
    throw new Error("loadApiUsageForUser: userId must be a UUID");
  }

  // PR-C §2.3 (#3244): tenant client for the conversations SELECT.
  // Per-handler RLS-baseline auth probe per plan §0.4 — surfaces
  // mid-TTL jti revocation or RLS policy churn that a cached JWT
  // would otherwise silently mask as zero rows.
  let tenant;
  try {
    tenant = await getFreshTenantClient(userId);
    const { error: probeErr } = await tenant
      .from("users")
      .select("id")
      .eq("id", userId)
      .maybeSingle();
    if (probeErr) {
      reportSilentFallback(probeErr, {
        feature: "api-usage",
        op: "auth-probe",
        extra: { userId },
      });
      return null;
    }
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      reportSilentFallback(err, {
        feature: "api-usage",
        op: "auth-probe",
        extra: { userId },
      });
      return null;
    }
    throw err;
  }

  // SERVICE-ROLE: both `sum_user_mtd_cost_by_workflow` (migration 136)
  // and its `sum_user_mtd_cost` fallback (migration 027:68) are REVOKEd
  // from authenticated. A tenant-JWT call would 42501 silently. The
  // explicit `uid` parameter is the load-bearing access control — each
  // RPC body filters cost rows to `WHERE user_id = uid`, and the caller
  // (this function) passes the authenticated session's userId. File
  // stays on `.service-role-allowlist` as PERMANENT for this surface.
  const service = createServiceClient();
  const monthStartIso = computeMonthStartIso();

  // `allSettled`, NOT `all` (#1055). The per-workflow aggregate is a
  // SUPPLEMENTARY read whose failure must degrade to `byWorkflow: null`, not
  // blank a correct money display. A *rejecting* promise (transport drop,
  // statement timeout) would throw straight past the `.error` handling below
  // under `Promise.all`, converting that intended degradation into fail-whole.
  const [listSettled, workflowSettled] = await Promise.allSettled([
    // visibility-sweep-audit: owner-scoped — BYOK cost aggregation is per-user
    tenant
      .from("conversations")
      .select(
        "id, domain_leader, created_at, input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens, total_cost_usd",
      )
      .eq("user_id", userId)
      .gt("total_cost_usd", 0)
      .order("created_at", { ascending: false })
      .limit(MAX_USAGE_ROWS),
    service.rpc("sum_user_mtd_cost_by_workflow", {
      uid: userId,
      since: monthStartIso,
    }),
  ]);

  const listErr =
    listSettled.status === "rejected"
      ? listSettled.reason
      : (listSettled.value.error ?? null);

  if (listErr) {
    reportSilentFallback(listErr, {
      feature: "api-usage",
      op: "loadApiUsageForUser",
      extra: { listCode: errCode(listErr), monthCode: null },
    });
    return null;
  }

  const listData = (listSettled.status === "fulfilled"
    ? (listSettled.value.data ?? [])
    : []) as ConversationListRow[];

  const rows: ApiUsageRow[] = listData.map((r) => ({
    id: r.id,
    domainLabel: resolveDomainLabel(r.domain_leader),
    createdAt: new Date(r.created_at),
    inputTokens: Number(r.input_tokens ?? 0),
    outputTokens: Number(r.output_tokens ?? 0),
    cacheReadTokens: Number(r.cache_read_input_tokens ?? 0),
    cacheCreationTokens: Number(r.cache_creation_input_tokens ?? 0),
    costUsd: Number(r.total_cost_usd ?? 0),
  }));

  const workflowErr =
    workflowSettled.status === "rejected"
      ? workflowSettled.reason
      : (workflowSettled.value.error ?? null);

  if (workflowErr) {
    // Dedicated tag — deliberately NOT folded into `loadApiUsageForUser`,
    // whose events mean "the whole section failed". This one means "the
    // headline and list are correct; only the split is missing".
    reportSilentFallback(workflowErr, {
      feature: "api-usage",
      op: "mtd-by-workflow",
      extra: { code: errCode(workflowErr) },
    });

    // SEQUENTIAL, and only here. Issuing `sum_user_mtd_cost` in parallel as a
    // "safety net" would reintroduce the two-snapshot race one layer up: the
    // headline would come from a second transaction while the buckets came
    // from the first, so the two figures the UI asks the reader to reconcile
    // could disagree. `increment_conversation_cost` fires on every turn, so
    // that window is real. In the happy path this RPC is not called at all.
    const monthRes = await service.rpc("sum_user_mtd_cost", {
      uid: userId,
      since: monthStartIso,
    });

    if (monthRes.error) {
      reportSilentFallback(monthRes.error, {
        feature: "api-usage",
        op: "loadApiUsageForUser",
        extra: { listCode: null, monthCode: monthRes.error.code ?? null },
      });
      return null;
    }

    // PostgREST returns NUMERIC as a JS string to preserve 12,6 precision.
    // The aggregate has no GROUP BY so zero-match still emits one row --
    // COALESCE gives [{ total: "0", n: 0 }]. The `?? 0` guards the
    // defensive-undefined path anyway (e.g. if the RPC response shape drifts
    // in a future supabase-js release).
    const monthRow = (monthRes.data as MonthSumRow[] | null)?.[0];
    return {
      mtdTotalUsd: Number(monthRow?.total ?? 0),
      mtdCount: Number(monthRow?.n ?? 0),
      rows,
      byWorkflow: null,
    };
  }

  const workflowData = (workflowSettled.status === "fulfilled"
    ? (workflowSettled.value.data ?? [])
    : []) as WorkflowSumRow[];

  // The headline comes from the `is_total` row — the ROLLUP super-aggregate
  // produced by the SAME statement as the buckets, therefore the SAME MVCC
  // snapshot. Never `[0]` (emission order is a convention, see below) and
  // never a second query (that is the race this design exists to close).
  const totalRow = workflowData.find((r) => r.is_total === true);

  // A ROLLUP always emits its super-aggregate, so an absent is_total row means
  // the response SHAPE drifted (a migration replaced the function, PostgREST
  // changed its envelope) -- not that the user spent nothing. The previous
  // `?? 0` rendered $0.00 above a non-empty conversation list with nothing
  // mirrored: a wrong money figure presented as a real one, which on a BYOK
  // surface is the single-user incident this plan's threshold names.
  //
  // The sibling `?? 0` guards below are DIFFERENT and stay: those coerce a
  // NUMERIC field that is genuinely absent-or-null on a legitimately empty
  // result, and 0 is the right answer there. This one guards a row that must
  // exist.
  if (workflowData.length > 0 && totalRow === undefined) {
    reportSilentFallback(null, {
      feature: "api-usage",
      op: "mtd-by-workflow-no-total-row",
      extra: { rows: workflowData.length },
    });
    return null;
  }

  const mtdTotalUsd = Number(totalRow?.total ?? 0);
  const mtdCount = Number(totalRow?.n ?? 0);

  // Coerce at the boundary; never sum in JS. The sum invariant is asserted
  // SQL-side on NUMERIC (AC1/AC2) — TS only renders server-computed values.
  // Sorting ≤ 8 already-coerced rows and dividing per row accumulate nothing.
  // A non-total row whose `bucket` is not a string cannot be rendered, and
  // dropping it silently loses money under a "Nothing is left out" promise.
  // The CASE in migration 136 can never produce one (its IS NULL arm returns
  // 'legacy' first), so this is response-shape drift, not data -- mirror it
  // rather than discarding it quietly. Sibling of the unmapped-bucket mirror
  // below; `cq-silent-fallback-must-mirror-to-sentry`.
  const droppedRows = workflowData.filter(
    (r) => r.is_total !== true && typeof r.bucket !== "string",
  );
  if (droppedRows.length > 0) {
    reportSilentFallback(null, {
      feature: "api-usage",
      op: "mtd-by-workflow-nonstring-bucket",
      extra: { dropped: droppedRows.length },
    });
  }

  const byWorkflow: WorkflowCostRow[] = workflowData
    .filter(
      (r): r is WorkflowSumRow & { bucket: string } =>
        r.is_total !== true && typeof r.bucket === "string",
    )
    .map((r) => {
      const totalUsd = Number(r.total ?? 0);
      const count = Number(r.n ?? 0);
      if (!isWorkflowBucket(r.bucket)) {
        // Partial deploy: migration 032's CHECK enum widened ahead of this
        // bundle. The row still renders (dropping it would break "Nothing is
        // left out"), but the unmapped key is mirrored to Sentry rather than
        // leaking a raw slug silently. Distinct op string — `mtd-by-workflow`
        // must stay a one-hit grep (plan §Observability discoverability_test).
        reportSilentFallback(null, {
          feature: "api-usage",
          op: "workflow-bucket-unmapped",
          extra: { bucket: r.bucket },
        });
      }
      return {
        bucket: r.bucket,
        label: workflowLabel(r.bucket),
        totalUsd,
        count,
        // Mean of the RAW total, deliberately not of the largest-remainder
        // allocated display value. `avgUsd * count` may therefore differ from
        // the rendered bucket total by a cent. That is correct and must not be
        // "fixed": allocation exists so the displayed PARTS sum to the
        // displayed WHOLE, which is the only summation the copy promises
        // ("match to the cent" governs breakdown vs headline). An average
        // computed from allocated units would be the mean of a rounding
        // artefact rather than of the spend, and would drift as buckets are
        // added or removed without any underlying money changing.
        avgUsd: count > 0 ? totalUsd / count : 0,
      };
    })
    // Defensive re-sort. The function emits `ORDER BY GROUPING(bucket) DESC,
    // 2 DESC, 1 ASC` and SECURITY DEFINER blocks planner inlining, so the
    // order does hold today — but PostgREST issues `SELECT * FROM fn(...)`
    // with no outer ORDER BY, so emission order is a convention, not a
    // contract. The UI's ordering claim is made here.
    .sort((a, b) => b.totalUsd - a.totalUsd || a.bucket.localeCompare(b.bucket));

  return { mtdTotalUsd, mtdCount, rows, byWorkflow };
}

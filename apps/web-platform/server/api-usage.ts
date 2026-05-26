// PR-C §2.3 (#3244): the conversations SELECT below now uses tenant-
// scoped JWT (`getFreshTenantClient(userId)`) — RLS on `conversations`
// enforces `auth.uid() = user_id`, layered on top of the explicit
// `.eq("user_id", userId)` filter. The `sum_user_mtd_cost` RPC stays
// service-role because migration 027:68 REVOKEd EXECUTE FROM
// authenticated — a tenant-JWT call would 42501 silently. Callers
// MUST still pass the authenticated session's userId; the UUID
// validation below is the IDOR guardrail.

import { createServiceClient } from "@/lib/supabase/service";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import { relativeTime } from "@/lib/relative-time";
import { reportSilentFallback } from "@/server/observability";

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

export interface ApiUsage {
  mtdTotalUsd: number;
  mtdCount: number;
  rows: ApiUsageRow[];
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

  // SERVICE-ROLE: `sum_user_mtd_cost` is REVOKEd from authenticated
  // (migration 027:68). A tenant-JWT call would 42501 silently. The
  // explicit `uid` parameter is the load-bearing access control — the
  // RPC body filters cost rows to `WHERE user_id = uid`, and the caller
  // (this function) passes the authenticated session's userId. File
  // stays on `.service-role-allowlist` as PERMANENT for this surface.
  const service = createServiceClient();
  const monthStartIso = computeMonthStartIso();

  const [listRes, monthRes] = await Promise.all([
    tenant
      .from("conversations")
      .select(
        "id, domain_leader, created_at, input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens, total_cost_usd",
      )
      .eq("user_id", userId)
      .gt("total_cost_usd", 0)
      .order("created_at", { ascending: false })
      .limit(MAX_USAGE_ROWS),
    service.rpc("sum_user_mtd_cost", {
      uid: userId,
      since: monthStartIso,
    }),
  ]);

  if (listRes.error || monthRes.error) {
    reportSilentFallback(listRes.error ?? monthRes.error, {
      feature: "api-usage",
      op: "loadApiUsageForUser",
      extra: {
        listCode: listRes.error?.code ?? null,
        monthCode: monthRes.error?.code ?? null,
      },
    });
    return null;
  }

  const listData = (listRes.data ?? []) as ConversationListRow[];

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

  // PostgREST returns NUMERIC as a JS string to preserve 12,6 precision.
  // RPC returns a TABLE: [{ total: "0.042300", n: 2 }]. The aggregate has
  // no GROUP BY so zero-match still emits one row -- COALESCE gives
  // [{ total: "0", n: 0 }]. The `?? 0` guards the defensive-undefined
  // path anyway (e.g. if the RPC response shape drifts in a future
  // supabase-js release).
  const monthRow = (monthRes.data as MonthSumRow[] | null)?.[0];
  const mtdTotalUsd = Number(monthRow?.total ?? 0);
  const mtdCount = Number(monthRow?.n ?? 0);

  return { mtdTotalUsd, mtdCount, rows };
}

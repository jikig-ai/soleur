// Caller MUST have verified the userId belongs to the authenticated session.
// This function trusts its input — it uses createServiceClient(), which
// bypasses RLS. Authorization reduces to "the caller passed the correct
// userId." The UUID validation below is a guardrail against IDOR from a
// future caller that forgets to authenticate.

import { createServiceClient } from "@/lib/supabase/service";
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

  const service = createServiceClient();
  const monthStartIso = computeMonthStartIso();

  const [listRes, monthRes] = await Promise.all([
    service
      .from("conversations")
      .select(
        "id, domain_leader, created_at, input_tokens, output_tokens, total_cost_usd",
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

// Caller MUST have verified the userId belongs to the authenticated session.
// This function trusts its input — it uses createServiceClient(), which
// bypasses RLS. Authorization reduces to "the caller passed the correct
// userId." The UUID validation below is a guardrail against IDOR from a
// future caller that forgets to authenticate.

import { createServiceClient } from "@/lib/supabase/service";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";

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

export function formatRelativeTime(date: Date, now: Date = new Date()): string {
  const diffMs = now.getTime() - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  if (diffSec < 60) return "just now";
  const diffMin = Math.floor(diffSec / 60);
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  const diffDay = Math.floor(diffHr / 24);
  if (diffDay < 30) return `${diffDay}d ago`;
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}

interface ConversationListRow {
  id: string;
  domain_leader: string | null;
  created_at: string;
  input_tokens: number | string | null;
  output_tokens: number | string | null;
  total_cost_usd: number | string | null;
}

interface MonthScopeRow {
  total_cost_usd: number | string | null;
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
      .limit(50),
    service
      .from("conversations")
      .select("total_cost_usd", { count: "exact" })
      .eq("user_id", userId)
      .gt("total_cost_usd", 0)
      .gte("created_at", monthStartIso),
  ]);

  if (listRes.error || monthRes.error) return null;

  const listData = (listRes.data ?? []) as ConversationListRow[];
  const monthData = (monthRes.data ?? []) as MonthScopeRow[];

  const rows: ApiUsageRow[] = listData.map((r) => ({
    id: r.id,
    domainLabel: resolveDomainLabel(r.domain_leader),
    createdAt: new Date(r.created_at),
    inputTokens: Number(r.input_tokens ?? 0),
    outputTokens: Number(r.output_tokens ?? 0),
    costUsd: Number(r.total_cost_usd ?? 0),
  }));

  const mtdTotalUsd = monthData.reduce(
    (sum, r) => sum + Number(r.total_cost_usd ?? 0),
    0,
  );
  const mtdCount = Number(monthRes.count ?? 0);

  return { mtdTotalUsd, mtdCount, rows };
}

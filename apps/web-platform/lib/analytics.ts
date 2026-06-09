export interface UserRow {
  id: string;
  email: string;
  created_at: string;
  // Heterogeneous JSONB array (#4224): legacy `{date,count}` rows from
  // `recordKbSyncHistory` coexist with rich `{at,trigger,ok,...}` rows
  // from `appendKbSyncRow`. The admin sparkline only consumes legacy
  // rows; the kbHistory derivation filters via a type-narrowing guard.
  kb_sync_history: unknown[];
  // 'provisioning' | 'ready' (001_initial_schema.sql). Drives the funnel's
  // "workspace ready" stage; computeMetrics ignores it.
  workspace_status: string;
}

export interface ConversationRow {
  user_id: string;
  domain_leader: string;
  status: string;
  created_at: string;
}

export interface UserMetrics {
  userId: string;
  email: string;
  domainCounts: Record<string, number>;
  domainCount: number;
  totalSessions: number;
  sessionsByDay: Record<string, number>;
  kbHistory: Array<{ date: string; count: number }>;
  ttfvDays: number | null;
  errorRate: number;
  churning: boolean;
  daysSinceLastSession: number | null;
}

const CHURN_THRESHOLD_DAYS = 7;
const MS_PER_DAY = 86_400_000;

// --- Activation funnel (aggregate; #5049) ---

const ACTIVATION_MIN_DOMAINS = 2;
const ACTIVATION_MIN_SPAN_DAYS = 14;

export const ACTIVATION_DEF =
  "Activated = used ≥2 domains across a ≥14-day span (first→last non-failed session)";

export interface FunnelStage {
  key: "signed_up" | "workspace_ready" | "first_conversation" | "activated";
  label: string;
  count: number;
  // Drop-off from the immediately-preceding stage. `null` for the first stage
  // (no predecessor); "—" when the predecessor count is 0 (avoids NaN/Infinity).
  dropoffLabel: string | null;
}

export interface FunnelResult {
  signupCount: number;
  activatedCount: number;
  activationDef: string;
  stages: FunnelStage[];
}

/**
 * Aggregate activation funnel over existing Supabase data. All per-user
 * derivations use NON-FAILED conversations only (P0-2): a domain reached only
 * via a failed session does not count toward activation, and an all-failed user
 * never clears the "first conversation" stage.
 *
 * Stages are independent counts, not strictly-nested subsets — the render must
 * not imply false nesting (P2-1).
 */
export function computeFunnel(
  users: UserRow[],
  conversations: ConversationRow[],
  now: Date = new Date(),
): FunnelResult {
  // Index non-failed conversations by user.
  const nonFailedByUser = new Map<string, ConversationRow[]>();
  for (const c of conversations) {
    if (c.status === "failed") continue;
    const list = nonFailedByUser.get(c.user_id) ?? [];
    list.push(c);
    nonFailedByUser.set(c.user_id, list);
  }

  let workspaceReady = 0;
  let firstConversation = 0;
  let activated = 0;

  for (const u of users) {
    if (u.workspace_status === "ready") workspaceReady++;

    const convs = nonFailedByUser.get(u.id) ?? [];
    if (convs.length === 0) continue;
    firstConversation++;

    const domains = new Set(convs.map((c) => c.domain_leader));
    let firstMs = Infinity;
    let lastMs = -Infinity;
    for (const c of convs) {
      const ms = new Date(c.created_at).getTime();
      if (ms < firstMs) firstMs = ms;
      if (ms > lastMs) lastMs = ms;
    }
    const spanDays = (lastMs - firstMs) / MS_PER_DAY;
    if (domains.size >= ACTIVATION_MIN_DOMAINS && spanDays >= ACTIVATION_MIN_SPAN_DAYS) {
      activated++;
    }
  }

  const counts: Array<{ stage: FunnelStage["key"]; label: string; count: number }> = [
    { stage: "signed_up", label: "Signed up", count: users.length },
    { stage: "workspace_ready", label: "Workspace ready", count: workspaceReady },
    { stage: "first_conversation", label: "First conversation", count: firstConversation },
    { stage: "activated", label: "Activated", count: activated },
  ];

  const stages: FunnelStage[] = counts.map((c, i) => {
    let dropoffLabel: string | null;
    if (i === 0) {
      dropoffLabel = null;
    } else {
      const prev = counts[i - 1].count;
      dropoffLabel =
        prev === 0 ? "—" : `${Math.round(((prev - c.count) / prev) * 100)}%`;
    }
    return { key: c.stage, label: c.label, count: c.count, dropoffLabel };
  });

  return {
    signupCount: users.length,
    activatedCount: activated,
    activationDef: ACTIVATION_DEF,
    stages,
  };
}

export function computeMetrics(
  users: UserRow[],
  conversations: ConversationRow[],
  now: Date = new Date(),
): UserMetrics[] {
  // Group conversations by user_id
  const convByUser = new Map<string, ConversationRow[]>();
  for (const c of conversations) {
    const list = convByUser.get(c.user_id) ?? [];
    list.push(c);
    convByUser.set(c.user_id, list);
  }

  return users.map((user) => {
    const convs = convByUser.get(user.id) ?? [];

    // Domain engagement: count per domain_leader
    const domainCounts: Record<string, number> = {};
    for (const c of convs) {
      domainCounts[c.domain_leader] = (domainCounts[c.domain_leader] ?? 0) + 1;
    }

    // Session frequency: count per day
    const sessionsByDay: Record<string, number> = {};
    for (const c of convs) {
      const day = c.created_at.slice(0, 10);
      sessionsByDay[day] = (sessionsByDay[day] ?? 0) + 1;
    }

    // Error rate
    const failedCount = convs.filter((c) => c.status === "failed").length;
    const errorRate = convs.length > 0 ? failedCount / convs.length : 0;

    // Time-to-first-value
    let ttfvDays: number | null = null;
    if (convs.length > 0) {
      const earliest = convs.reduce((min, c) =>
        c.created_at < min.created_at ? c : min,
      );
      const signupMs = new Date(user.created_at).getTime();
      const firstSessionMs = new Date(earliest.created_at).getTime();
      ttfvDays = Math.round((firstSessionMs - signupMs) / MS_PER_DAY);
    }

    // Churn signal
    let daysSinceLastSession: number | null = null;
    let churning = true; // Default: no sessions = churning
    if (convs.length > 0) {
      const latest = convs.reduce((max, c) =>
        c.created_at > max.created_at ? c : max,
      );
      const lastMs = new Date(latest.created_at).getTime();
      daysSinceLastSession = Math.round((now.getTime() - lastMs) / MS_PER_DAY);
      churning = daysSinceLastSession >= CHURN_THRESHOLD_DAYS;
    }

    return {
      userId: user.id,
      email: user.email,
      domainCounts,
      domainCount: Object.keys(domainCounts).length,
      totalSessions: convs.length,
      sessionsByDay,
      // Filter to legacy {date, count} rows — rich rows from
      // appendKbSyncRow (#4224) lack the .count field the sparkline
      // arithmetic depends on; including them produces NaN points.
      kbHistory: Array.isArray(user.kb_sync_history)
        ? user.kb_sync_history.filter(
            (r): r is { date: string; count: number } =>
              typeof r === "object" &&
              r !== null &&
              typeof (r as { date?: unknown }).date === "string" &&
              typeof (r as { count?: unknown }).count === "number",
          )
        : [],
      ttfvDays,
      errorRate,
      churning,
      daysSinceLastSession,
    };
  });
}

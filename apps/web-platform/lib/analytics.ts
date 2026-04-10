export interface UserRow {
  id: string;
  email: string;
  created_at: string;
  kb_sync_history: Array<{ date: string; count: number }>;
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
      kbHistory: Array.isArray(user.kb_sync_history)
        ? user.kb_sync_history
        : [],
      ttfvDays,
      errorRate,
      churning,
      daysSinceLastSession,
    };
  });
}

"use client";

// feat-nav-attention-badges — a count badge on the Dashboard left-nav item
// showing how many conversations need the founder's decision/attention.
//
// "Needs attention/decision" = conversation status IN ('waiting_for_user',
// 'failed') — exactly the two the app already labels "Needs your decision" /
// "Needs attention" (STATUS_LABELS in lib/types.ts; RAIL_STATUS_LABEL in
// conversations-rail.tsx).
//
// Unlike the Inbox/Workstream badges, conversations are NOT on SWR (use
// Conversations is a Supabase-realtime hook), so the badge cannot share one
// cache with the list. It runs its own lightweight `head` count query scoped to
// the ACTIVE workspace's repo — the SAME scope the dashboard list uses
// (repo_url + workspace_id + archived_at IS NULL) so the count matches what the
// list shows. It reuses the cached active-repo fetch (swrKeys.workspaceActiveRepo)
// so that request still dedups with the dashboard page.

import useSWR from "swr";
import { createClient } from "@/lib/supabase/client";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";
import {
  NavCountBadge,
  useNavAttentionCount,
} from "@/components/dashboard/nav-count-badge";

// Statuses the founder needs to act on — the single source of the predicate.
const ATTENTION_STATUSES = ["waiting_for_user", "failed"] as const;

export async function fetchConversationAttentionCount([, repoUrl, workspaceId]: readonly [
  string,
  string,
  string,
]): Promise<number> {
  const supabase = createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return 0;
  // Scope EXACTLY as the dashboard list (hooks/use-conversations.ts): active
  // repo + active workspace + not archived. RLS additionally scopes to the
  // owner, matching the list. `head: true` returns only the count.
  const { count, error } = await supabase
    .from("conversations")
    .select("id", { count: "exact", head: true })
    .eq("repo_url", repoUrl)
    .eq("workspace_id", workspaceId)
    .is("archived_at", null)
    .in("status", ATTENTION_STATUSES);
  // Throw so SWR routes to `error` and the badge omits (never a false "0")
  // rather than caching a wrong 0 from a failed query.
  if (error) throw new Error(`conversation attention count: ${error.message}`);
  return count ?? 0;
}

export function ConversationsNavBadge({ collapsed }: { collapsed: boolean }) {
  const { data: activeRepo } = useSWR(
    swrKeys.workspaceActiveRepo(),
    jsonFetcher<{ repoUrl?: string | null; workspaceId?: string | null }>,
  );
  const repoUrl = activeRepo?.repoUrl ?? null;
  const workspaceId = activeRepo?.workspaceId ?? null;
  // Gate the count until the active repo+workspace resolves (a disconnected repo
  // → no key → no count, and the dashboard shows its empty state anyway).
  const key =
    repoUrl && workspaceId
      ? swrKeys.dashboardConversationAttention(repoUrl, workspaceId)
      : null;

  const count = useNavAttentionCount(
    key,
    fetchConversationAttentionCount,
    (n) => n,
    "dashboard-nav-badge",
  );
  if (count === null || count === 0) return null;

  return (
    <NavCountBadge
      count={count}
      collapsed={collapsed}
      testId="dashboard-nav-badge"
      label={`${count} ${count === 1 ? "conversation needs" : "conversations need"} your attention`}
    />
  );
}

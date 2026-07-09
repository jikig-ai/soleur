import { redirect } from "next/navigation";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { computeMetrics, computeFunnel } from "@/lib/analytics";
import type { UserRow, ConversationRow } from "@/lib/analytics";
import { AnalyticsDashboard } from "@/components/analytics/analytics-dashboard";
import { AdminAnalyticsAuthzRefresh } from "@/components/analytics/admin-analytics-authz-refresh";

export default async function AdminAnalyticsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Inline admin check — fail closed if env var is missing
  const isAdmin =
    process.env.ADMIN_USER_IDS?.split(",").includes(user.id) ?? false;
  if (!isAdmin) {
    redirect("/dashboard");
  }

  const service = createServiceClient();

  // Fetch all users and conversations in parallel
  const [usersResult, convsResult] = await Promise.all([
    service
      .from("users")
      .select("id, email, created_at, kb_sync_history, workspace_status")
      .order("created_at", { ascending: true }),
    service
      .from("conversations")
      .select("user_id, domain_leader, status, created_at")
      .order("created_at", { ascending: true })
      .limit(10_000),
  ]);

  if (usersResult.error || convsResult.error) {
    console.error(
      "[analytics] query failed:",
      usersResult.error ?? convsResult.error,
    );
    return (
      <div className="mx-auto max-w-6xl px-6 py-8 flex flex-col items-center justify-center min-h-[400px] gap-4">
        <p className="text-red-400">Failed to load analytics data. Please try again.</p>
        <a
          href="/dashboard/admin/analytics"
          className="text-amber-500 underline hover:text-amber-400"
        >
          Retry
        </a>
      </div>
    );
  }

  const users = (usersResult.data ?? []) as UserRow[];
  const conversations = (convsResult.data ?? []) as ConversationRow[];
  // The conversations query is capped at 10k rows; past that the funnel's
  // first-conversation/activated counts undercount silently. Warn so the gap is
  // discoverable (harmless at current scale; revisit with pagination if hit).
  if (conversations.length === 10_000) {
    console.warn(
      "[analytics] conversations query hit the 10k row cap — funnel counts may undercount.",
    );
  }
  const metrics = computeMetrics(users, conversations);
  const funnel = computeFunnel(users, conversations);

  return (
    <>
      {/* GAP H (ADR-067 staleTimes): re-validate admin authz on every entry,
          including a warm Router-Cache restore, so a de-provisioned admin never
          rides the cached all-tenant RSC. */}
      <AdminAnalyticsAuthzRefresh />
      <AnalyticsDashboard metrics={metrics} funnel={funnel} />
    </>
  );
}

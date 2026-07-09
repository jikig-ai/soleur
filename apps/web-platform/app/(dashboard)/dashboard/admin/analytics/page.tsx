import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AnalyticsDashboardLoader } from "@/components/analytics/analytics-dashboard-loader";

export default async function AdminAnalyticsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Inline admin check — fail closed if env var is missing. This gates the
  // FIRST (uncached) render as defense-in-depth.
  const isAdmin =
    process.env.ADMIN_USER_IDS?.split(",").includes(user.id) ?? false;
  if (!isAdmin) {
    redirect("/dashboard");
  }

  // GAP H (ADR-067 staleTimes amendment): the all-tenant analytics data (every
  // user's email + all conversations) is NO LONGER baked into this RSC. With
  // `staleTimes.dynamic = 30` the client Router Cache reuses a route's RSC
  // across soft navigations WITHOUT re-running the server `isAdmin` gate — so
  // baking all-tenant data into the RSC would let a de-provisioned admin (with a
  // warm cache) soft-navigate back and briefly see the stale all-tenant payload
  // before any re-validation. Instead the data is fetched client-side via SWR
  // from the admin-gated `/api/admin/analytics` route, whose `isAdmin` gate
  // re-runs on EVERY fetch (through middleware): a de-provisioned admin gets a
  // fresh 403 and nothing sensitive is ever in a cacheable RSC. The server gate
  // above still protects the first render.
  return <AnalyticsDashboardLoader />;
}

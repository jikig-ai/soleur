import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { computeMetrics, computeFunnel } from "@/lib/analytics";
import type { UserRow, ConversationRow } from "@/lib/analytics";

// GAP H (ADR-067 staleTimes amendment): admin-gated analytics data endpoint.
// The all-tenant analytics data moved OFF the `admin/analytics` RSC (which the
// Router Cache reuses across soft navigations without re-running the server
// authz gate) and onto this route, whose `isAdmin` gate re-runs on EVERY fetch.
// A de-provisioned admin gets a fresh 403 here — nothing sensitive is ever baked
// into a cacheable RSC. Uses the RLS-bypassing service client (all-tenant read),
// but only AFTER the getUser() + ADMIN_USER_IDS gate.
export async function GET(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const isAdmin =
    process.env.ADMIN_USER_IDS?.split(",").includes(user.id) ?? false;
  if (!isAdmin) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }

  // Optional cohort scope (#8880): `?cohort=alpha` narrows users to
  // cohort_key matches and conversations to those users' ids — applied
  // SERVER-SIDE before the 10k cap so a filtered cohort can never be
  // truncated away by other tenants' rows.
  const cohortParam = new URL(request.url).searchParams.get("cohort");
  const cohort =
    cohortParam && cohortParam.trim().length > 0
      ? cohortParam.trim().toLowerCase()
      : null;

  const service = createServiceClient();
  const convsBase = () =>
    service
      .from("conversations")
      .select("user_id, domain_leader, status, created_at")
      .order("created_at", { ascending: true });

  let usersResult, convsResult;
  if (cohort) {
    // Scoped: conversations must filter on the cohort's user ids, so the users
    // query resolves first (sequential is intrinsic here, not a regression).
    const usersQuery = service
      .from("users")
      .select(
        "id, email, created_at, kb_sync_history, workspace_status, cohort_key",
      )
      .order("created_at", { ascending: true })
      .eq("cohort_key", cohort);
    usersResult = await usersQuery;
    if (usersResult.error) {
      console.error("[analytics] users query failed:", usersResult.error);
      return NextResponse.json({ error: "query_failed" }, { status: 500 });
    }
    const cohortIds = ((usersResult.data ?? []) as UserRow[]).map((u) => u.id);
    // Empty member set still applies .in() — PostgREST maps in.() to = ANY('{}'),
    // zero rows, fail-closed: an unscoped leak into a cohort report is impossible.
    convsResult = await convsBase().in("user_id", cohortIds).limit(10_000);
  } else {
    // Unscoped default: keep the original parallel fan-out.
    [usersResult, convsResult] = await Promise.all([
      service
        .from("users")
        .select(
          "id, email, created_at, kb_sync_history, workspace_status, cohort_key",
        )
        .order("created_at", { ascending: true }),
      convsBase().limit(10_000),
    ]);
    if (usersResult.error) {
      console.error("[analytics] users query failed:", usersResult.error);
      return NextResponse.json({ error: "query_failed" }, { status: 500 });
    }
  }
  const users = (usersResult.data ?? []) as UserRow[];

  if (convsResult.error) {
    // Mirror the failure so an operator sees it without SSH; the client renders
    // a retry affordance on the non-200.
    console.error("[analytics] conversations query failed:", convsResult.error);
    return NextResponse.json({ error: "query_failed" }, { status: 500 });
  }

  const conversations = (convsResult.data ?? []) as ConversationRow[];
  // The conversations query is capped at 10k rows; past that the funnel's
  // first-conversation/activated counts undercount silently. Warn so the gap is
  // discoverable (harmless at current scale; revisit with pagination if hit).
  if (conversations.length === 10_000) {
    console.warn(
      "[analytics] conversations query hit the 10k row cap — funnel counts may undercount.",
    );
  }

  return NextResponse.json({
    metrics: computeMetrics(users, conversations),
    funnel: computeFunnel(users, conversations),
  });
}

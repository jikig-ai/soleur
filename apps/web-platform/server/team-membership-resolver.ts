import { isTeamWorkspaceInviteEnabled } from "@/lib/feature-flags/server";
import { getCurrentOrganizationId } from "@/server/workspace-resolver";

// Server-only resolver for the /dashboard/settings/team membership page.
// Factored out of the page component so AC-A's flag-OFF → notFound() behavior
// is unit-testable without spinning up a Next.js render harness.

export interface TeamMembershipRow {
  userId: string;
  email: string;
  role: "owner" | "member";
  addedAt: string; // membership.created_at
  isSelf: boolean;
}

export interface TeamMembershipPageData {
  organizationId: string;
  workspaceId: string;
  currentUserId: string;
  members: TeamMembershipRow[];
}

export type TeamMembershipPageResult =
  | { ok: true; data: TeamMembershipPageData }
  | { ok: false; reason: "not-found" | "no-org" | "no-membership" };

// Minimal structural shapes — we don't pull SupabaseClient<Database> generics
// across the resolver boundary; the page passes the real client at runtime
// and the test passes mocked thenables (same shape as workspace-resolver.ts).
interface AuthClient {
  auth: {
    getUser: () => Promise<{
      data: { user: { id: string; app_metadata?: Record<string, unknown> } | null };
      error: unknown;
    }>;
  };
}

interface ServiceClient {
  from: (table: string) => unknown;
}

interface MembershipRow {
  workspace_id: string;
  user_id: string;
  role: "owner" | "member";
  created_at: string;
}

interface UserRow {
  id: string;
  email: string | null;
}

export async function resolveTeamMembershipPageData(
  supabase: AuthClient,
  service: ServiceClient,
): Promise<TeamMembershipPageResult> {
  const userResp = await supabase.auth.getUser();
  const user = userResp.data?.user;
  if (!user) return { ok: false, reason: "not-found" };

  const orgId = getCurrentOrganizationId({
    user: { id: user.id, app_metadata: user.app_metadata as never },
  });
  if (!orgId) return { ok: false, reason: "no-org" };

  // 2-key gate per AC-F. When false, surface as not-found so the page calls
  // notFound() → HTTP 404 (AC-A: never 403, never empty 200).
  if (!isTeamWorkspaceInviteEnabled(orgId)) {
    return { ok: false, reason: "not-found" };
  }

  // Resolve the membership rows for the current org. We query through service
  // role because the page needs every member's email, and email lives on
  // auth.users which the RLS-bound anon client can't read for peers.
  const membershipChain = service.from("workspace_members") as {
    select: (cols: string) => {
      eq: (col: string, val: string) => {
        order: (
          col: string,
          opts?: { ascending?: boolean },
        ) => Promise<{ data: MembershipRow[] | null; error: unknown }>;
      };
    };
  };

  // Org → workspaces. For now we collapse to the user's primary workspace
  // (N2 invariant: solo users have workspace_id === user_id). Multi-workspace
  // orgs land in #2778 (post-MVP projects refactor).
  // We resolve via current_organization_id → workspaces → members.
  // Query: workspaces.organization_id = orgId, then their members.
  const wsChain = service.from("workspaces") as {
    select: (cols: string) => {
      eq: (
        col: string,
        val: string,
      ) => Promise<{ data: { id: string }[] | null; error: unknown }>;
    };
  };
  const wsResp = await wsChain.select("id").eq("organization_id", orgId);
  if (wsResp.error || !wsResp.data || wsResp.data.length === 0) {
    return { ok: false, reason: "no-membership" };
  }
  const workspaceId = wsResp.data[0].id;

  const membersResp = await membershipChain
    .select("workspace_id, user_id, role, created_at")
    .eq("workspace_id", workspaceId)
    .order("created_at", { ascending: true });
  if (membersResp.error || !membersResp.data) {
    return { ok: false, reason: "no-membership" };
  }
  const rows = membersResp.data;
  if (rows.length === 0) {
    return { ok: false, reason: "no-membership" };
  }

  const userIds = rows.map((r) => r.user_id);
  const usersChain = service.from("users") as {
    select: (cols: string) => {
      in: (
        col: string,
        vals: string[],
      ) => Promise<{ data: UserRow[] | null; error: unknown }>;
    };
  };
  const usersResp = await usersChain.select("id, email").in("id", userIds);
  const emailByUserId = new Map<string, string>();
  for (const row of usersResp.data ?? []) {
    if (row.email) emailByUserId.set(row.id, row.email);
  }

  const members: TeamMembershipRow[] = rows.map((r) => ({
    userId: r.user_id,
    email: emailByUserId.get(r.user_id) ?? "",
    role: r.role,
    addedAt: r.created_at,
    isSelf: r.user_id === user.id,
  }));

  return {
    ok: true,
    data: {
      organizationId: orgId,
      workspaceId,
      currentUserId: user.id,
      members,
    },
  };
}

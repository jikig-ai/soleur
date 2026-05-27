import { isTeamWorkspaceInviteEnabled, isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveCurrentOrganizationId } from "@/server/workspace-resolver";

// Server-only resolver for the /dashboard/settings/team membership page.
// Factored out of the page component so AC-A's flag-OFF → notFound() behavior
// is unit-testable without spinning up a Next.js render harness.

export interface TeamMembershipRow {
  userId: string;
  email: string;
  role: "owner" | "member";
  addedAt: string; // membership.created_at
  isSelf: boolean;
  delegationFromMe?: {
    id: string;
    dailyCapCents: number;
    todaySpentCents: number;
    active: boolean;
  };
  delegationToMe?: {
    id: string;
    grantorDisplayName: string;
    dailyCapCents: number;
    todaySpentCents: number;
  };
}

export interface TeamMembershipPageData {
  organizationId: string;
  organizationName: string | null;
  workspaceId: string;
  currentUserId: string;
  members: TeamMembershipRow[];
  byokDelegationsEnabled: boolean;
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

  const orgId = await resolveCurrentOrganizationId(user.id, service);
  if (!orgId) return { ok: false, reason: "no-org" };

  const orgNameResp = await (service.from("organizations") as {
    select: (cols: string) => {
      eq: (col: string, val: string) => {
        single: () => Promise<{ data: { name: string | null } | null; error: unknown }>;
      };
    };
  }).select("name").eq("id", orgId).single();
  const organizationName: string | null = orgNameResp.data?.name ?? null;

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isTeamWorkspaceInviteEnabled(orgId, identity))) {
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

  const byokEnabled = await isByokDelegationsEnabled(orgId, identity);

  let delegationsByGrantor = new Map<string, { id: string; grantee_user_id: string; daily_cap_cents: number }>();
  let delegationsByGrantee = new Map<string, { id: string; grantor_user_id: string; daily_cap_cents: number }>();

  if (byokEnabled) {
    const delegChain = service.from("byok_delegations") as {
      select: (cols: string) => {
        eq: (col: string, val: string) => {
          is: (col: string, val: null) => Promise<{ data: Array<{ id: string; grantor_user_id: string; grantee_user_id: string; daily_cap_cents: number }> | null; error: unknown }>;
        };
      };
    };
    const delegResp = await delegChain
      .select("id, grantor_user_id, grantee_user_id, daily_cap_cents")
      .eq("workspace_id", workspaceId)
      .is("revoked_at", null);
    for (const d of delegResp.data ?? []) {
      delegationsByGrantor.set(`${d.grantor_user_id}:${d.grantee_user_id}`, d);
      delegationsByGrantee.set(d.grantee_user_id, d);
    }
  }

  const members: TeamMembershipRow[] = rows.map((r) => {
    const row: TeamMembershipRow = {
      userId: r.user_id,
      email: emailByUserId.get(r.user_id) ?? "",
      role: r.role,
      addedAt: r.created_at,
      isSelf: r.user_id === user.id,
    };

    if (byokEnabled) {
      const fromMe = delegationsByGrantor.get(`${user.id}:${r.user_id}`);
      if (fromMe) {
        row.delegationFromMe = {
          id: fromMe.id,
          dailyCapCents: fromMe.daily_cap_cents,
          todaySpentCents: 0,
          active: true,
        };
      }
      const toMe = r.user_id === user.id ? delegationsByGrantee.get(user.id) : undefined;
      if (toMe) {
        const grantorEmail = emailByUserId.get(toMe.grantor_user_id) ?? "Unknown";
        row.delegationToMe = {
          id: toMe.id,
          grantorDisplayName: grantorEmail.split("@")[0],
          dailyCapCents: toMe.daily_cap_cents,
          todaySpentCents: 0,
        };
      }
    }

    return row;
  });

  return {
    ok: true,
    data: {
      organizationId: orgId,
      organizationName,
      workspaceId,
      currentUserId: user.id,
      members,
      byokDelegationsEnabled: byokEnabled,
    },
  };
}

import { getCurrentOrganizationId } from "@/server/workspace-resolver";

// Returns the user's full list of organization memberships with role + member
// count. Powers the dashboard OrgSwitcher (Phase 5.3) which hides itself when
// the list has 0 or 1 entries (AC-C).

export interface OrgMembershipSummary {
  organizationId: string;
  organizationName: string;
  workspaceId: string;
  role: "owner" | "member";
  memberCount: number;
  isCurrent: boolean;
}

interface AuthClient {
  auth: {
    getUser: () => Promise<{
      data: {
        user: {
          id: string;
          app_metadata?: Record<string, unknown>;
        } | null;
      };
      error: unknown;
    }>;
  };
}

interface ServiceClient {
  from: (table: string) => unknown;
}

interface MembershipRow {
  workspace_id: string;
  role: "owner" | "member";
}

interface WorkspaceRow {
  id: string;
  organization_id: string;
}

interface OrganizationRow {
  id: string;
  name: string | null;
}

interface MemberCountRow {
  workspace_id: string;
  user_id: string;
}

export async function resolveOrgMemberships(
  supabase: AuthClient,
  service: ServiceClient,
): Promise<OrgMembershipSummary[]> {
  const userResp = await supabase.auth.getUser();
  const user = userResp.data?.user;
  if (!user) return [];

  const currentOrgId = getCurrentOrganizationId({
    user: { id: user.id, app_metadata: user.app_metadata as never },
  });

  // 1. user's memberships → workspace_ids + role
  type MembershipsChain = {
    select: (cols: string) => {
      eq: (
        col: string,
        val: string,
      ) => Promise<{ data: MembershipRow[] | null; error: unknown }>;
    };
  };
  const membershipsResp = await (
    service.from("workspace_members") as MembershipsChain
  )
    .select("workspace_id, role")
    .eq("user_id", user.id);
  if (membershipsResp.error || !membershipsResp.data) return [];
  const memberships = membershipsResp.data;
  if (memberships.length === 0) return [];

  const workspaceIds = memberships.map((m) => m.workspace_id);

  // 2. workspaces → organization_id
  type WorkspacesChain = {
    select: (cols: string) => {
      in: (
        col: string,
        vals: string[],
      ) => Promise<{ data: WorkspaceRow[] | null; error: unknown }>;
    };
  };
  const workspacesResp = await (
    service.from("workspaces") as WorkspacesChain
  )
    .select("id, organization_id")
    .in("id", workspaceIds);
  if (workspacesResp.error || !workspacesResp.data) return [];
  const workspaces = workspacesResp.data;

  const orgIds = Array.from(new Set(workspaces.map((w) => w.organization_id)));

  // 3. organization names
  type OrgsChain = {
    select: (cols: string) => {
      in: (
        col: string,
        vals: string[],
      ) => Promise<{ data: OrganizationRow[] | null; error: unknown }>;
    };
  };
  const orgsResp = await (service.from("organizations") as OrgsChain)
    .select("id, name")
    .in("id", orgIds);
  const orgNameById = new Map<string, string | null>();
  for (const row of orgsResp.data ?? []) orgNameById.set(row.id, row.name);

  // 4. member counts per workspace (count(*) on workspace_members)
  type CountsChain = {
    select: (cols: string) => {
      in: (
        col: string,
        vals: string[],
      ) => Promise<{ data: MemberCountRow[] | null; error: unknown }>;
    };
  };
  const countsResp = await (
    service.from("workspace_members") as CountsChain
  )
    .select("workspace_id, user_id")
    .in("workspace_id", workspaceIds);
  const countByWorkspace = new Map<string, number>();
  for (const row of countsResp.data ?? []) {
    countByWorkspace.set(
      row.workspace_id,
      (countByWorkspace.get(row.workspace_id) ?? 0) + 1,
    );
  }

  // 5. assemble summaries
  const workspaceById = new Map(workspaces.map((w) => [w.id, w]));
  const summaries: OrgMembershipSummary[] = memberships
    .map((m) => {
      const ws = workspaceById.get(m.workspace_id);
      if (!ws) return null;
      const orgName = orgNameById.get(ws.organization_id) ?? "Untitled";
      return {
        organizationId: ws.organization_id,
        organizationName: orgName,
        workspaceId: ws.id,
        role: m.role,
        memberCount: countByWorkspace.get(ws.id) ?? 1,
        isCurrent: ws.organization_id === currentOrgId,
      };
    })
    .filter((s): s is OrgMembershipSummary => s !== null);

  // If the JWT claim is absent (single-membership users; AC-FLOW1 default),
  // mark the first membership as current so the UI has a stable anchor.
  if (!summaries.some((s) => s.isCurrent) && summaries.length > 0) {
    summaries[0] = { ...summaries[0], isCurrent: true };
  }

  return summaries;
}

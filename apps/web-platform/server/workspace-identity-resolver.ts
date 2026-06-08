import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
import { isTeamWorkspaceInviteEnabled, type Identity } from "@/lib/feature-flags/server";

// Server-only resolver for the General settings page's workspace-identity
// controls (logo + rename) — #4916 follow-up.
//
// Why a SEPARATE resolver from resolveTeamMembershipPageData: the Team page is
// gated behind isTeamWorkspaceInviteEnabled, so the logo + rename controls that
// used to live there were UNREACHABLE when the flag is OFF. Relocating them to
// the always-present General page fixes that reachability defect — so this
// resolver deliberately does NOT consult any feature flag (AC7).
//
// It resolves the SAME workspace the upload route writes to: plain
// resolveCurrentWorkspaceId (claim → solo fallback), NOT a self-healing variant,
// so the General page reads exactly the row the POST persists to.

export interface WorkspaceIdentity {
  workspaceId: string;
  organizationId: string | null;
  organizationName: string | null;
  isOwner: boolean;
  hasLogo: boolean;
  /**
   * Whether the rename control should render. The rename ROUTE
   * (POST /api/workspace/rename) is gated behind isTeamWorkspaceInviteEnabled
   * and 404s when off, so the UI must match — otherwise a flag-off owner sees an
   * enabled Rename control that fails on submit. The LOGO is intentionally NOT
   * flag-gated (its route has no flag gate; logo reachability is the reason the
   * controls moved to the always-present General page). #4916.
   */
  canRename: boolean;
}

interface AuthClient {
  auth: {
    getUser: () => Promise<{
      data: { user: { id: string } | null };
      error: unknown;
    }>;
  };
  // supabase-js .rpc() returns a thenable PostgrestFilterBuilder (not a bare
  // Promise) — PromiseLike accepts both it and the test's async stub.
  rpc: (
    name: string,
    args: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: unknown }>;
}

interface ServiceClient {
  from: (table: string) => unknown;
}

type MaybeSingleChain<T> = {
  select: (cols: string) => MaybeSingleChain<T>;
  eq: (col: string, val: string) => MaybeSingleChain<T>;
  maybeSingle: () => Promise<{ data: T | null; error: unknown }>;
};

export async function resolveWorkspaceIdentityForSettings(
  supabase: AuthClient,
  service: ServiceClient,
): Promise<WorkspaceIdentity | null> {
  const userResp = await supabase.auth.getUser();
  const user = userResp.data?.user;
  if (!user) return null;

  // The SAME id the upload route's persist targets (AC: read == write target).
  const workspaceId = await resolveCurrentWorkspaceId(user.id, service);

  const wsChain = service.from("workspaces") as MaybeSingleChain<{
    organization_id: string | null;
    logo_path: string | null;
  }>;
  const wsResp = await wsChain
    .select("organization_id, logo_path")
    .eq("id", workspaceId)
    .maybeSingle();
  // No workspace row (also the silent-persistence bug signal) → render nothing
  // rather than a half-populated control.
  if (wsResp.error || !wsResp.data) return null;
  const organizationId = wsResp.data.organization_id;
  const hasLogo = wsResp.data.logo_path != null;

  let organizationName: string | null = null;
  // The rename route is flag-gated; mirror that so the UI doesn't show an
  // enabled control that 404s. Logo stays flag-free (resolved above).
  let canRename = false;
  if (organizationId) {
    const orgChain = service.from("organizations") as MaybeSingleChain<{
      name: string | null;
    }>;
    const orgResp = await orgChain
      .select("name")
      .eq("id", organizationId)
      .maybeSingle();
    organizationName = orgResp.data?.name ?? null;

    const identity: Identity = { userId: user.id, role: "prd", orgId: organizationId };
    canRename = await isTeamWorkspaceInviteEnabled(organizationId, identity);
  }

  // Owner gate via the SECURITY DEFINER RPC (GRANT authenticated) — same gate the
  // upload route uses, so the General control's enabled/disabled state matches
  // what the POST will accept (AC8).
  const ownerRes = await supabase.rpc("is_workspace_owner", {
    p_workspace_id: workspaceId,
    p_user_id: user.id,
  });
  const isOwner = ownerRes.data === true;

  return { workspaceId, organizationId, organizationName, isOwner, hasLogo, canRename };
}

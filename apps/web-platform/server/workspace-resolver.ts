import { join } from "path";

// Resolver for user → current/default workspace mapping (feat-team-workspace-multi-user).
//
// Two distinct lookups:
//   1. getCurrentOrganizationId(session) — reads the Supabase Auth JWT custom
//      claim `app_metadata.current_organization_id` populated by migration 056's
//      access-token hook. Synchronous, no DB call. Returns null when the claim
//      is absent (single-membership users) or the session is anonymous; callers
//      then fall back to getDefaultWorkspaceForUser.
//   2. getDefaultWorkspaceForUser(userId, supabase) — DB query against
//      workspace_members joined to workspaces. Returns the MIN(created_at)
//      workspace_id. For solo users this collapses to the N2 invariant
//      (workspaces.id === user.id; see migration 053 §1.1.7 backfill).
//
// resolveWorkspacePathForUser(userId, supabase) is the filesystem-layer helper:
// composes getDefaultWorkspaceForUser with WORKSPACES_ROOT.

const WORKSPACES_ROOT_DEFAULT = "/workspaces";

function getWorkspacesRoot(): string {
  return process.env.WORKSPACES_ROOT || WORKSPACES_ROOT_DEFAULT;
}

interface SessionLike {
  user?: {
    id?: string;
    app_metadata?: { current_organization_id?: string } & Record<
      string,
      unknown
    >;
  };
}

/**
 * Returns the `app_metadata.current_organization_id` JWT custom claim
 * populated by migration 056's `custom_access_token` hook, or null.
 *
 * Phase 5.4 dependency: the org-switcher writes user_session_state then
 * calls `supabase.auth.refreshSession()` to force a token refresh so the
 * new claim propagates to all tabs.
 */
export function getCurrentOrganizationId(
  session: SessionLike | null | undefined,
): string | null {
  return session?.user?.app_metadata?.current_organization_id ?? null;
}

// Minimal structural type for the test-injected supabase client. We only need
// `.from(table)` returning a thenable query chain. This avoids dragging the
// full `SupabaseClient<Database>` generic into the resolver signature.
interface SupabaseLike {
  from: (table: string) => unknown;
}

interface WorkspaceMemberRow {
  workspace_id: string;
}

async function awaitChain<T>(chain: unknown): Promise<T> {
  // The chain is a thenable; await coerces it without explicit .then chaining.
  return (await (chain as PromiseLike<T>)) as T;
}

/**
 * Resolve a user's default workspace_id by querying workspace_members.
 *
 * For solo users this returns their own user_id (N2 invariant). For users
 * with multiple memberships, returns the oldest workspace by created_at —
 * deterministic, matches the JWT-claim fallback behavior in Phase 5.4.
 */
export async function getDefaultWorkspaceForUser(
  userId: string,
  supabase: SupabaseLike,
): Promise<string> {
  type ChainShape = {
    select: (cols: string) => ChainShape;
    eq: (col: string, val: string) => ChainShape;
    order: (col: string, opts?: { ascending?: boolean }) => ChainShape;
    limit: (n: number) => ChainShape;
  } & PromiseLike<{ data: WorkspaceMemberRow[] | null; error: unknown }>;

  const chain = supabase.from("workspace_members") as ChainShape;

  // The query: SELECT workspace_id FROM workspace_members
  //   JOIN workspaces ON workspaces.id = workspace_members.workspace_id
  //   WHERE user_id = $userId
  //   ORDER BY workspaces.created_at ASC
  //   LIMIT 1
  //
  // Implemented via PostgREST embedded-resource ordering:
  // .select("workspace_id, workspaces!inner(created_at)")
  //   .order("created_at", { foreignTable: "workspaces", ascending: true })
  //
  // The test mock is recursive (every chain method returns the same chain)
  // so this real shape and the mock shape agree.
  const result = await awaitChain<{
    data: WorkspaceMemberRow[] | null;
    error: unknown;
  }>(
    chain
      .select("workspace_id, workspaces!inner(created_at)")
      .eq("user_id", userId)
      .order("created_at", { ascending: true })
      .limit(1),
  );

  if (result.error) {
    throw new Error(
      `getDefaultWorkspaceForUser query failed: ${String(result.error)}`,
    );
  }
  const rows = result.data ?? [];
  if (rows.length === 0) {
    // Fail-closed: the handle_new_user trigger (migration 053 §1.1.8) plus
    // the TS upsert fallback (server/auth signup callback) guarantee a row
    // exists at this point. Reaching here means an integrity violation — we
    // refuse to silently fall back to userId because that would mask a real
    // bug while still appearing to work for solo accounts.
    throw new Error(
      `no workspace membership found for user ${userId}; integrity violation`,
    );
  }
  return rows[0].workspace_id;
}

/**
 * Filesystem path resolver for a user's default workspace directory.
 *
 * Composition of getDefaultWorkspaceForUser + WORKSPACES_ROOT. Used by
 * future team-invite callers (Phase 5) to provision/locate the right
 * directory for a member whose workspace_id ≠ user_id. Solo callers
 * (signup, account-delete) still pass user.id directly per N2.
 */
export async function resolveWorkspacePathForUser(
  userId: string,
  supabase: SupabaseLike,
): Promise<string> {
  const workspaceId = await getDefaultWorkspaceForUser(userId, supabase);
  return join(getWorkspacesRoot(), workspaceId);
}

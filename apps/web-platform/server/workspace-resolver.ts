import { join } from "path";

// Resolver for user → current/default workspace mapping (feat-team-workspace-multi-user).
//
// Three lookups:
//   1. resolveCurrentOrganizationId(userId, supabase) — queries
//      user_session_state directly. Preferred over getCurrentOrganizationId.
//   2. getCurrentOrganizationId(session) — DEPRECATED. Reads
//      getUser().app_metadata which returns stored raw_app_meta_data, not
//      the JWT hook's injected claims.
//   3. getDefaultWorkspaceForUser(userId, supabase) — DB query against
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
 * @deprecated Reads from `getUser().app_metadata` which returns the stored
 * `raw_app_meta_data` — the JWT hook's `current_organization_id` claim is
 * NOT persisted there. Use `resolveCurrentOrganizationId` instead.
 */
export function getCurrentOrganizationId(
  session: SessionLike | null | undefined,
): string | null {
  return session?.user?.app_metadata?.current_organization_id ?? null;
}

/**
 * Queries `user_session_state` directly for the user's current org.
 *
 * The JWT hook (migration 060) injects `current_organization_id` into token
 * claims at mint time, but `supabase.auth.getUser()` returns the stored
 * `auth.users.raw_app_meta_data` which never includes hook modifications.
 * This function bypasses the JWT entirely and reads the source of truth.
 *
 * RLS: `user_session_state_owner_select` allows `auth.uid() = user_id`.
 */
export async function resolveCurrentOrganizationId(
  userId: string,
  supabase: SupabaseLike,
): Promise<string | null> {
  type ChainShape = {
    select: (cols: string) => ChainShape;
    eq: (col: string, val: string) => ChainShape;
    maybeSingle: () => ChainShape;
  } & PromiseLike<{
    data: { current_organization_id: string | null } | null;
    error: unknown;
  }>;

  const chain = supabase.from("user_session_state") as ChainShape;
  const result = await awaitChain<{
    data: { current_organization_id: string | null } | null;
    error: unknown;
  }>(chain.select("current_organization_id").eq("user_id", userId).maybeSingle());

  if (result.error || !result.data) return null;
  return result.data.current_organization_id;
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

interface WorkspaceMemberWorkspaceJoin {
  workspace_id: string;
  workspaces: { organization_id: string } | { organization_id: string }[] | null;
}

/**
 * Resolve the workspace_id a user belongs to inside a specific organization.
 *
 * Used by ws-handler at session-open time (Phase 5.5) to translate the JWT
 * custom claim `app_metadata.current_organization_id` (migration 060) into
 * the workspace_id required by `abortAllWorkspaceMemberSessions`. One join
 * + one filter; runs once per WS connection, then the result is cached on
 * the ClientSession.
 *
 * Returns null when the user has no membership in the named organization.
 * Defense-in-depth: the JWT claim is server-controlled (migration 060's
 * access-token hook reads `user_session_state` written by the RPC which
 * itself re-checks workspace_members), so this lookup is the third gate.
 */
export async function getWorkspaceForUserInOrganization(
  userId: string,
  organizationId: string,
  supabase: SupabaseLike,
): Promise<string | null> {
  type ChainShape = {
    select: (cols: string) => ChainShape;
    eq: (col: string, val: string) => ChainShape;
    limit: (n: number) => ChainShape;
  } & PromiseLike<{
    data: WorkspaceMemberWorkspaceJoin[] | null;
    error: unknown;
  }>;
  const chain = supabase.from("workspace_members") as ChainShape;
  const result = await (chain
    .select("workspace_id, workspaces!inner(organization_id)")
    .eq("user_id", userId)
    .eq("workspaces.organization_id", organizationId)
    .limit(1) as PromiseLike<{
    data: WorkspaceMemberWorkspaceJoin[] | null;
    error: unknown;
  }>);
  if (result.error) return null;
  const rows = result.data ?? [];
  if (rows.length === 0) return null;
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

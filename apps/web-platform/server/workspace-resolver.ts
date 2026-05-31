import { join } from "path";
import { reportSilentFallback } from "@/server/observability";

// Pure JWT-claim readers live in the client-safe `@/lib/session-claims` module
// (so "use client" components can read the active-workspace claim without
// bundling pino). Re-exported here for server callers' import-site stability.
export {
  getCurrentOrganizationId,
  getCurrentWorkspaceId,
} from "@/lib/session-claims";

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

  if (result.error) {
    reportSilentFallback(result.error, {
      feature: "workspace-resolver",
      op: "resolveCurrentOrganizationId",
      extra: { userId },
    });
    return null;
  }
  if (!result.data) return null;
  return result.data.current_organization_id;
}

// Minimal structural type for the test-injected supabase client. We only need
// `.from(table)` returning a thenable query chain. This avoids dragging the
// full `SupabaseClient<Database>` generic into the resolver signature.
interface SupabaseLike {
  from: (table: string) => unknown;
}

/**
 * Pure visibility predicate for the Settings "Members" tab
 * (feat-team-workspace-multi-user). The tab — and the dependent "Team
 * Activity" tab — render only when the user has a resolved current org AND the
 * team-workspace-invite flag evaluates ON for it. Extracted so the three-branch
 * decision is deterministically testable without the live Flagsmith/Supabase
 * dependency. The 2026-05-31 ops@jikigai.com disappearance was a live-state
 * question (invisible to code-grep); this predicate guards a future *code*
 * regression of the chain itself.
 */
export function shouldShowMembersTab(orgId: string | null, flagOn: boolean): boolean {
  return orgId != null && flagOn;
}

/**
 * True when the user has at least one `workspace_members` row.
 *
 * Used to distinguish a legitimately org-less identity (normal — stay silent)
 * from the integrity surface where a *member* resolves a null current org, in
 * which case org-gated UI (the Members + Team Activity tabs) silently vanishes
 * with no error. Fail-quiet on a query error: this is a diagnostic discriminator
 * on an already-degraded branch and must never itself block a render.
 *
 * RLS: `workspace_members` owner-select (`auth.uid() = user_id`).
 */
export async function userHasWorkspaceMembership(
  userId: string,
  supabase: SupabaseLike,
): Promise<boolean> {
  type ChainShape = {
    select: (cols: string) => ChainShape;
    eq: (col: string, val: string) => ChainShape;
    limit: (n: number) => ChainShape;
  } & PromiseLike<{ data: unknown[] | null; error: unknown }>;

  const chain = supabase.from("workspace_members") as ChainShape;
  const result = await awaitChain<{ data: unknown[] | null; error: unknown }>(
    chain.select("workspace_id").eq("user_id", userId).limit(1),
  );
  if (result.error) return false; // fail-quiet — never block render on a probe
  return (result.data?.length ?? 0) > 0;
}

/**
 * Resolve the user's CURRENT workspace id from `user_session_state`
 * (ADR-044). Source-of-truth read (preferred over the JWT claim, which can
 * be stale on an un-refreshed session). Falls back to the user's SOLO
 * workspace (`= userId` per ADR-038 N2) when the claim is null/absent or on
 * transient error — NEVER an arbitrary sibling workspace (the cross-tenant
 * read this whole feature is designed to prevent). Always returns a
 * workspace id; never null.
 *
 * RLS: `user_session_state_owner_select` allows `auth.uid() = user_id`, so a
 * tenant client reads only its own row.
 */
export async function resolveCurrentWorkspaceId(
  userId: string,
  supabase: SupabaseLike,
): Promise<string> {
  type ChainShape = {
    select: (cols: string) => ChainShape;
    eq: (col: string, val: string) => ChainShape;
    maybeSingle: () => ChainShape;
  } & PromiseLike<{
    data: { current_workspace_id: string | null } | null;
    error: unknown;
  }>;

  const chain = supabase.from("user_session_state") as ChainShape;
  const result = await awaitChain<{
    data: { current_workspace_id: string | null } | null;
    error: unknown;
  }>(chain.select("current_workspace_id").eq("user_id", userId).maybeSingle());

  if (result.error) {
    reportSilentFallback(result.error, {
      feature: "workspace-resolver",
      op: "resolveCurrentWorkspaceId",
      extra: { userId },
    });
    return userId; // fail to solo workspace, never a sibling
  }
  return result.data?.current_workspace_id ?? userId;
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

/**
 * Filesystem path for a workspace id: `<WORKSPACES_ROOT>/<workspace_id>`
 * (ADR-038 bwrap mount). Used by the push-reconcile fan-out (ADR-044) to
 * locate each matching workspace's directory directly from its id — no
 * `users.workspace_path` lookup. For backfilled solo workspaces this equals
 * the legacy `<WORKSPACES_ROOT>/<user_id>` path (N2: workspace_id == user_id).
 */
export function workspacePathForWorkspaceId(workspaceId: string): string {
  return join(getWorkspacesRoot(), workspaceId);
}

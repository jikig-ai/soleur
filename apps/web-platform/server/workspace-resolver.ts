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

// Mirrors workspace.ts:67 / api-usage.ts:46 — id-shape gate before any value
// flows into join() to build a bwrap mount path (ADR-038, CWE-22 #5344). The
// workspaceId column is typed `string | null`, not a validated UUID; this
// allowlist (8-4-4-4-12 hex) rejects every traversal/separator token (`..`,
// `/`, absolute prefix, newline-suffix) as a side-effect. `userId` is itself a
// UUID, so the solo-workspace case (workspaceId === userId, N2) passes.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
 * True when the user has at least one `workspace_members` row.
 *
 * Used to distinguish a legitimately org-less identity (normal — stay silent)
 * from the integrity surface where a *member* resolves a null current org, in
 * which case org-gated UI (the Members + Team Activity tabs) silently vanishes
 * with no error. Fail-quiet on a query error: this is a diagnostic discriminator
 * on an already-degraded branch and must never itself block a render.
 *
 * RLS: `workspace_members` peer-select (`members_select_peers` → `is_workspace_member(workspace_id, auth.uid())`,
 * migration 053). The explicit `.eq("user_id", userId)` self-scopes the probe to
 * the caller's own rows regardless — the boolean cannot be influenced cross-tenant.
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
  if (result.error) {
    // fail-quiet — never block render on a probe, but mirror to Sentry
    // (cq-silent-fallback-must-mirror-to-sentry) so a recurring membership-probe
    // failure on this integrity surface is visible, not pino-stdout-only.
    reportSilentFallback(result.error, {
      feature: "workspace-resolver",
      op: "userHasWorkspaceMembership",
      extra: { userId },
    });
    return false;
  }
  return (result.data?.length ?? 0) > 0;
}

/**
 * feat-invite-accept-membership-byok (#4715). True when the user is a member of
 * a workspace they do NOT own — i.e. a shared workspace they were invited into.
 * Per the N2 invariant (migration 053), a solo user's workspace id equals their
 * user id, so a `workspace_members` row whose `workspace_id !== userId` is a
 * genuine shared membership.
 *
 * Drives the dashboard NoApiKeyBanner copy: a keyless SHARED member must see the
 * "ask your owner to share a key, or add your own" joiner copy — not the solo
 * "buy a separate paid Anthropic account" dead-end. Fail-quiet to `false`
 * (treat as solo) on a probe error so a transient failure degrades to the
 * existing copy rather than blocking the render — same posture as
 * `userHasWorkspaceMembership`.
 *
 * `userId` is the SESSION-derived id at the call site (IDOR guard preserved);
 * the `.eq("user_id", userId)` self-scopes the probe regardless of RLS.
 */
export async function userIsSharedWorkspaceMember(
  userId: string,
  supabase: SupabaseLike,
): Promise<boolean> {
  type ChainShape = {
    select: (cols: string) => ChainShape;
    eq: (col: string, val: string) => ChainShape;
  } & PromiseLike<{
    data: { workspace_id: string }[] | null;
    error: unknown;
  }>;

  const chain = supabase.from("workspace_members") as ChainShape;
  const result = await awaitChain<{
    data: { workspace_id: string }[] | null;
    error: unknown;
  }>(chain.select("workspace_id").eq("user_id", userId));
  if (result.error) {
    // fail-quiet — degrade to solo copy, but mirror to Sentry
    // (cq-silent-fallback-must-mirror-to-sentry); the sibling resolvers in this
    // file do the same. A recurring probe failure is the integrity surface this
    // feature exists to surface, so it must not be invisible.
    reportSilentFallback(result.error, {
      feature: "workspace-resolver",
      op: "userIsSharedWorkspaceMember",
      extra: { userId },
    });
    return false;
  }
  // INVARIANT: this id-equality test assumes an owner always holds the
  // self-referential membership row (workspace_id === user_id, the N2 invariant
  // from migration 053). If a future team-workspace flow mints a workspace with
  // a fresh gen_random_uuid() id, its OWNER would get a row where
  // workspace_id !== user_id and be misclassified as a shared member — that
  // flow must classify by role/ownership, not id-equality. See #2778.
  return (result.data ?? []).some((r) => r.workspace_id !== userId);
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

/**
 * Fail-loud sibling of {@link resolveCurrentWorkspaceId}: read the user's
 * CURRENT workspace id from `user_session_state.current_workspace_id` (ADR-044
 * source-of-truth) and return it, or `null` when the row is absent / the column
 * is null.
 *
 * Unlike `resolveCurrentWorkspaceId` this NEVER falls back to `userId` (the
 * solo workspace) and NEVER swallows a read error. Callers here WRITE the
 * resolved id as a durable `conversations.workspace_id` / slot `p_workspace_id`
 * (a cross-tenant boundary): a silent solo-fallback to the caller's own id —
 * the exact pattern #5256 removed from the resume-rebind path — could bind one
 * tenant's write into another's workspace. So the fail-loud decision is centralized in
 * the caller's durable resolver (`resolveUserWorkspaceBinding`): this reader
 * returns `null` on an absent binding and THROWS on a DB read error, letting
 * the resolver distinguish the two (Sentry op `unresolvable` vs `db-read`) and
 * abort honestly.
 *
 * RLS: `user_session_state_owner_select` allows `auth.uid() = user_id`, so a
 * tenant client reads only its own row.
 */
export async function readWorkspaceIdFromDb(
  userId: string,
  supabase: SupabaseLike,
): Promise<string | null> {
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
    // Do NOT swallow — the resolver owns the fail-loud Sentry mirror + abort
    // and reports this as op `db-read`. Returning null here would collapse a
    // transient read failure into "user genuinely unbound".
    throw result.error instanceof Error
      ? result.error
      : new Error(String(result.error));
  }
  return result.data?.current_workspace_id ?? null; // null, never userId
}

interface WorkspaceMemberRow {
  workspace_id: string;
}

/**
 * Resolve the calling user's KB filesystem root for their ACTIVE workspace
 * (ADR-044 read-path cutover, #4543). The KB lives on disk at
 * `<WORKSPACES_ROOT>/<active_workspace_id>/knowledge-base`; connectivity and
 * readiness are gated on the ACTIVE workspace — NEVER the caller's own `users`
 * row. For an invited member viewing a workspace they do not own, the caller's
 * own row is the empty solo row, so reading it is the exact #4543 dual-ownership
 * bug that 404s the KB ("No Project Connected") for members.
 *
 * Mirrors the canonical `app/api/workspace/active-repo` resolution exactly:
 *   1. resolve `current_workspace_id` (→ solo fallback, never a sibling);
 *   2. J5 self-heal — a non-solo claim the caller is no longer a member of
 *      falls back to the solo workspace (read-only; no corrective write on a
 *      GET, unlike active-repo's badge self-heal);
 *   3. gate connectivity on the active workspace's `workspaces.repo_status`;
 *   4. gate readiness on the active workspace OWNER's `users.workspace_status`
 *      (resolved via `organizations.owner_user_id`). For a solo caller the
 *      owner IS the caller, so this is a byte-identical own-row read.
 *
 * Returns a discriminated result mirroring the legacy KB-route status contract
 * (404 = no repo / not connected, 503 = not ready) so each route preserves the
 * exact response the client hook (`use-kb-layout-state.tsx`) discriminates.
 */
export type ActiveWorkspaceKbAccess =
  | { ok: false; status: 404 | 503 }
  | {
      ok: true;
      activeWorkspaceId: string;
      workspacePath: string;
      kbRoot: string;
      repoStatus: string;
    };

interface WorkspaceRepoRow {
  repo_status: string | null;
  organization_id: string | null;
}

// Shared shape for the single-row reads this resolver issues (collapses the
// four otherwise-identical inline `& PromiseLike<...>` chain casts). Mirrors
// the structural-mock convention the rest of this file uses (SupabaseLike).
type MaybeSingleChain<T> = {
  select: (cols: string) => MaybeSingleChain<T>;
  eq: (col: string, val: string) => MaybeSingleChain<T>;
  maybeSingle: () => MaybeSingleChain<T>;
} & PromiseLike<{ data: T | null; error: unknown }>;

/**
 * Resolve the caller's ACTIVE workspace id (ADR-044), self-healing a stale
 * non-member claim back to the SOLO workspace (fail-closed — never a sibling).
 *
 * This is steps 1-2 of `resolveActiveWorkspaceKbRoot`, extracted so the
 * Concierge document resolver and the agent sandbox cwd
 * (`fetchUserWorkspacePath`) resolve the SAME workspace the UI KB file tree
 * renders from. Without sharing this resolution, the agent goes blind to the
 * document the user has open — the agent-native parity bug (#4543 class) this
 * resolver exists to prevent.
 *
 * RLS: `user_session_state` + `workspace_members` reads are self-scoped via
 * `.eq("user_id", userId)`; a tenant client cannot influence the result
 * cross-tenant, and the non-member fallback is unconditionally solo.
 */
export async function resolveActiveWorkspaceIdWithMembership(
  userId: string,
  supabase: SupabaseLike,
): Promise<string> {
  // 1. Active workspace id — claim → solo fallback (never a sibling).
  let activeWorkspaceId = await resolveCurrentWorkspaceId(userId, supabase);

  // 2. J5 self-heal parity: a non-solo claim the caller is no longer a member
  //    of must NOT read the sibling's workspace. Fall back to solo (read-only —
  //    the active-repo route's corrective set_current_workspace_id write is for
  //    the badge; a GET / agent dispatch must stay side-effect-free).
  if (activeWorkspaceId !== userId) {
    const memberChain = supabase.from("workspace_members") as MaybeSingleChain<{
      user_id: string;
    }>;
    const membership = await awaitChain<{
      data: { user_id: string } | null;
      error: unknown;
    }>(
      memberChain
        .select("user_id")
        .eq("workspace_id", activeWorkspaceId)
        .eq("user_id", userId)
        .maybeSingle(),
    );
    // A transient probe error must page (cq-silent-fallback-must-mirror-to-sentry,
    // matching the sibling resolvers in this file) — but it still fails CLOSED to
    // solo, never the sibling. A clean `!membership.data` is the legitimate
    // non-member case (no mirror).
    if (membership.error) {
      reportSilentFallback(membership.error, {
        feature: "workspace-resolver",
        op: "resolveActiveWorkspaceKbRoot.membership-probe",
        extra: { userId, activeWorkspaceId },
      });
    }
    if (membership.error || !membership.data) {
      activeWorkspaceId = userId; // never the sibling
    }
  }
  return activeWorkspaceId;
}

/**
 * The on-disk workspace path for the caller's ACTIVE workspace
 * (`<WORKSPACES_ROOT>/<active_workspace_id>`). This is the path the UI KB file
 * tree renders from (`resolveActiveWorkspaceKbRoot`). The Concierge document
 * resolver and the agent sandbox cwd MUST use this — NOT the legacy
 * `users.workspace_path` column, which is stale/empty for invited members and
 * for users provisioned after the ADR-044 `users → workspaces` relocation
 * (#4559). Always returns a path (the active-id resolution fails closed to
 * solo), never throws "not provisioned".
 */
export async function resolveActiveWorkspacePath(
  userId: string,
  supabase: SupabaseLike,
): Promise<string> {
  const activeWorkspaceId = await resolveActiveWorkspaceIdWithMembership(
    userId,
    supabase,
  );
  return workspacePathForWorkspaceId(activeWorkspaceId);
}

export async function resolveActiveWorkspaceKbRoot(
  userId: string,
  supabase: SupabaseLike,
): Promise<ActiveWorkspaceKbAccess> {
  // 1-2. Active workspace id (claim → solo fallback) with the J5 membership
  //      self-heal — shared with the Concierge/agent workspace-path resolver so
  //      both read the identical fail-closed source (ADR-044 parity).
  const activeWorkspaceId = await resolveActiveWorkspaceIdWithMembership(
    userId,
    supabase,
  );

  // 3. Connectivity gate — read the SOURCE OF TRUTH (`workspaces`), not
  //    `users.repo_status` (ADR-044 relocated repo state to `workspaces`).
  const wsChain = supabase.from("workspaces") as MaybeSingleChain<WorkspaceRepoRow>;
  const wsResult = await awaitChain<{ data: WorkspaceRepoRow | null; error: unknown }>(
    wsChain
      .select("repo_status, organization_id")
      .eq("id", activeWorkspaceId)
      .maybeSingle(),
  );
  // A query error degrades to 404 ("No Project Connected") — mirror it so a
  // recurring workspaces-read failure on this brand-survival read path is
  // visible, not an invisible bare-404 (cq-silent-fallback-must-mirror-to-sentry).
  if (wsResult.error) {
    reportSilentFallback(wsResult.error, {
      feature: "workspace-resolver",
      op: "resolveActiveWorkspaceKbRoot.workspaces-read",
      extra: { userId, activeWorkspaceId },
    });
  }
  const repoStatus = wsResult.data?.repo_status ?? null;
  if (wsResult.error || !repoStatus || repoStatus === "not_connected") {
    return { ok: false, status: 404 };
  }

  // 4. Readiness gate — the active workspace OWNER's `users.workspace_status`.
  //    Solo shortcut: owner === caller (N2), so skip the organizations hop and
  //    read the caller's own row (byte-identical to the legacy behavior).
  let ownerId = userId;
  if (activeWorkspaceId !== userId) {
    const orgId = wsResult.data?.organization_id ?? null;
    if (!orgId) return { ok: false, status: 503 };
    const orgChain = supabase.from("organizations") as MaybeSingleChain<{
      owner_user_id: string;
    }>;
    const orgResult = await awaitChain<{
      data: { owner_user_id: string } | null;
      error: unknown;
    }>(orgChain.select("owner_user_id").eq("id", orgId).maybeSingle());
    if (orgResult.error) {
      reportSilentFallback(orgResult.error, {
        feature: "workspace-resolver",
        op: "resolveActiveWorkspaceKbRoot.organizations-read",
        extra: { userId, activeWorkspaceId },
      });
    }
    if (orgResult.error || !orgResult.data?.owner_user_id) {
      return { ok: false, status: 503 };
    }
    ownerId = orgResult.data.owner_user_id;
  }

  const userChain = supabase.from("users") as MaybeSingleChain<{
    workspace_status: string | null;
  }>;
  const ownerResult = await awaitChain<{
    data: { workspace_status: string | null } | null;
    error: unknown;
  }>(userChain.select("workspace_status").eq("id", ownerId).maybeSingle());
  if (ownerResult.error) {
    reportSilentFallback(ownerResult.error, {
      feature: "workspace-resolver",
      op: "resolveActiveWorkspaceKbRoot.owner-readiness-read",
      extra: { userId, activeWorkspaceId, ownerId },
    });
  }
  if (ownerResult.error || ownerResult.data?.workspace_status !== "ready") {
    return { ok: false, status: 503 };
  }

  // The id-shape guard (CWE-22 #5344) lives in workspacePathForWorkspaceId, so
  // both workspacePath and the kbRoot built from it below are covered here.
  // NOTE: paths built from the pre-stored `users.workspace_path` column
  // (kb-route-helpers / kb upload route) are a SEPARATE boundary, mitigated by
  // their own downstream `isPathInWorkspace` containment — not by this guard.
  const workspacePath = workspacePathForWorkspaceId(activeWorkspaceId);
  return {
    ok: true,
    activeWorkspaceId,
    workspacePath,
    kbRoot: join(workspacePath, "knowledge-base"),
    repoStatus,
  };
}

/**
 * Resolve the git-push metadata (repo_url + GitHub installation id) for the
 * caller's ACTIVE workspace (ADR-044, #4543). The SIBLING to
 * `resolveActiveWorkspaceKbRoot` — kept separate so the read-path resolvers
 * (content/tree/search/c4-project) stay lean (they never need repo metadata).
 * The upload route composes both: `resolveActiveWorkspaceKbRoot` (kbRoot +
 * readiness/connectivity gate) + this (git-push credentials).
 *
 * Sources, ALL service-role + membership-scoped (NEVER the caller's `users`
 * row — the #4543 dual-ownership trap, where an invited member's own users row
 * is the empty solo row → "No repository connected"):
 *   1. active workspace id via `resolveActiveWorkspaceIdWithMembership`
 *      (claim → solo fallback, NEVER a sibling — the IDOR self-scope);
 *   2. `workspaces.repo_url` by active id (mirrors the active-repo route);
 *   3. installation via the EXISTING `resolveInstallationId(userId, activeId)`
 *      — the membership-checked `resolve_workspace_installation_id` SECURITY
 *      DEFINER RPC, because `workspaces.github_installation_id` is REVOKED from
 *      the `authenticated` grant (migration 079). A direct tenant SELECT
 *      returns null.
 *
 * Returns the legacy KB-route status contract: 404 = no repo connected,
 * 400 = repo connected but no installation resolvable, 503 = workspace read
 * error. Mirrors any query error via reportSilentFallback.
 *
 * `resolveInstallationId` is imported dynamically to avoid a static import
 * cycle (`resolve-installation-id.ts` imports `resolveCurrentWorkspaceId` from
 * this module).
 */
export type ActiveWorkspaceRepoMeta =
  | { ok: false; status: 400 | 404 | 503 }
  | { ok: true; repoUrl: string; githubInstallationId: number };

export async function resolveActiveWorkspaceRepoMeta(
  userId: string,
  supabase: SupabaseLike,
  // Optional pre-resolved active id. When a caller already resolved the active
  // workspace (e.g. via resolveActiveWorkspaceKbRoot in the same request), pass
  // it here so kbRoot, repo metadata, and any attribution write all key to ONE
  // membership-resolved id — and skip a redundant user_session_state +
  // workspace_members round-trip.
  preResolvedActiveWorkspaceId?: string,
): Promise<ActiveWorkspaceRepoMeta> {
  // 1. Active workspace id — claim → solo fallback (never a sibling).
  const activeWorkspaceId =
    preResolvedActiveWorkspaceId ??
    (await resolveActiveWorkspaceIdWithMembership(userId, supabase));

  // 2. repo_url from the SOURCE OF TRUTH (`workspaces`), service-role, by
  //    active id — mirrors app/api/workspace/active-repo/route.ts:67-71.
  const wsChain = supabase.from("workspaces") as MaybeSingleChain<{
    repo_url: string | null;
  }>;
  const wsResult = await awaitChain<{
    data: { repo_url: string | null } | null;
    error: unknown;
  }>(wsChain.select("repo_url").eq("id", activeWorkspaceId).maybeSingle());
  if (wsResult.error) {
    reportSilentFallback(wsResult.error, {
      feature: "workspace-resolver",
      op: "resolveActiveWorkspaceRepoMeta.workspaces-read",
      extra: { userId, activeWorkspaceId },
    });
    return { ok: false, status: 503 };
  }
  const repoUrl = wsResult.data?.repo_url ?? null;
  if (!repoUrl) {
    // No repository connected for the active workspace.
    return { ok: false, status: 404 };
  }

  // 3. Installation via the membership-checked SECURITY DEFINER RPC. Pass the
  //    resolved active id so the credential is read for the SAME workspace the
  //    kbRoot/repo resolve to (not re-derived inside resolveInstallationId).
  const { resolveInstallationId } = await import(
    "@/server/resolve-installation-id"
  );
  const githubInstallationId = await resolveInstallationId(
    userId,
    activeWorkspaceId,
  );
  if (!githubInstallationId) {
    // Repo connected but no installation resolvable (revoked grant / non-member
    // RPC deny / disconnected app) — mirror the legacy "No repository
    // connected" 400 the upload route returned.
    return { ok: false, status: 400 };
  }

  return { ok: true, repoUrl, githubInstallationId };
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
  if (!UUID_RE.test(workspaceId)) {
    // JSON.stringify escapes control chars (the value is Sentry-bound via the
    // callers' catch → reportSilentFallback): closes the log-injection vector
    // a crafted/corrupted id would otherwise open (#5344).
    throw new Error(`Invalid workspaceId format: ${JSON.stringify(workspaceId)}`);
  }
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
  if (!UUID_RE.test(workspaceId)) {
    throw new Error(`Invalid workspaceId format: ${JSON.stringify(workspaceId)}`);
  }
  return join(getWorkspacesRoot(), workspaceId);
}

// Git-data READ-side client — epic #5274 Phase 3 Sub-PR 3.C / ADR-068 §6.
//
// The shared git-data bare store is reached over ONE cluster-wide SSH transport
// key (`GIT_TRANSPORT_SSH_PRIVATE_KEY`). That key authorizes the *transport*, not
// the *tenant*: nothing in the SSH layer (nor the agent sandbox bwrap, which only
// isolates the filesystem — agent-runner-sandbox-config.ts) gates WHICH
// workspace's objects a request may fetch. So the app MUST authorize membership
// before it fetches a workspace's refs on a user's behalf — the boundary bwrap
// cannot cover (ADR-068 §6 cross-tenant isolation; the fetch mirror of the
// git-data-replication.ts D2 write-boundary sentinel).
//
// AUTHORIZATION AUTHORITY: `is_workspace_member(p_workspace_id, p_user_id)` — the
// canonical SECURITY DEFINER membership substrate (migration 053; the same
// predicate `resolve_workspace_installation_id` itself gates on, mig 079 §2).
// It is used HERE — not `resolve_workspace_installation_id` directly — because
// that RPC returns NULL for BOTH a non-member AND a member whose workspace has no
// GitHub App installation; git-data is replicated for EVERY workspace (connected
// or not), so keying on the installation-id RPC would wrongly deny a legitimate
// member's own git-data. `is_workspace_member` returns a clean membership boolean.
// (Plan D0/D2 spec: "membership shape … NULL→deny" — the faithful reading is the
// membership predicate, not the credential resolver that conflates two states.)
//
// FAIL-CLOSED: any RPC error, any exception, a NULL/false result, or a missing
// userId DENIES. A cross-tenant attempt (genuine non-member) is a security event
// mirrored to Sentry; an RPC failure (membership indeterminable) is an error
// mirrored to Sentry — both surface under `feature: "git-data-authz"` so on-call
// can query `feature:git-data-authz op:*-deny` without SSH (Observability §).

import { getFreshTenantClient, RuntimeAuthError } from "@/lib/supabase/tenant";
import {
  hashUserId,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { isGitDataStoreEnabled } from "@/server/workspace-resolver";
import { gitWithPrivateKeyAuth } from "@/server/git-auth";
// Pure transport helpers (call-time only) from the WRITE-side module. The two
// modules reference each other exclusively inside async function bodies (this
// file → gitDataRemoteUrl/assertSafeWorkspaceId; the write module →
// authorizeGitDataAccess), so the ESM cycle resolves via live bindings and never
// touches a partially-initialized export at module-eval time (intentional; keeps
// a SINGLE URL builder + a SINGLE authz authority, no drift).
import { assertSafeWorkspaceId, gitDataRemoteUrl } from "@/server/git-data-replication";
import { assertSafeWorktreeId } from "@/server/worktree-write-lease";

/**
 * Thrown when a git-data access (fetch or push) is refused because the acting
 * user is not a member of the target workspace, or membership could not be
 * confirmed (fail-closed). Distinct type so callers/tests can assert the DENY
 * reason rather than string-matching a generic error.
 */
export class GitDataAuthorizationError extends Error {
  constructor(
    readonly op: "fetch" | "write",
    readonly reason: "not-member" | "indeterminate" | "missing-user",
    message: string,
  ) {
    super(message);
    this.name = "GitDataAuthorizationError";
  }
}

/**
 * Fail-closed membership authorization for shared git-data access.
 *
 * Returns `true` IFF `userId` is a confirmed member of `workspaceId`, verified
 * via the `is_workspace_member` SECURITY DEFINER RPC through a fresh tenant
 * client (the RPC is REVOKE'd from `service_role` and GRANTed to `authenticated`,
 * so it MUST run under the user's own JWT — which is also why this module never
 * imports the service-role client). Every non-affirmative outcome returns `false`
 * (fail-closed) and mirrors telemetry:
 *   - genuine non-member (data === false)  → `warnSilentFallback` (security)
 *   - RPC/tenant error or exception         → `reportSilentFallback` (error)
 *   - missing userId                        → `reportSilentFallback` (error)
 *
 * The check is keyed on the EXACT `workspaceId` the caller will use to build the
 * transport URL (no re-derivation — hr-write-boundary-sentinel-sweep-all-write-sites).
 */
export async function authorizeGitDataAccess(params: {
  userId: string | undefined;
  workspaceId: string;
  op: "fetch" | "write";
}): Promise<boolean> {
  const { userId, workspaceId, op } = params;
  const workspaceIdHash = hashUserId(workspaceId);

  if (!userId) {
    // A push/fetch with no authorizing user is a logic bug once the flag is on
    // (both call sites derive userId from the session). Fail closed + loud.
    reportSilentFallback(
      new Error("git-data access with no authorizing userId"),
      {
        feature: "git-data-authz",
        op: `${op}-deny`,
        extra: { workspaceIdHash, reason: "missing-user" },
        tags: { sec: "true" },
        message:
          "git-data authorization refused — no userId to authorize the " +
          `${op}; refusing to reach the shared store without a member check`,
      },
    );
    return false;
  }

  try {
    const tenant = await getFreshTenantClient(userId);
    const { data, error } = await tenant.rpc("is_workspace_member", {
      p_workspace_id: workspaceId,
      p_user_id: userId,
    });

    if (error) {
      reportSilentFallback(error, {
        feature: "git-data-authz",
        op: `${op}-deny`,
        extra: { userId, workspaceIdHash, reason: "indeterminate" },
        tags: { sec: "true" },
        message:
          "git-data membership RPC failed — authorization indeterminate; " +
          "denying (fail-closed)",
      });
      return false;
    }

    if (data === true) return true;

    // Genuine cross-tenant attempt: a confirmed non-member. Loud security event
    // (Observability failure_mode: git-data denial {workspace_id_hash, member:false}).
    warnSilentFallback(
      new Error("git-data cross-tenant access denied (non-member)"),
      {
        feature: "git-data-authz",
        op: `${op}-deny`,
        extra: { userId, workspaceIdHash, member: false, reason: "not-member" },
        tags: { sec: "true", cross_tenant: "true" },
        message:
          `git-data ${op} refused — user is not a member of the target ` +
          "workspace (cross-tenant boundary, fail-closed)",
      },
    );
    return false;
  } catch (err) {
    // RuntimeAuthError (JWT mint failed) or any other throw → indeterminate → deny.
    if (!(err instanceof RuntimeAuthError)) {
      // Non-auth throws are unexpected; still fail closed, still mirror.
      reportSilentFallback(err, {
        feature: "git-data-authz",
        op: `${op}-deny`,
        extra: { userId, workspaceIdHash, reason: "indeterminate" },
        tags: { sec: "true" },
        message: "git-data authorization threw — denying (fail-closed)",
      });
      return false;
    }
    reportSilentFallback(err, {
      feature: "git-data-authz",
      op: `${op}-deny`,
      extra: { userId, workspaceIdHash, reason: "indeterminate" },
      tags: { sec: "true" },
      message:
        "git-data authorization could not mint a tenant client — denying " +
        "(fail-closed)",
    });
    return false;
  }
}

/**
 * Authorized fetch of a workspace's per-user worktree namespace from the shared
 * git-data store into `destPath`'s local `refs/heads/*` (the reverse of the
 * git-data-replication.ts write refspec: the write pushes local `refs/heads/*` →
 * `refs/soleur/worktrees/<worktreeId>/heads/*`, so the read maps that namespace
 * back). Membership is authorized FIRST (fail-closed); on a DENY nothing touches
 * the transport and a {@link GitDataAuthorizationError} is thrown. NO-OP (returns
 * without fetching) at flag-off — the whole read side is dark until the 3.D flip.
 *
 * `destPath` must already be a git work tree with a configured `git-data` remote
 * (see `ensureGitDataRemote`). Retains `origin`→GitHub untouched — GitHub stays
 * the canonical rehydration source (ADR-068 §1; never orphan).
 *
 * PRECONDITION (3.D, CTO ruling): FRESH-GRAFT-ONLY — do NOT call on a live worktree.
 * The fetch lands worktree heads in remote-tracking `refs/remotes/git-data/*` (never
 * a local branch), but the `+…tags/*:refs/tags/*` force-fetch would clobber a
 * local-only tag on a live tree. The sole caller wires this on the fresh-clone path
 * (ensure-workspace-repo, past the `isValidGitWorkTree` early-return), where by
 * construction no local-only refs exist. git-data ⊇ GitHub origin in committed-ref
 * completeness (syncPush only auto-commits `knowledge-base/**` + reroutes protected
 * pushes to a PR branch; replicateToGitData force-pushes ALL refs), so rehydration =
 * clone(GitHub) → overlay(git-data).
 */
export async function fetchFromGitData(params: {
  userId: string;
  workspaceId: string;
  worktreeId: string;
  workspacePath: string;
}): Promise<void> {
  if (!isGitDataStoreEnabled()) return;
  const { userId, workspaceId, worktreeId, workspacePath } = params;
  assertSafeWorkspaceId(workspaceId);
  assertSafeWorktreeId(worktreeId);

  const authorized = await authorizeGitDataAccess({ userId, workspaceId, op: "fetch" });
  if (!authorized) {
    throw new GitDataAuthorizationError(
      "fetch",
      "not-member",
      `git-data fetch refused for workspace ${workspaceId} (membership denied)`,
    );
  }

  const transportKey = process.env.GIT_TRANSPORT_SSH_PRIVATE_KEY?.trim();
  if (!transportKey) {
    throw new Error(
      "git-data: GIT_TRANSPORT_SSH_PRIVATE_KEY is unset — cannot fetch from the " +
        "git-data host. It is delivered to the container from Doppler prd.",
    );
  }

  // Fetch by the EXPLICIT URL built from the AUTHORIZED workspaceId — NOT the
  // named `git-data` remote resolved from `workspacePath`'s local config. This
  // binds the transport target to the exact workspaceId membership just authorized
  // (mirror of the write path's inline `ensureGitDataRemote(workspacePath,
  // workspaceId)`): a clone whose local `git-data` remote pointed at a DIFFERENT
  // workspace could otherwise pull tenant-B objects while authz passed for tenant-A.
  const remoteUrl = gitDataRemoteUrl(workspaceId);

  // Map this user's OWN namespace into REMOTE-TRACKING refs (`refs/remotes/git-data/*`),
  // NOT local `refs/heads/*` (3.D, CTO ruling). A `+…:refs/heads/*` force-fetch would
  // target the destination clone's CHECKED-OUT branch — which git refuses, or under
  // force discards local-only commits (silent user-data loss). Landing in a
  // remote-tracking namespace is one git can never refuse and can never overwrite a
  // live branch; the fresh-graft caller (ensure-workspace-repo) then does a guarded
  // `reset --hard refs/remotes/git-data/<primary>` to overlay the latest tip. Tags
  // keep `refs/tags/*` — safe ONLY because this is a fresh-graft-only call (see the
  // precondition in the doc comment above; a live worktree could hold local-only tags).
  // The fence, not ref ancestry, is the ordering authority — symmetric to the write's
  // `--force`. Cross-user visibility is a separate explicit fetch of the peer namespace
  // (ADR-068 D0-ref), not this call.
  await gitWithPrivateKeyAuth(
    [
      "fetch",
      remoteUrl,
      `+refs/soleur/worktrees/${worktreeId}/heads/*:refs/remotes/git-data/*`,
      `+refs/soleur/worktrees/${worktreeId}/tags/*:refs/tags/*`,
    ],
    transportKey,
    { cwd: workspacePath, timeout: 60_000 },
  );
}

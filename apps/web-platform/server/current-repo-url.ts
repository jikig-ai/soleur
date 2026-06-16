import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { normalizeRepoUrl } from "@/lib/repo-url";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

/**
 * Read the repo URL of the authenticated user's CURRENT (active) workspace.
 *
 * Post-ADR-044 read-cutover: the source of truth is `workspaces.repo_url`,
 * NOT `users.repo_url`. The active workspace is resolved INTERNALLY from
 * `user_session_state.current_workspace_id` (server-derived from the
 * authenticated user — never from `req.body`/`req.query`, so no IDOR), and
 * an explicit `workspaceId` may be passed to override (e.g. by callers that
 * already hold a verified workspace context). A null/absent claim falls
 * back to the caller's SOLO workspace (`= userId`), never a sibling. Reads
 * come from `workspaces` ONLY — no `users.repo_url` fallback — to avoid the
 * dual-ownership divergence trap.
 *
 * `repo_url` is a non-credential column (it stays in the `authenticated`
 * grant; only `github_installation_id` is revoked), and RLS
 * (`workspaces_select_for_members`) gates row visibility to members.
 *
 * Returns `null` when the workspace has no repo OR on transient error —
 * callers treat both identically (disconnect semantics fail-closed).
 */
export async function getCurrentRepoUrl(
  userId: string,
  workspaceId?: string | null,
): Promise<string | null> {
  let tenant;
  try {
    tenant = await getFreshTenantClient(userId);
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      // Transient retryable auth blip (tenant JWT mint) on a hot reconnect
      // path — WARNING, not error. This upstream emit is the single
      // highest-volume contributor to the `feature=stream-replay`
      // ownership-mismatch false-positive flood (the WS resume handler reads
      // this and used to misread the resulting null as a repo-scope mismatch).
      // The genuine query-error path below stays at error level. (#5290 /
      // ADR-059 false-positive remediation.)
      warnSilentFallback(err, {
        feature: "repo-scope",
        op: "read-current-repo-url.tenant-mint",
        extra: { userId },
      });
      return null;
    }
    throw err;
  }

  const targetWorkspaceId =
    workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));

  const { data, error } = await tenant
    .from("workspaces")
    .select("repo_url")
    .eq("id", targetWorkspaceId)
    .maybeSingle();

  if (error) {
    reportSilentFallback(error, {
      feature: "repo-scope",
      op: "read-current-repo-url",
      extra: { userId, workspaceId: targetWorkspaceId },
    });
    return null;
  }

  // Normalize on return — the choke point for every server consumer
  // (MCP tools, WS handler, agent-runner, lookup helper). Post-backfill
  // this is a no-op on at-rest data; the safety net for any row the
  // migration couldn't normalize.
  const raw = (data?.repo_url as string | null | undefined) ?? null;
  const normalized = normalizeRepoUrl(raw);
  return normalized.length > 0 ? normalized : null;
}

/**
 * The active workspace's repo readiness signal for the Concierge dispatch gate
 * (#5394). Reads `repo_status` from `workspaces` (the ADR-044 source of truth,
 * correct for shared/team workspaces) and the sanitized error REASON from
 * `users.repo_error` — `workspaces.repo_error` is NEVER written
 * (`workspace-repo-mirror.ts:6`), so the reason can only come from `users`.
 * Both reads go through the TENANT client (own-row RLS: "Users can read own
 * profile"), keeping cc-dispatcher OFF the service-role allowlist.
 *
 * FAIL-OPEN: any transient/auth/query error coerces to
 * `{ repoStatus: "not_connected" }` so a `ready` founder is NEVER blocked by a
 * tenant-mint blip — worst case a genuinely `cloning`/`error` workspace falls
 * through to the existing repo-less path / #5392 fallback (the safety net this
 * gate layers on top of).
 *
 * Source-key note (forward-looking, for the #4560 team-workspace author): the
 * `repo_status` key is the active WORKSPACE while the `repo_error` key is the
 * dispatching USER. Today connect/disconnect is solo-only
 * (`workspace.id === user.id`), so the two keys coincide. Once team-invite repo
 * flows land (#4560), a member dispatching against a workspace whose `error`
 * status was caused by ANOTHER member reads their own (null) `repo_error` → the
 * gate's message degrades to the generic `"setup failed"` fallback (NOT a
 * misclassification and NOT a cross-member leak — readiness is still correct).
 */
export async function getCurrentRepoStatus(
  userId: string,
  workspaceId?: string | null,
): Promise<{ repoStatus: string; repoError: string | null }> {
  const FAIL_OPEN = { repoStatus: "not_connected", repoError: null } as const;

  let tenant;
  try {
    tenant = await getFreshTenantClient(userId);
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      // Same transient tenant-mint blip class as getCurrentRepoUrl — WARN, not
      // error. Fail-open so the gate never blocks a ready founder on a blip.
      warnSilentFallback(err, {
        feature: "repo-readiness",
        op: "read-current-repo-status.tenant-mint",
        extra: { userId },
      });
      return FAIL_OPEN;
    }
    throw err;
  }

  const targetWorkspaceId =
    workspaceId ?? (await resolveCurrentWorkspaceId(userId, tenant));

  // workspaces.repo_status (source of truth) + users.repo_error (the only row
  // that holds the sanitized reason) in parallel — adds no sequential await.
  const [statusRes, errorRes] = await Promise.all([
    tenant
      .from("workspaces")
      .select("repo_status")
      .eq("id", targetWorkspaceId)
      .maybeSingle(),
    tenant
      .from("users")
      .select("repo_error")
      .eq("id", userId)
      .maybeSingle(),
  ]);

  if (statusRes.error) {
    reportSilentFallback(statusRes.error, {
      feature: "repo-readiness",
      op: "read-current-repo-status",
      extra: { userId, workspaceId: targetWorkspaceId },
    });
    return FAIL_OPEN;
  }

  const repoStatus =
    (statusRes.data?.repo_status as string | null | undefined) ??
    "not_connected";
  // A users-read error must not block dispatch — the reason is only consumed on
  // the `error` branch, so a null reason degrades to generic copy, never a hard
  // fail. (No reportSilentFallback: the status read is the load-bearing signal.)
  const repoError =
    (errorRes.data?.repo_error as string | null | undefined) ?? null;

  return { repoStatus, repoError };
}

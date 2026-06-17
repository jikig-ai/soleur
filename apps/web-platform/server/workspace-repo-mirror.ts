import { reportSilentFallback } from "@/server/observability";

/**
 * The ADR-044 "moved" repo columns — relocated from `users` to `workspaces`.
 * Non-moved connect-flow columns (`workspace_path`, `workspace_status`,
 * `repo_error`, `health_snapshot`) stay on `users` and are NOT mirrored.
 */
export type MirroredRepoCols = Partial<{
  repo_url: string | null;
  github_installation_id: number | null;
  repo_status: string;
  repo_last_synced_at: string | null;
}>;

interface ServiceClientLike {
  from: (table: string) => {
    update: (patch: MirroredRepoCols) => {
      eq: (col: string, val: string) => PromiseLike<{ error: unknown }>;
    };
  };
}

/**
 * Dual-write the moved repo columns to the user's SOLO workspace
 * (`workspaces.id == user_id`, ADR-038 N2) so the workspaces-only read path
 * (`getCurrentRepoUrl` / `resolveInstallationId`) stays consistent with the
 * legacy `users` write during the ADR-044 soak. Without this, a fresh
 * connect/disconnect would write `users` while the read path checks
 * `workspaces`, showing a stale/absent repo.
 *
 * Connect/disconnect flows are SOLO-ONLY today (team-invite repo flows are
 * deferred to #5462 / Phase 5 — they will resolve the target workspace
 * first), so the solo workspace id equals the user id.
 *
 * Service-role write: members cannot UPDATE `workspaces` directly (no
 * UPDATE RLS policy) and `github_installation_id` is REVOKE'd from the
 * `authenticated` grant; the caller passes a service client.
 *
 * Best-effort by default — failure is Sentry-mirrored but does not throw,
 * because on a CONNECT the `users` write stays authoritative and a missed
 * mirror only makes the workspaces-only read path show "not connected" (a
 * safe-fail the next connect/sync re-mirrors).
 *
 * Pass `{ throwOnError: true }` on the DISCONNECT / credential-clear path:
 * there the read path is workspaces-only, so a silently-failed mirror would
 * leave `github_installation_id` (a live GitHub App grant) and `repo_url`
 * readable AFTER the user "disconnected" — the agent could still act under
 * the supposedly-revoked grant, and the `repo_url && installationId === null`
 * revalidation guard cannot catch it (both stay non-null). Failing closed
 * lets the route surface a 500 so the (idempotent) disconnect is retried.
 */
export async function mirrorRepoColsToSoloWorkspace(
  service: ServiceClientLike,
  userId: string,
  patch: MirroredRepoCols,
  opts?: { throwOnError?: boolean },
): Promise<void> {
  const { error } = await service.from("workspaces").update(patch).eq("id", userId);
  if (error) {
    reportSilentFallback(error, {
      feature: "workspace-repo-mirror",
      op: "mirror-to-solo-workspace",
      extra: { userId, cols: Object.keys(patch) },
      message: "Failed to mirror repo columns to the solo workspace",
    });
    if (opts?.throwOnError) {
      throw error instanceof Error ? error : new Error(String(error));
    }
  }
}

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
 * deferred to #4560 / Phase 5 — they will resolve the target workspace
 * first), so the solo workspace id equals the user id.
 *
 * Service-role write: members cannot UPDATE `workspaces` directly (no
 * UPDATE RLS policy) and `github_installation_id` is REVOKE'd from the
 * `authenticated` grant; the caller passes a service client. Best-effort —
 * failure is Sentry-mirrored but does not throw (the `users` write remains
 * the authoritative record until the decommission migration).
 */
export async function mirrorRepoColsToSoloWorkspace(
  service: ServiceClientLike,
  userId: string,
  patch: MirroredRepoCols,
): Promise<void> {
  const { error } = await service.from("workspaces").update(patch).eq("id", userId);
  if (error) {
    reportSilentFallback(error, {
      feature: "workspace-repo-mirror",
      op: "mirror-to-solo-workspace",
      extra: { userId, cols: Object.keys(patch) },
      message: "Failed to mirror repo columns to the solo workspace",
    });
  }
}

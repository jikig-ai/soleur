import { reportSilentFallback } from "@/server/observability";

/**
 * The ADR-044 repo-connection columns — authoritative on `workspaces` as of the
 * PR-2 write-cutover (#5462). `repo_error` joined the set (migration 110 adds the
 * column + extends the non-credential GRANT). The provisioning/readiness columns
 * (`workspace_path`, `workspace_status`, `health_snapshot`) are NOT relocated by
 * ADR-044 and stay on `users` (written by the connect routes only for the SOLO
 * owner case).
 */
export type WorkspaceRepoCols = Partial<{
  repo_url: string | null;
  github_installation_id: number | null;
  repo_status: string;
  repo_last_synced_at: string | null;
  repo_error: string | null;
}>;

interface ServiceClientLike {
  from: (table: string) => {
    update: (patch: WorkspaceRepoCols) => {
      eq: (
        col: string,
        val: string,
      ) => {
        select: (
          cols: string,
        ) => PromiseLike<{ data: Array<{ id: string }> | null; error: unknown }>;
      };
    };
  };
}

/**
 * Write the authoritative repo-connection columns to the `workspaces` row keyed
 * on the **caller-supplied resolved workspace id** (team OR solo — NOT a
 * hardcoded `userId`). This is the PR-2 inversion of the former
 * `mirrorRepoColsToSoloWorkspace`: `workspaces` is now the source of truth, so
 * this is the authoritative write, not a best-effort mirror.
 *
 * The caller MUST pass an id resolved server-side via the membership-verified
 * `resolveActiveWorkspace` (IDOR-safe, never `req.body`); a write to an
 * unverified id would cross the user→workspace tenant boundary.
 *
 * Members cannot UPDATE `workspaces` directly (no UPDATE RLS policy) and
 * `github_installation_id` is REVOKE'd from the `authenticated` grant, so the
 * caller passes a service client.
 *
 * The UPDATE `.select("id")`s so a **0-row match** is detected: a
 * `.eq("id", workspaceId)` that matches no row returns `{error:null}` — a SILENT
 * no-op (the workspace can be deleted between request return and a background
 * callback; `current_workspace_id` is `ON DELETE SET NULL`, mig 079). A 0-row
 * write is treated as a failure class (`cq-silent-fallback-must-mirror-to-sentry`).
 *
 * Best-effort by default — failure is Sentry-mirrored but does not throw.
 * Pass `{ throwOnError: true }` on the DISCONNECT / credential-clear path and on
 * the connect cloning-flip: there a silently-failed write would leave
 * `github_installation_id` (a live GitHub App grant) + `repo_url` readable on the
 * workspaces-only read path AFTER the user "disconnected", or report a connect as
 * succeeded when it never persisted. Failing closed lets the route surface a 500
 * so the (idempotent) operation is retried.
 */
export async function writeRepoColsToWorkspace(
  service: ServiceClientLike,
  workspaceId: string,
  patch: WorkspaceRepoCols,
  opts?: { throwOnError?: boolean },
): Promise<void> {
  const { data, error } = await service
    .from("workspaces")
    .update(patch)
    .eq("id", workspaceId)
    .select("id");

  if (error) {
    reportSilentFallback(error, {
      feature: "workspace-repo-write",
      op: "write-to-workspace",
      extra: { workspaceId, cols: Object.keys(patch) },
      message: "Failed to write repo columns to the active workspace",
    });
    if (opts?.throwOnError) {
      throw error instanceof Error ? error : new Error(String(error));
    }
    return;
  }

  if (!data || data.length === 0) {
    // 0-row no-op: the target workspace row is gone (deleted mid-flight) or the
    // id never existed. The write silently affected nothing — surface it.
    const zeroRow = new Error(
      `writeRepoColsToWorkspace matched 0 rows for workspace ${workspaceId}`,
    );
    reportSilentFallback(zeroRow, {
      feature: "workspace-repo-write",
      op: "write-to-workspace.zero-rows",
      extra: { workspaceId, cols: Object.keys(patch) },
      message: "Repo-column write to the active workspace matched 0 rows",
    });
    if (opts?.throwOnError) {
      throw zeroRow;
    }
  }
}

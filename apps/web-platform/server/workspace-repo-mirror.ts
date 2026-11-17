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
  /** #12714 (migration 187): display-only held-files count, 0..10000, null = unknown. Service-client only. */
  kb_sync_held_files: number | null;
  /** #12714 (migration 187): when `kb_sync_held_files` was computed. */
  kb_sync_held_checked_at: string | null;
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

interface HeldClearClientLike {
  from: (table: string) => {
    update: (patch: Pick<WorkspaceRepoCols, "kb_sync_held_files" | "kb_sync_held_checked_at">) => {
      eq: (col: string, val: string) => PromiseLike<{ error: unknown }>;
    };
  };
}

/**
 * #12714 (D29(1), D33(2)): null the held-files columns of the workspace, in a SEPARATE best-effort UPDATE that the
 * disconnect and setup routes run after their own repo-column write. A held count describes one connection, so it
 * must not reappear after a reconnect. Never throws: a failure (a missing column during an apply that lags, or after a
 * rollback) sends one mirror and leaves the route's status and response unchanged. A missing column also means no
 * count was ever stored, so nothing goes stale.
 */
export async function clearKbSyncHeldCols(service: HeldClearClientLike, workspaceId: string): Promise<void> {
  let failure: unknown = null;
  try {
    const { error } = await service
      .from("workspaces")
      .update({ kb_sync_held_files: null, kb_sync_held_checked_at: null })
      .eq("id", workspaceId);
    failure = error ?? null;
  } catch (err) {
    failure = err ?? new Error("clearKbSyncHeldCols rejected");
  }
  if (failure) {
    reportSilentFallback(failure, {
      feature: "workspace-repo-write",
      op: "clear-kb-sync-held",
      extra: { workspaceId },
      message: "Failed to clear the held-files columns on the workspace",
    });
  }
}

/**
 * Why the self-heal is blocked from pulling (D42): the closed values of `workspaces.kb_sync_pull_blocked`, which lands
 * with WP3's amendment of migration 187.
 */
export type KbSyncPullBlocked = "merge_conflict_precheck" | "untracked_collision";

/**
 * The held-files write (frozen signature, review Phase 0): the count (null = unknown) and the instant it was computed,
 * always together. `pullBlocked` undefined leaves that column untouched; in Phase 0 the column does not exist yet, so
 * `pullBlocked` is accepted and never written (WP3 writes it).
 */
export interface KbSyncHeldPatch {
  heldFiles: number | null;
  checkedAt: Date;
  pullBlocked?: KbSyncPullBlocked | null;
}

interface HeldWriteClientLike {
  from: (table: string) => {
    update: (patch: { kb_sync_held_files: number | null; kb_sync_held_checked_at: string }) => {
      eq: (col: string, val: string) => {
        select: (cols: string) => PromiseLike<{ data: Array<{ id: string }> | null; error: unknown }>;
      };
    };
  };
}

/**
 * #12714 (D29(1), D33): write the held-files count and the time it was computed, after every sync that computed one
 * (`syncPush` from its `finally`, `syncPull` after its merge and adoption). A SEPARATE service-client UPDATE, never folded
 * into the `repo_last_synced_at` stamp, so a missing column (an apply that lags, or a rollback) fails only this write.
 * Written every time (no write-on-change map), so `kb_sync_held_checked_at` advances on an unchanged value too.
 *
 * Never throws: an error, a rejection or a 0-row match (the workspace was deleted mid-flight, or the id never existed)
 * sends one mirror, and the sync's result is unchanged. The caller passes the membership-verified workspace id it already
 * resolved (agent-runner), never a re-resolved or request-supplied one.
 */
export async function writeKbSyncHeldCols(
  service: HeldWriteClientLike,
  workspaceId: string,
  patch: KbSyncHeldPatch,
): Promise<void> {
  let failure: unknown = null;
  let op = "write-kb-sync-held";
  try {
    const { data, error } = await service
      .from("workspaces")
      .update({ kb_sync_held_files: patch.heldFiles, kb_sync_held_checked_at: patch.checkedAt.toISOString() })
      .eq("id", workspaceId)
      .select("id");
    if (error) {
      failure = error;
    } else if (!data || data.length === 0) {
      failure = new Error(`writeKbSyncHeldCols matched 0 rows for workspace ${workspaceId}`);
      op = "write-kb-sync-held.zero-rows";
    }
  } catch (err) {
    failure = err ?? new Error("writeKbSyncHeldCols rejected");
  }
  if (failure) {
    reportSilentFallback(failure, {
      feature: "workspace-repo-write",
      op,
      extra: { workspaceId },
      message: "Failed to write the held-files count to the workspace",
    });
  }
}

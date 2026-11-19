import log from "@/server/logger";
import { mirrorWithDebounce, reportSilentFallback } from "@/server/observability";

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
  // The #12714 held columns (migrations 187, 188) are deliberately NOT here (simplicity F6, D29(1), D33(2)): they have their
  // own row type below, so folding them into the fail-closed repo write is a compile error, not a census regex.
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

/**
 * Why the self-heal is blocked from pulling (D42): the closed values of `workspaces.kb_sync_pull_blocked` (migration 188's
 * named check).
 */
export type KbSyncPullBlocked = "merge_conflict_precheck" | "untracked_collision";

const PULL_BLOCKED_VALUES: ReadonlySet<unknown> = new Set<KbSyncPullBlocked>(["merge_conflict_precheck", "untracked_collision"]);

/**
 * The held-files write (frozen signature, review Phase 0): the count (null = unknown) and the instant this run read the
 * remote tip it was computed against (`RemoteState.readAt`, D39(f)), always together. The pull-blocked state is NOT
 * part of it: it has its own UPDATE, `writeKbSyncPullBlocked` (verify-data-sec P3-4).
 */
export interface KbSyncHeldPatch {
  heldFiles: number | null;
  checkedAt: Date;
}

/** The held columns by name (187's two, 188's pull-blocked): the row shapes the held UPDATEs take. */
type KbSyncHeldRow =
  | { kb_sync_held_files: number | null; kb_sync_held_checked_at: string }
  | { kb_sync_held_files: null; kb_sync_held_checked_at: string; kb_sync_pull_blocked: null }
  | { kb_sync_pull_blocked: KbSyncPullBlocked | null };

interface HeldFilterLike {
  eq: (col: string, val: string) => HeldFilterLike;
  or: (filters: string) => HeldFilterLike;
  select: (cols: string) => PromiseLike<{ data: Array<{ id: string }> | null; error: unknown }>;
}

interface HeldColsClientLike {
  from: (table: string) => { update: (row: KbSyncHeldRow) => HeldFilterLike };
}

/** A PostgREST (`PGRST204`) or Postgres SQLSTATE (`42703`) code, or "none": the tag never carries free text. */
function pgCodeOf(err: unknown): string {
  const code = (err as { code?: unknown } | null | undefined)?.code;
  return typeof code === "string" && /^(?:[0-9A-Z]{5}|PGRST\d{3})$/.test(code) ? code : "none";
}

const HELD_OP_MESSAGES = {
  "kb-sync-held.write": "Failed to write the held-files count to the workspace",
  "kb-sync-held.clear": "Failed to clear the held-files columns on the workspace",
  "kb-sync-held.pull-blocked": "Failed to write the pull-blocked state to the workspace",
} as const;

/** Which rows an UPDATE may touch: any (the clear), ready ones (pull-blocked), or ready and older (the count). */
type HeldGuard = { readonly checkedAt: string } | "ready" | null;

/**
 * The ONE held-columns UPDATE body (simplicity F7) behind the write, the pull-blocked write and the clear. Never throws.
 *   - `guard` "ready" (pull-blocked) or `{ checkedAt }` (the count): the row must be `repo_status = 'ready'`, so a
 *     disconnected or re-cloning row is a no-op. The count also needs its stored `checked_at` null or older (D39(f)),
 *     so a stale run is a no-op; a clear stamps `checked_at`, so after one, null means "never written".
 *   - 0 rows matched: expected (a newer or not-ready row, or a deleted workspace). One info line, no mirror.
 *   - an error or a rejection: one pino line every time (layer 2), and one debounced Sentry event on a CONSTANT key
 *     per op and pg code (obs F1), err null with `pg_code` in the tags (obs F9: an Error object would lose `op` to the
 *     pino-mirror capture). A missing column (an apply that lags, or a rollback, D33) then costs one event per process
 *     per window, not one per sync.
 */
async function updateKbSyncHeldCols(
  service: HeldColsClientLike,
  workspaceId: string,
  row: KbSyncHeldRow,
  op: keyof typeof HELD_OP_MESSAGES,
  guard: HeldGuard,
): Promise<void> {
  let failure: { pgCode: string; errName: string } | null = null;
  try {
    let q = service.from("workspaces").update(row).eq("id", workspaceId);
    if (guard !== null) q = q.eq("repo_status", "ready");
    if (guard !== null && guard !== "ready") {
      q = q.or(`kb_sync_held_checked_at.is.null,kb_sync_held_checked_at.lt."${guard.checkedAt}"`);
    }
    const { data, error } = await q.select("id");
    if (error) {
      failure = { pgCode: pgCodeOf(error), errName: "PostgrestError" };
    } else if (!data || data.length === 0) {
      log.info({ op, workspaceId, outcome: "no_row" }, "Held-columns update matched no row (newer, not ready, or gone)");
    }
  } catch (err) {
    failure = { pgCode: pgCodeOf(err), errName: err instanceof Error ? err.name : typeof err };
  }
  if (failure === null) return;
  log.warn({ op, workspaceId, pgCode: failure.pgCode, errName: failure.errName }, HELD_OP_MESSAGES[op]);
  mirrorWithDebounce(
    null,
    {
      feature: "workspace-repo-write",
      op,
      message: HELD_OP_MESSAGES[op],
      tags: { pg_code: failure.pgCode, err_name: failure.errName },
      extra: { workspaceId, pgCode: failure.pgCode, errName: failure.errName },
    },
    op,
    `${op}:${failure.pgCode}`,
  );
}

/**
 * #12714 (D29(1), D33(2), D42): clear the held columns of the workspace (count and pull-blocked null), in a SEPARATE
 * best-effort UPDATE that the disconnect and setup routes run apart from their own repo-column write. A held count
 * describes one connection, so it must not reappear after a reconnect. No freshness guard: the clear always applies.
 *
 * `checked_at` is STAMPED with the clear's instant, never nulled (verify-data-sec P3-3): a null count shows nothing,
 * and a run that read `T` before the clear (a legacy session still in flight across a disconnect and reconnect, or a
 * setup re-clone) carries an older `checkedAt`, so it loses the D39(f) `lt` guard once the row is `ready` again instead
 * of passing its `is.null` branch. Every write that read `T` after the clear is newer and lands.
 *
 * Never throws: a failure (a missing column during an apply that lags, or after a rollback) is mirrored (debounced) and
 * leaves the route's status and response unchanged. A missing column also means no count was ever stored.
 */
export async function clearKbSyncHeldCols(service: HeldColsClientLike, workspaceId: string): Promise<void> {
  await updateKbSyncHeldCols(
    service,
    workspaceId,
    { kb_sync_held_files: null, kb_sync_held_checked_at: new Date().toISOString(), kb_sync_pull_blocked: null },
    "kb-sync-held.clear",
    null,
  );
}

/**
 * #12714 (D42, verify-data-sec P3-4): write why the self-heal cannot bring the workspace up to date (null = it can).
 * Its OWN UPDATE, guarded only by `repo_status = 'ready'`: the state is the latest self-heal or pull verdict on the
 * workspace, not a property of one count, so ordering it by the count's `checked_at` would let an unrelated newer count
 * write drop a set or a clear. A disconnected or re-cloning row is untouched (the clear owns it then). Same R2 exemption
 * and caller contract as `writeKbSyncHeldCols` (a server-resolved workspace id, display-only, read by no gate). A value
 * outside the closed set writes nothing. Never throws.
 */
export async function writeKbSyncPullBlocked(
  service: HeldColsClientLike,
  workspaceId: string,
  value: KbSyncPullBlocked | null,
): Promise<void> {
  if (value !== null && !PULL_BLOCKED_VALUES.has(value)) {
    log.warn({ op: "kb-sync-held.pull-blocked", workspaceId }, "Pull-blocked write skipped: not a closed value");
    return;
  }
  await updateKbSyncHeldCols(service, workspaceId, { kb_sync_pull_blocked: value }, "kb-sync-held.pull-blocked", "ready");
}

/**
 * #12714 (D29(1), D33, D39(b)/(f)): write the held-files count (null = a count was attempted and failed) and the
 * instant the run read `T` (the pull-blocked state is `writeKbSyncPullBlocked`'s). A SEPARATE service-client UPDATE, never folded into
 * the `repo_last_synced_at` stamp, so a missing column fails only this write. Last writer wins by `checkedAt`, never by
 * arrival: an older run, or a row that is not `ready` (disconnected, or re-cloning after a setup clear), matches 0 rows.
 *
 * R2 exemption (D45(b)): no workspace-membership re-check before this service-role write. The value is display-only,
 * derived from the same workspace's own files, and read by no gate (test/kb-sync-held-readers-census.test.ts pins the
 * readers); the `repo_status = 'ready'` guard is the added bound. The caller passes a server-resolved workspace id (the
 * agent-runner's membership-verified one, or a background job's own row), never a request-supplied one.
 *
 * Never throws.
 */
export async function writeKbSyncHeldCols(
  service: HeldColsClientLike,
  workspaceId: string,
  patch: KbSyncHeldPatch,
): Promise<void> {
  if (!(patch.checkedAt instanceof Date) || Number.isNaN(patch.checkedAt.getTime())) {
    // A caller bug, not a database state: no instant to order by, so nothing is written (never throws).
    log.warn({ op: "kb-sync-held.write", workspaceId }, "Held-files write skipped: checkedAt is not a valid instant");
    return;
  }
  const checkedAt = patch.checkedAt.toISOString();
  const row: KbSyncHeldRow = { kb_sync_held_files: patch.heldFiles, kb_sync_held_checked_at: checkedAt };
  await updateKbSyncHeldCols(service, workspaceId, row, "kb-sync-held.write", { checkedAt });
}

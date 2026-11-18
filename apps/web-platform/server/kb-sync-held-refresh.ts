// ---------------------------------------------------------------------------
// KB sync held count: the one compute-and-write path of `workspaces.kb_sync_held_files` (#12714, rulings D39(a)/(b)/(f),
// D42, D43).
//
// - `writeHeldFromIsolated`: the count on an isolated dir a caller already holds (syncPull, syncPush's `onHeldFiles`,
//   the self-heal), over that caller's own `T`, written with `checkedAt` = the instant the caller read `T`. Every
//   attempt writes (W1 binding, D39(b)): a failed count writes null, with its `checked_at` and one `kb-sync.held-files`
//   line naming the closed `nullCause`. The self-heal also passes `pullBlocked` (D42) into the same guarded UPDATE.
// - `refreshHeldCount`: the standalone refresh the cc runner calls after a turn (repo URL, isolated dir, hardened
//   `ls-remote`, compute, write, dispose), single-flight per workspace per process.
// - `heldCountOn` / `writeHeldCount`: the pre-review entries session-sync still calls (moved here in review Phase 0).
//   They share the count and the write with the two above; they go when session-sync calls `writeHeldFromIsolated`.
//
// Service role: the held columns have no UPDATE policy (migration 187, RLS 053), so the write uses the service client.
// This file is on `.service-role-allowlist` for exactly that write and the D43 system read of `repo_url`, both keyed on a
// server-resolved workspace id. All of it is display-only and never throws.
// ---------------------------------------------------------------------------

import type { SupabaseClient } from "@supabase/supabase-js";

import { getServiceClient } from "@/lib/supabase/service";
import { readWorkspaceHeadRef } from "./approval/workspace-head";
import { disposeIsolated } from "./git-isolated-dispose";
import { createIsolatedPushDir, IsolatedPushDirRefusal, type IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { computeHeldFiles, logHeldFiles, readRecoveredKbSyncTips, type HeldFiles } from "./kb-sync-held";
import { isCommitPresent } from "./kb-sync-objects";
import { KbRemoteError, parseOwnerRepo, readRemoteState, resolveRepoUrl } from "./kb-sync-remote";
import { createChildLogger } from "./logger";
import { mirrorWarnWithDebounce } from "./observability";
import { writeKbSyncHeldCols, type KbSyncHeldPatch, type KbSyncPullBlocked } from "./workspace-repo-mirror";

const log = createChildLogger("kb-sync-held");

/** A computed held-files count and when it was computed. */
export interface HeldCount extends HeldFiles {
  readonly checkedAt: string;
}

/**
 * The count on `isolated` over `base...head` plus the set-aside tips, or null. When the set-aside refs cannot be read
 * safely the count is `recovered_unreadable`: logged like every other null, and ALSO a debounced warning, because that
 * state is persistent for the workspace (an oversized `packed-refs`, a reftable repo; obs F6). Never throws.
 */
async function countOn(
  isolated: IsolatedPushDirHandle,
  base: string,
  head: string,
  workspacePath: string,
  workspaceId: string,
  budgetMs: number | undefined,
): Promise<HeldFiles | null> {
  try {
    const recovered = readRecoveredKbSyncTips(workspacePath, { workspaceId });
    if (recovered === null) {
      logHeldFiles(null, "recovered_unreadable", workspaceId);
      mirrorWarnWithDebounce(
        null,
        {
          feature: "kb-sync-held",
          op: "kb-sync-held.count",
          message: "The set-aside branch refs could not be read safely; the held count is unknown",
          tags: { null_cause: "recovered_unreadable" },
          extra: { workspaceId },
        },
        workspaceId,
        "kb-sync-held.count:recovered_unreadable",
      );
      return null;
    }
    return await computeHeldFiles(
      { isolated, base, head, recovered, workspaceId },
      budgetMs === undefined ? {} : { budgetMs },
    );
  } catch (err) {
    log.warn({ workspaceId, errName: err instanceof Error ? err.name : typeof err }, "Held-files count failed");
    return null;
  }
}

/** The one call into the writer: every path here writes through it. Never throws. */
async function persist(service: () => SupabaseClient, workspaceId: string, patch: KbSyncHeldPatch): Promise<void> {
  try {
    await writeKbSyncHeldCols(service(), workspaceId, patch);
  } catch (err) {
    // writeKbSyncHeldCols never throws by contract; this keeps a broken client (or a missing service env) from
    // changing the caller's result.
    log.warn({ workspaceId, errName: err instanceof Error ? err.name : typeof err }, "Held-files write threw");
  }
}

/**
 * #12714 (W1, W2, W4, D29(1)): the pre-review count entry session-sync calls. Null when no count was computed (the
 * cause is logged); never throws.
 */
export async function heldCountOn(
  isolated: IsolatedPushDirHandle,
  base: string,
  head: string,
  workspacePath: string,
  workspaceId: string,
): Promise<HeldCount | null> {
  const held = await countOn(isolated, base, head, workspacePath, workspaceId, undefined);
  return held === null ? null : { total: held.total, onRecovered: held.onRecovered, checkedAt: new Date().toISOString() };
}

/** The pre-review write entry session-sync calls with its injected service client (D29(1)). Never throws. */
export async function writeHeldCount(service: SupabaseClient, workspaceId: string, held: HeldCount): Promise<void> {
  await persist(() => service, workspaceId, { heldFiles: held.total, checkedAt: new Date(held.checkedAt) });
}

/**
 * D39(a)/(b)/(f), D42: the held count on an isolated dir the caller already holds, over its own `T`, written with
 * `checkedAt` (the instant the caller read `T`, `RemoteState.readAt`) through the guarded UPDATE: last writer by
 * `checkedAt` wins and a row that is not `ready` is untouched. A failed count writes null. `pullBlocked` undefined leaves
 * that column as it is. Returns the stored total, or null. Never throws.
 */
export async function writeHeldFromIsolated(a: {
  readonly isolated: IsolatedPushDirHandle;
  readonly workspacePath: string;
  readonly workspaceId: string;
  readonly T: string;
  readonly headSha: string;
  readonly checkedAt: Date;
  readonly pullBlocked?: KbSyncPullBlocked | null;
  readonly budgetMs?: number;
}): Promise<number | null> {
  const held = await countOn(a.isolated, a.T, a.headSha, a.workspacePath, a.workspaceId, a.budgetMs);
  const total = held === null ? null : held.total;
  await persist(getServiceClient, a.workspaceId, {
    heldFiles: total,
    checkedAt: a.checkedAt,
    ...(a.pullBlocked !== undefined ? { pullBlocked: a.pullBlocked } : {}),
  });
  return total;
}

type RefreshArgs = {
  readonly workspaceId: string;
  readonly workspacePath: string;
  readonly installationId: number;
  readonly userId?: string;
};

/** Why a refresh wrote nothing (a closed `outcome` on the `kb-sync-held.refresh` info line). */
type RefreshSkip =
  | "not_ready"
  | "no_installation"
  | "head_unreadable"
  | "isolated_refused"
  | "remote_unreadable"
  | "remote_branch_absent"
  | "tip_absent";

const inflight = new Map<string, Promise<void>>();

function logRefresh(workspaceId: string, outcome: RefreshSkip | "written"): void {
  log.info({ op: "kb-sync-held.refresh", workspaceId, outcome }, "kb sync held count refresh");
}

/**
 * The repo URL (R2: the literal `https://github.com/<owner>/<repo>.git` from the workspace row). With `userId`, the
 * tenant-scoped read (`resolveRepoUrl`). Without it (a system caller, D43), a service read keyed on the job's own
 * workspace id with `repo_status = 'ready'`, and no tenant token is minted. Null when there is no ready, valid row.
 */
async function refreshRepoUrl(a: RefreshArgs): Promise<string | null> {
  if (a.userId !== undefined) {
    try {
      return (await resolveRepoUrl(a.userId, a.workspaceId)).url;
    } catch (err) {
      if (err instanceof KbRemoteError) return null;
      throw err;
    }
  }
  const { data, error } = await getServiceClient()
    .from("workspaces")
    .select("repo_url")
    .eq("id", a.workspaceId)
    .eq("repo_status", "ready")
    .maybeSingle();
  if (error) throw Object.assign(new Error("repo_url service read failed"), { name: "RepoUrlReadError" });
  const { owner, repo } = parseOwnerRepo((data as { repo_url?: string | null } | null)?.repo_url ?? null);
  return owner && repo ? `https://github.com/${owner}/${repo}.git` : null;
}

async function runRefresh(a: RefreshArgs): Promise<void> {
  if (!Number.isSafeInteger(a.installationId) || a.installationId <= 0) return logRefresh(a.workspaceId, "no_installation");
  const url = await refreshRepoUrl(a);
  if (url === null) return logRefresh(a.workspaceId, "not_ready");
  let headSha: string;
  try {
    headSha = readWorkspaceHeadRef(a.workspacePath).sha;
  } catch {
    return logRefresh(a.workspaceId, "head_unreadable");
  }
  let isolated: IsolatedPushDirHandle | undefined;
  try {
    try {
      isolated = createIsolatedPushDir(a.workspacePath);
    } catch (err) {
      if (err instanceof IsolatedPushDirRefusal) return logRefresh(a.workspaceId, "isolated_refused");
      throw err;
    }
    let remote;
    try {
      remote = await readRemoteState(isolated, a.installationId, url);
    } catch (err) {
      if (err instanceof KbRemoteError) return logRefresh(a.workspaceId, "remote_unreadable");
      throw err;
    }
    if (remote === null) return logRefresh(a.workspaceId, "remote_branch_absent");
    // No fetch here (the cost is one ls-remote). A `T` the workspace does not have yet belongs to the next sync or
    // self-heal, which fetch it and write the count against it; a null written here would erase that count.
    if (!(await isCommitPresent(isolated, remote.tip))) return logRefresh(a.workspaceId, "tip_absent");
    await writeHeldFromIsolated({
      isolated,
      workspacePath: a.workspacePath,
      workspaceId: a.workspaceId,
      T: remote.tip,
      headSha,
      checkedAt: remote.readAt,
    });
    logRefresh(a.workspaceId, "written");
  } finally {
    disposeIsolated(isolated);
  }
}

/**
 * D39(a), D43: the standalone held-count refresh (repo URL, isolated dir, hardened `readRemoteState`, compute, write,
 * dispose), called by the cc runner after a turn. Single-flight per workspace per process: a call while one runs gets
 * that run's promise. Skipped (nothing written) when the repo is not ready, no installation is given, or no count can
 * be attempted. Without `userId` it mints no tenant token. Never throws (rejects never).
 */
export function refreshHeldCount(a: RefreshArgs): Promise<void> {
  const running = inflight.get(a.workspaceId);
  if (running) return running;
  const run = (async () => {
    try {
      await runRefresh(a);
    } catch (err) {
      const errName = err instanceof Error ? err.name : typeof err;
      log.warn({ op: "kb-sync-held.refresh", workspaceId: a.workspaceId, errName }, "Held-count refresh failed");
      mirrorWarnWithDebounce(
        null,
        {
          feature: "kb-sync-held",
          op: "kb-sync-held.refresh",
          message: "The held-count refresh failed",
          tags: { err_name: errName },
          extra: { workspaceId: a.workspaceId, errName },
        },
        a.workspaceId,
        "kb-sync-held.refresh",
      );
    } finally {
      inflight.delete(a.workspaceId);
    }
  })();
  inflight.set(a.workspaceId, run);
  return run;
}

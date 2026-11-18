// ---------------------------------------------------------------------------
// KB sync held count: the one compute-and-write path of `workspaces.kb_sync_held_files` (#12714, rulings D39(a)/(b)/(f),
// D42, D43).
//
// - `writeHeldFromIsolated`: the count on an isolated dir a caller already holds (syncPull, syncPush's `onHeldFiles`,
//   the self-heal), over that caller's own `T`, written with `checkedAt` = the instant the caller read `T`. Every
//   attempt writes (W1 binding, D39(b)): a failed count writes null, with its `checked_at` and one `kb-sync.held-files`
//   line naming the closed `nullCause`. No attempt is made when `T` is not in the isolated dir's object store (the
//   fetch failed or never ran): a null there would erase a good count (verify-coverage P2-2). `pullBlocked` (D42) goes to
//   its own UPDATE (`writeKbSyncPullBlocked`), not ordered by the count's `checked_at` (verify-data-sec P3-4).
// - `refreshHeldCount`: the standalone refresh the cc runner calls after a turn (repo URL, then under the workspace git
//   lock: HEAD, isolated dir, hardened `ls-remote`, compute, write, dispose), single-flight per workspace per process.
//
// Service role: the held columns have no UPDATE policy (migrations 187/188, RLS 053), so the write uses the service client.
// This file is on `.service-role-allowlist` for exactly that write and the D43 system read of `repo_url`, both keyed on a
// server-resolved workspace id. All of it is display-only and never throws.
// ---------------------------------------------------------------------------

import type { SupabaseClient } from "@supabase/supabase-js";

import { normalizeRepoUrl } from "@/lib/repo-url";
import { getServiceClient } from "@/lib/supabase/service";
import { readWorkspaceHeadRef } from "./approval/workspace-head";
import { withWorkspaceGitLock } from "./connected-repo-git";
import { disposeIsolated } from "./git-isolated-dispose";
import { createIsolatedPushDir, IsolatedPushDirRefusal, type IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { computeHeldFiles, HELD_COUNT_BUDGET_MS, logHeldFiles, readRecoveredKbSyncTips, type HeldFiles } from "./kb-sync-held";
import { isCommitPresent } from "./kb-sync-objects";
import { KbRemoteError, parseOwnerRepo, readRemoteState, resolveRepoUrl } from "./kb-sync-remote";
import { createChildLogger } from "./logger";
import { mirrorWarnWithDebounce } from "./observability";
import {
  writeKbSyncHeldCols,
  writeKbSyncPullBlocked,
  type KbSyncHeldPatch,
  type KbSyncPullBlocked,
} from "./workspace-repo-mirror";

const log = createChildLogger("kb-sync-held");

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

/** The one call into the pull-blocked writer (its own UPDATE, guarded only by `repo_status = 'ready'`). Never throws. */
async function persistPullBlocked(
  service: () => SupabaseClient,
  workspaceId: string,
  value: KbSyncPullBlocked | null,
): Promise<void> {
  try {
    await writeKbSyncPullBlocked(service(), workspaceId, value);
  } catch (err) {
    log.warn({ workspaceId, errName: err instanceof Error ? err.name : typeof err }, "Pull-blocked write threw");
  }
}

/** Whether `T` is a commit in the isolated dir's object store; a failed check is "unknown", read as not present. */
async function tipPresent(isolated: IsolatedPushDirHandle, T: string): Promise<boolean> {
  try {
    return await isCommitPresent(isolated, T);
  } catch {
    return false;
  }
}

/**
 * D39(a)/(b)/(f), D42: the held count on an isolated dir the caller already holds, over its own `T`, written with
 * `checkedAt` (the instant the caller read `T`, `RemoteState.readAt`) through the guarded UPDATE: last writer by
 * `checkedAt` wins and a row that is not `ready` is untouched. A failed count writes null.
 *
 * `T` not in this dir's object store (a `fetch_failed`, a `pull_deadline` before the fetch, a `remote_unknown_tip`, or
 * a presence check that cannot answer): no count is attempted and nothing is written, the same skip as the refresh's
 * `tip_absent` (verify-coverage P2-2): the count would fail as `invalid_rev`, and its null, carrying a newer
 * `checked_at`, would win the guard over a good count.
 *
 * `pullBlocked` (a value, or null to clear) goes to its own UPDATE whatever `T`'s presence (it is the caller's verdict on
 * the workspace, not a count over `T`); undefined leaves it as it is. `service` is the caller's injected service
 * client when it has one (session-sync's, from the allowlisted agent-runner, ADR-044 PR-B); without it the process's
 * service client is used. Returns what was computed (`total` is the stored value; `onRecovered` feeds the legacy agent
 * line's recovered clause), or null. Never throws.
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
  readonly service?: SupabaseClient;
}): Promise<HeldFiles | null> {
  const service = a.service;
  const client = service ? () => service : getServiceClient;
  let held: HeldFiles | null = null;
  if (await tipPresent(a.isolated, a.T)) {
    held = await countOn(a.isolated, a.T, a.headSha, a.workspacePath, a.workspaceId, a.budgetMs);
    await persist(client, a.workspaceId, { heldFiles: held === null ? null : held.total, checkedAt: a.checkedAt });
  } else {
    log.info({ op: "kb-sync-held.write", workspaceId: a.workspaceId, outcome: "tip_absent" }, "Held count skipped: T is not in the object store");
  }
  if (a.pullBlocked !== undefined) await persistPullBlocked(client, a.workspaceId, a.pullBlocked);
  return held;
}

/** How long the refresh waits for the workspace git lock before it gives up quietly (a sync or self-heal holds it). */
export const REFRESH_LOCK_WAIT_MS = 5_000;

type RefreshTarget = {
  readonly workspaceId: string;
  readonly workspacePath: string;
  readonly installationId: number;
};

/**
 * Who the refresh runs for (verify-data-sec P3-5), the explicit discriminant `SyncWorkspaceContext` uses: a user (the
 * tenant-scoped repo URL read) or a system caller (the D43 service read, no tenant token). Never decided by a missing
 * field: an argument with neither (or both) is refused by the type, and skipped at run time.
 */
type RefreshArgs = RefreshTarget & ({ readonly userId: string; readonly system?: undefined } | { readonly system: true; readonly userId?: undefined });

/**
 * The bounded lock call (R2-B's `withWorkspaceGitLock(path, fn, { waitMs })`). Until that option lands the extra argument
 * is ignored at run time (an unbounded wait, as every other locked body); the expiry is handled either way: a rejection
 * before the body, or a return without running it, is the quiet `lock_busy` skip.
 */
function lockWithWait<T>(path: string, fn: () => Promise<T>, opts: { readonly waitMs: number }): Promise<T> {
  // read at call time, not module load: a test double of connected-repo-git need not define the lock to import this file
  const lock = withWorkspaceGitLock as <U>(p: string, f: () => Promise<U>, o: { readonly waitMs: number }) => Promise<U>;
  return lock(path, fn, opts);
}

/** Why a refresh wrote nothing (a closed `outcome` on the `kb-sync-held.refresh` info line). */
type RefreshSkip =
  | "no_actor"
  | "lock_busy"
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
 * The repo URL (R2: the literal `https://github.com/<owner>/<repo>.git` from the workspace row). A user caller: the
 * tenant-scoped read (`resolveRepoUrl`). A system caller (D43): a service read keyed on the job's own workspace id with
 * `repo_status = 'ready'`, normalized like the self-heal's system read (`resolveSelfHealRepoUrl`), and no tenant token
 * is minted. Null when there is no ready, valid row.
 */
async function refreshRepoUrl(a: RefreshArgs): Promise<string | null> {
  if (!a.system) {
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
  const raw = (data as { repo_url?: unknown } | null)?.repo_url;
  if (typeof raw !== "string") return null;
  const { owner, repo } = parseOwnerRepo(normalizeRepoUrl(raw));
  return owner && repo ? `https://github.com/${owner}/${repo}.git` : null;
}

/** Exactly one of `system: true` or a non-empty `userId` (the run-time half of the discriminant). */
function hasActor(a: RefreshArgs): boolean {
  const userId: unknown = a.userId;
  return a.system === true ? userId === undefined : typeof userId === "string" && userId.length > 0;
}

async function runRefresh(a: RefreshArgs): Promise<void> {
  if (!hasActor(a)) return logRefresh(a.workspaceId, "no_actor");
  if (!Number.isSafeInteger(a.installationId) || a.installationId <= 0) return logRefresh(a.workspaceId, "no_installation");
  const url = await refreshRepoUrl(a);
  if (url === null) return logRefresh(a.workspaceId, "not_ready");
  // verify-coverage P3-4: HEAD, the ls-remote, the count and the write run under the workspace git lock, so a count
  // never reads the HEAD a concurrent merge is about to move (its stale result would win the guard over the merge's).
  let entered = false;
  try {
    await lockWithWait(
      a.workspacePath,
      async () => {
        entered = true;
        await refreshLocked(a, url);
      },
      { waitMs: REFRESH_LOCK_WAIT_MS },
    );
  } catch (err) {
    if (entered) throw err;
    return logRefresh(a.workspaceId, "lock_busy");
  }
  if (!entered) logRefresh(a.workspaceId, "lock_busy");
}

async function refreshLocked(a: RefreshArgs, url: string): Promise<void> {
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
      budgetMs: HELD_COUNT_BUDGET_MS,
    });
    logRefresh(a.workspaceId, "written");
  } finally {
    disposeIsolated(isolated, "kb-sync-held"); // simplicity H3: the refresh's own feature, as its other mirrors
  }
}

/**
 * D39(a), D43: the standalone held-count refresh (repo URL; then, under the workspace git lock with a bounded wait:
 * HEAD, isolated dir, hardened `readRemoteState`, compute on the held-count budget, write, dispose), called by the cc
 * runner after a turn. Single-flight per workspace per process: a call while one runs gets that run's promise. Skipped
 * (nothing written) when the caller is neither a user nor a system job, the repo is not ready, no installation is given,
 * the lock stays busy, or no count can be attempted. A system caller mints no tenant token. Never writes the
 * pull-blocked state. Never throws (rejects never).
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

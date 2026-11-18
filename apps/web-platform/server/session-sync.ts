// ---------------------------------------------------------------------------
// Session sync: pull before session, push after session
//
// Keeps the user's workspace in sync with their connected GitHub repo.
// All operations are best-effort — failures are logged but never block
// the agent session.
// ---------------------------------------------------------------------------

import { readdirSync } from "fs";
import { join } from "path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import {
  hashUserId,
  mirrorWarnWithDebounce,
  mirrorWithDebounce,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { firstAppFrame } from "./error-frame";
import { disposeIsolated } from "./git-isolated-dispose";
import { createIsolatedPushDir, IsolatedPushDirRefusal, type IsolatedPushDirHandle } from "./git-isolated-push-dir";
import {
  kbPullWriter,
  kbWorkspaceWriter,
  mergeInProgress,
  mirrorGitRefusal,
  pinInterruptedAutostash,
  readStatus,
  runConnectedRepoGitAsync,
  withWorkspaceGitLock,
  WORKSPACE_GIT_LOCK_TIMEOUT,
  type PorcelainEntry,
} from "./connected-repo-git";
import { HostGitRefusedError } from "./host-git";
import { KB_ROOT } from "./kb-root";
import { writeHeldFromIsolated } from "./kb-sync-held-refresh";
import { KbSyncError, publishKbOnly, reportPushHeld, SYNC_PUSH_BUDGET_MS, type PushBudget } from "./kb-sync-publish";
import {
  adoptSideTip,
  KB_PULL_HELD_MESSAGES,
  KB_PULL_HELD_OP,
  MERGE_START_MIN_MS,
  mergeVerifiedDefault,
  pullBudget,
  SYNC_PULL_BUDGET_MS,
  type KbPullHeldReason,
  type KbPullLimits,
  type KbPullRef,
  type KbPullStep,
  type PullBudget,
} from "./kb-sync-pull";
import { KbRemoteError, resolveRepoUrl } from "./kb-sync-remote";
import { readWorkspaceHeadRef } from "./approval/workspace-head";
import { writeRepoColsToWorkspace } from "./workspace-repo-mirror";
import { createChildLogger } from "./logger";

const log = createChildLogger("session-sync");

// Path-allowlist for the auto-commit sweep. Only paths under
// `knowledge-base/` (`KB_ROOT`) are eligible for automatic staging during syncPull/syncPush.
// Everything else (`.claude/`, `.github/`, `apps/`, root config files, ...)
// is left dirty in the working tree so it never lands in PRs the loop did
// not explicitly author. See #2905 for the failure modes this prevents.
const isAllowlistedPath = (path: string): boolean => path.startsWith(`${KB_ROOT}/`);

// Auto-commit headlines used by syncPull / syncPush. Exported as named
// constants so .github/scripts/check-auto-commit-density.sh can stay in
// sync (the regex there must reference these exact strings).
export const AUTO_COMMIT_MSG_PULL = "Auto-commit before sync pull";
export const AUTO_COMMIT_MSG_PUSH = "Auto-commit after session";

/**
 * What a failed auto-commit may carry to Sentry: the stage, the exit status and a CLOSED stderr bucket, never the
 * raw error (its message is the full argv, which names tenant file paths, plus git's stderr). The raw error stays in
 * the local `log.warn`. `null` = nothing to report (an empty commit is not a failure).
 */
function autoCommitFailure(err: unknown, stage: "pull" | "push"): Error | null {
  if (err instanceof HostGitRefusedError) return new Error(`auto-commit-${stage} refused: ${err.reason}`);
  const e = err as { status?: number; stdout?: unknown; stderr?: unknown };
  const text = `${String(e?.stdout ?? "")}\n${String(e?.stderr ?? "")}`;
  let bucket = "other";
  if (/nothing (added )?to commit|no changes added to commit/i.test(text)) return null;
  if (/Author identity unknown|unable to auto-detect email/i.test(text)) bucket = "identity";
  else if (/index\.lock/i.test(text)) bucket = "index-lock";
  else if (/not a git repository/i.test(text)) bucket = "not-a-repository";
  else if (/Permission denied|Operation not permitted/i.test(text)) bucket = "permission";
  return new Error(`auto-commit-${stage} failed (exit ${typeof e?.status === "number" ? e.status : "unknown"}, ${bucket})`);
}

const allowlisted = (entries: readonly PorcelainEntry[] | null): string[] =>
  (entries ?? []).filter((e) => isAllowlistedPath(e.path)).map((e) => e.path);

/** The changed paths under `knowledge-base/`, from one status run (the auto-commit's allowlist, #2905). */
export async function getAllowlistedChanges(workspacePath: string): Promise<string[]> {
  return allowlisted(await readStatus(workspacePath, "getAllowlistedChanges"));
}

// PR-C §2.1 (#3244): all four `.from("users")` sites in this file migrate
// from service-role to tenant-scoped (RLS `auth.uid() = id` on `users`).
// Module-level lazy service-role cache is gone — `getFreshTenantClient`
// has its own per-userId TTL cache, so per-call mint cost is bounded
// regardless of fan-out. Offline-dev (no SUPABASE_SERVICE_ROLE_KEY) now
// surfaces as a `RuntimeAuthError` thrown from `getFreshTenantClient`,
// caught by the outer `syncPull`/`syncPush` try/catch (this file's
// best-effort contract — failures never block the agent session).

/**
 * Per-handler RLS-baseline probe. Plan §0.4 form throws
 * `RuntimeAuthError` on probe failure; `session-sync`'s best-effort
 * contract (file header: "failures are logged but never throw") means
 * we mirror to Sentry and return `false` instead, letting the entry
 * function early-return cleanly. Same probe semantics, different
 * failure mode for this file. See learning
 * `2026-04-12-silent-rls-failures-in-team-names` for why this is
 * load-bearing distinct from the implicit `getFreshTenantClient` mint:
 * a cached JWT inside the TTL window does not re-run `precheck_jwt_mint`,
 * so a mid-session jti revocation or RLS policy churn would otherwise
 * silently return zero rows on the first real read.
 */
async function authProbe(userId: string, op: string): Promise<boolean> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const { error: probeErr } = await tenant
      .from("users")
      .select("id")
      .eq("id", userId)
      .maybeSingle();
    if (probeErr) {
      reportSilentFallback(probeErr, {
        feature: "session-sync",
        op: `auth-probe.${op}`,
        extra: { userId },
      });
      return false;
    }
    return true;
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      reportSilentFallback(err, {
        feature: "session-sync",
        op: `auth-probe.${op}`,
        extra: { userId },
      });
      return false;
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function hasRemote(workspacePath: string): Promise<boolean> {
  try {
    const result = await runConnectedRepoGitAsync(["remote", "-v"], { cwd: workspacePath });
    return result.toString().trim().length > 0;
  } catch (err) {
    mirrorGitRefusal(err, "hasRemote");
    return false;
  }
}

async function hasLocalCommits(workspacePath: string): Promise<boolean> {
  try {
    // Check if there are commits ahead of the remote tracking branch
    const result = await runConnectedRepoGitAsync(["rev-list", "--count", "@{u}..HEAD"], { cwd: workspacePath });
    return parseInt(result.toString().trim(), 10) > 0;
  } catch (outer) {
    if (mirrorGitRefusal(outer, "hasLocalCommits")) return false;
    // No upstream tracking branch — if we have any commits at all, attempt push.
    // This handles the case where auto-commit created local commits but no
    // upstream tracking branch is set (first push after clone).
    try {
      const result = await runConnectedRepoGitAsync(["rev-list", "--count", "HEAD"], { cwd: workspacePath });
      return parseInt(result.toString().trim(), 10) > 0;
    } catch {
      return false;
    }
  }
}

/** D45(a): the installation of the caller's ONE resolved workspace (never a user-level guess; the #5435 divergence). */
async function getInstallationId(userId: string, workspaceId: string): Promise<number | null> {
  const { resolveInstallationId } = await import(
    "@/server/resolve-installation-id"
  );
  return resolveInstallationId(userId, workspaceId);
}

/**
 * Recursively count .md files in a directory.
 * Returns 0 if the directory does not exist.
 */
export function countMdFiles(dirPath: string): number {
  let count = 0;
  try {
    const entries = readdirSync(dirPath, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = join(dirPath, entry.name);
      if (entry.isDirectory()) {
        count = count + countMdFiles(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        count = count + 1;
      }
    }
  } catch {
    // Directory does not exist or is not readable
  }
  return count;
}

/**
 * Record the current KB file count in the user's kb_sync_history JSONB array.
 * Trims to the last 14 entries (the RPC's `p_cap: 14` reproduces the old
 * `.slice(-14)` — read-merge-cap happens inside the function under a
 * row-level lock). Best-effort — failures are logged and mirrored to Sentry
 * via `reportSilentFallback`, never thrown.
 *
 * #11193: routed through the `append_kb_sync_row` SECURITY DEFINER RPC
 * (migration 053) — the same instrumented path `appendKbSyncRow` below uses.
 * Migration 178 re-narrows `users` to SELECT + column-level UPDATE on the
 * Note C census set, and migration 017's RESTRICTIVE policy pins
 * kb_sync_history for any authenticated UPDATE regardless of grants, so a
 * direct `.update({ kb_sync_history })` cannot survive the narrow. The RPC
 * is the only tenant-callable write path (it also removes the lost-update
 * race the JS-side fetch + update had under concurrent sync calls).
 */
async function recordKbSyncHistory(
  userId: string,
  workspacePath: string,
): Promise<void> {
  // PR-C §2.1 (#3244): tenant-scoped client (authenticated role).
  const tenant = await getFreshTenantClient(userId);
  const kbPath = join(workspacePath, KB_ROOT);
  const fileCount = countMdFiles(kbPath);
  const today = new Date().toISOString().slice(0, 10);

  const { error } = await tenant.rpc("append_kb_sync_row", {
    p_row: { date: today, count: fileCount } satisfies LegacyKbSyncRow,
    p_cap: 14,
  });

  if (error) {
    reportSilentFallback(error, {
      feature: "session-sync",
      op: "appendKbSyncRow",
      extra: { userId },
      message: "append_kb_sync_row RPC failed (recordKbSyncHistory)",
    });
    return;
  }
  const uidHash = hashUserId(userId);
  log.debug({ userIdHash: uidHash, fileCount }, "Recorded KB sync history");
}

// #4224 — shared constants for the workspace-reconcile feature.
// Re-exported from the Inngest function module too so test files and
// future consumers have one source of truth.
export const WORKSPACE_RECONCILE_REQUESTED_EVENT =
  "platform/workspace.reconcile.requested" as const;
// Bumped "1"→"2" (ADR-044): the reconcile payload now carries
// `fullName` (repository.full_name) so the consumer can fan out to all
// workspaces matching the repo. Adding a consumer-read field is a schema-
// boundary change; in-flight v=1 events (lacking fullName) drain to
// {ok:false} via the non-throwing schema-gate rather than syncing with a
// missing field. See 2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.
//
// Bumped "2"→"3" (ADR-044 Amendment 2026-06-17b): `founderId` removed from
// the payload (it was vestigial — the consumer re-derives workspaces from
// (installation_id, repo_url) and never read it for routing). Dropping a
// payload field is a schema-boundary change; in-flight v=2 events deadletter
// via the non-throwing schema-gate and the next push re-drives (reconcile is
// idempotent by (installation_id, repo_url)). See plan R6/P2-3.
export const WORKSPACE_RECONCILE_SCHEMA_V = "3" as const;
export const WORKSPACE_RECONCILE_SENTRY_FEATURE =
  "workspace-reconcile-push" as const;

// kb_sync_history error_class literals. Load-bearing for the 30-day drift
// analysis (TR4 / DS1 gating in plan §Phase 5).
export const ERROR_CLASS_NON_FAST_FORWARD = "non_fast_forward" as const;
export const ERROR_CLASS_WORKSPACE_NOT_READY = "workspace_not_ready" as const;
export const ERROR_CLASS_SYNC_FAILED = "sync_failed" as const;
export type KbSyncErrorClass =
  | typeof ERROR_CLASS_NON_FAST_FORWARD
  | typeof ERROR_CLASS_WORKSPACE_NOT_READY
  | typeof ERROR_CLASS_SYNC_FAILED;

/**
 * Rich kb_sync_history row shape used by webhook-push reconcile (#4224)
 * and the manual /api/kb/sync route. Heterogeneous with the legacy
 * `{ date, count }` shape produced by `recordKbSyncHistory` — the reader
 * (KbSyncStatus) discriminates inline.
 */
export type KbSyncRow = {
  at: string; // ISO timestamp; anchored to sync_completed_at semantics
  // "reconcile_backfill" (#5689 item 2): a system-initiated sync that arm-1 of
  // cron-workspace-sync-health fires immediately after backfilling a missing
  // github_installation_id — truthfully distinct from a user-driven "webhook_push".
  // Write-only label (no reader switches on `trigger`); free-form JSONB, no migration.
  trigger: "webhook_push" | "manual" | "session" | "reconcile_backfill";
  sha_before?: string;
  sha_after?: string;
  ok: boolean;
  error_class?: KbSyncErrorClass;
  // #self-heal (kb-sync-affordance-reconcile) — set true on an ok:true row
  // when the self-heal (server/workspace-sync.ts `selfHealNonFastForward`)
  // recovered a diverged clone (a `reset --keep` to the verified default tip,
  // after branching any local commits aside) rather than a clean fast-forward.
  // Absent on clean syncs and all legacy rows. Keeps the forensic trail
  // distinguishing a recovery from a normal sync.
  recovered?: boolean;
  push_received_at?: number; // Unix ms — only set on webhook_push rows
  sync_completed_at: number; // Unix ms
  // #4728 — workspace discriminator. Set by the webhook-push reconcile
  // producer (workspace-reconcile-on-push.ts), where the iterated
  // workspace id is in scope. Absent on manual-route rows and on all
  // legacy rows; a missing value reads as legacy-single-workspace.
  workspace_id?: string;
};

/** Legacy daily-count row shape produced by `recordKbSyncHistory`. */
export type LegacyKbSyncRow = { date: string; count: number };

const KB_SYNC_HISTORY_CAP = 100;

/**
 * Append a rich `KbSyncRow` to the user's `kb_sync_history` JSONB array,
 * preserving any legacy `{ date, count }` rows already there. Caps at 100.
 * Best-effort — failures are mirrored to Sentry via `reportSilentFallback`
 * but do not throw.
 *
 * Implementation routes through the `append_kb_sync_row` SECURITY DEFINER
 * RPC (migration 053). Direct UPDATE on `kb_sync_history` is blocked by
 * migration 006's column grant (authenticated has UPDATE(email) only) and
 * migration 017's RESTRICTIVE policy; the RPC is the only tenant-callable
 * write path. The RPC also makes the read-modify-write atomic under a
 * row-level lock, removing the lost-update race that a JS-side fetch +
 * update would have under concurrent webhook + manual sync calls.
 *
 * NOTE: `recordKbSyncHistory` is intentionally NOT widened — its
 * `{date,count}` shape continues to serve the daily-count sparkline; this
 * new helper writes the per-event reconciliation rows.
 */
export async function appendKbSyncRow(
  userId: string,
  row: KbSyncRow,
): Promise<void> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const { error } = await tenant.rpc("append_kb_sync_row", {
      p_row: row,
      p_cap: KB_SYNC_HISTORY_CAP,
    });
    if (error) {
      reportSilentFallback(error, {
        feature: "session-sync",
        op: "appendKbSyncRow",
        extra: { userId },
        message: "append_kb_sync_row RPC failed",
      });
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "session-sync",
      op: "appendKbSyncRow",
      extra: { userId },
      message: "kb_sync_history append failed",
    });
  }
}

/**
 * #4906 — append a `KbSyncRow` to a workspace's *backing user's*
 * `kb_sync_history`, keyed by `workspaceId` rather than by an authenticated
 * caller. Used by the owner-less reconcile path
 * (`workspace-reconcile-on-push.ts`), which runs in the Inngest worker with no
 * user JWT — so `auth.uid()` is null and `appendKbSyncRow` (the tenant RPC)
 * cannot be used.
 *
 * Routes through the `append_kb_sync_row_for_user` SECURITY DEFINER RPC
 * (migration 100), which is `service_role`-only. The caller passes the
 * service-role `client` in — session-sync.ts must NOT itself acquire a
 * service-role client (it was migrated to tenant-only in PR-C #3244 and removed
 * from `.service-role-allowlist`; the privilege-acquisition site stays in the
 * allowlisted handler). For solo workspaces `workspaces.id = users.id`
 * (ADR-038 N2), so `workspaceId` resolves directly to the backing user row and
 * the audit row lands exactly as an owner-attributed row would. If `workspaceId`
 * is not a `users.id` (a non-solo / org owner-less workspace — itself an
 * invariant drift), the RPC's UPDATE affects zero rows and no audit row lands;
 * the caller's owner-drift warn still fires, so the anomaly is never silent.
 *
 * Best-effort, mirroring `appendKbSyncRow`: failures are reported to Sentry via
 * `reportSilentFallback` but never throw (the reconcile must not fail on a
 * missing audit row).
 */
export async function appendKbSyncRowForWorkspace(
  client: SupabaseClient,
  workspaceId: string,
  row: KbSyncRow,
): Promise<void> {
  try {
    const { error } = await client.rpc("append_kb_sync_row_for_user", {
      // p_user_id ← workspaceId: solo workspaces.id === users.id (ADR-038 N2).
      // Non-solo ids that don't map to a users row UPDATE 0 rows (no error).
      p_user_id: workspaceId,
      p_row: row,
      p_cap: KB_SYNC_HISTORY_CAP,
    });
    if (error) {
      reportSilentFallback(error, {
        feature: "session-sync",
        op: "appendKbSyncRowForWorkspace",
        extra: { workspaceId },
        message: "append_kb_sync_row_for_user RPC failed",
      });
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "session-sync",
      op: "appendKbSyncRowForWorkspace",
      extra: { workspaceId },
      message: "kb_sync_history workspace-keyed append failed",
    });
  }
}

/**
 * ADR-044 PR-B: write `repo_last_synced_at` to the AUTHORITATIVE
 * `workspaces` row (the repo/status read moved there in PR-2, so a `users`
 * write would freeze the displayed timestamp forever).
 *
 * Signature is `(service, workspaceId)` — NO `userId`, NO internal resolve,
 * NO `userId` fallback. The id is the caller's ONE membership-verified
 * resolution (agent-runner.ts resolves `resolveActiveWorkspace` once and
 * threads the id into BOTH the on-disk path and here), which forbids the
 * #5435 dual-resolver divergence class: a team-active member's write lands on
 * the TEAM workspace, never their solo `userId`. session-sync.ts does NOT
 * acquire a service-role client (it is tenant-only, off `.service-role-allowlist`);
 * the caller injects the service client (writeRepoColsToWorkspace needs it —
 * `workspaces` has no UPDATE RLS policy). Best-effort: writeRepoColsToWorkspace
 * Sentry-mirrors a write error / 0-row no-op but does not throw.
 */
async function updateLastSynced(
  service: SupabaseClient,
  workspaceId: string,
): Promise<void> {
  await writeRepoColsToWorkspace(service, workspaceId, {
    repo_last_synced_at: new Date().toISOString(),
  });
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * One `kb-sync.pull-held` line per session-start pull (D25(6)): an info pino line for every reason, plus a debounced
 * warning mirror (per workspace and reason) for the warning reasons. Tags carry the closed reason and, for a fetch-stage
 * reason, which fetch; no URL, sha, path or branch name.
 */
export function reportPullHeld(
  reason: KbPullHeldReason,
  ctx: { userId: string; workspaceId: string },
  ref?: KbPullRef,
  detail: Pick<KbPullStep, "remoteCause" | "isolatedReason" | "errName" | "frame"> = {},
): void {
  // Closed sub-causes ride as tags (obs F4, F8); the catch-all's class name and first app frame as extra (obs F3).
  const tags = {
    reason,
    ...(ref ? { ref } : {}),
    ...(detail.remoteCause ? { remote_cause: detail.remoteCause } : {}),
    ...(detail.isolatedReason ? { isolated_reason: detail.isolatedReason } : {}),
  };
  const diag = { ...(detail.errName ? { errName: detail.errName } : {}), ...(detail.frame ? { frame: detail.frame } : {}) };
  log.info({ op: KB_PULL_HELD_OP, ...tags, ...diag, workspaceId: ctx.workspaceId }, "KB sync pull outcome");
  const message = KB_PULL_HELD_MESSAGES[reason];
  if (message === null) return;
  mirrorWarnWithDebounce(
    null,
    { feature: "session-sync", op: KB_PULL_HELD_OP, message, tags, extra: { userId: ctx.userId, ...diag } },
    ctx.workspaceId,
    `kb-sync-pull-held:${reason}`,
  );
}

/**
 * What `syncPull` hands its caller (D29(4)): this run's fresh held-files count and the run's reason. The legacy runner
 * builds its agent lines from it (task 11.3b), so it never reads the stored columns.
 * - `heldFiles`: `computeHeldFiles().total`, or null when no count was computed this run (no remote read, a refused or
 *   unreadable state, a git failure). Null is "unknown", never 0.
 * - `onRecovered`: `computeHeldFiles().onRecovered`, null exactly when `heldFiles` is.
 * - `checkedAt`: when the count was computed (ISO 8601, the value written to `kb_sync_held_checked_at`), null with it.
 */
export interface SyncPullResult {
  readonly heldFiles: number | null;
  readonly onRecovered: number | null;
  readonly pullReason: KbPullHeldReason | null;
  readonly checkedAt: string | null;
}

/** The reasons after which the workspace is in sync with GitHub's default branch, so `repo_last_synced_at` is stamped (X1). */
const PULL_STAMPS = new Set<KbPullHeldReason>(["up_to_date", "merged", "autostash_conflict"]);
/** The default-branch reasons after which step 6b (side-tip adoption, D28) runs. */
const PULL_ADOPTS = new Set<KbPullHeldReason>(["up_to_date", "merged"]);

/**
 * Pull GitHub's default branch into the workspace before an agent session (#12718, rulings X1, X4, X5, D25-D28).
 * Best-effort: failures are logged and reported, and it never throws.
 *
 * Order: ONE status run; the shared `mergeInProgress` (a half-done merge refuses `unresolved_merge` BEFORE any auto-commit,
 * with no token minted, D26(1)); the KB auto-commit from the same status; the frozen HEAD; then, in ONE isolated directory,
 * `mergeVerifiedDefault` (server/kb-sync-pull.ts) and, after `merged` or `up_to_date`, the side-tip adoption. The token
 * reaches only the hardened `ls-remote` and fetches against the literal URL; no workspace config, ref or hook takes part.
 * `repo_last_synced_at` is stamped after `up_to_date`, `merged` and `autostash_conflict` (a merge that exited 0). One
 * `kb-sync.pull-held` report per run. After the merge and the adoption, the held-files count (#12714) is computed on the
 * same isolated directory, written through the separate `writeKbSyncHeldCols`, and returned for the legacy runner's
 * agent line.
 */
export async function syncPull(
  userId: string,
  workspacePath: string,
  // ADR-044 PR-B: injected service client + the caller's ONE resolved active
  // workspace id (resolve-id-first; see agent-runner.ts). Threaded straight
  // into `updateLastSynced(service, workspaceId)` — session-sync never
  // re-resolves the workspace (forbids the #5435 dual-resolver divergence).
  service: SupabaseClient,
  workspaceId: string,
  /** `budget` is a test seam (D38(2)); production passes none: `SYNC_PULL_BUDGET_MS` from this call's entry. */
  opts: { readonly limits?: KbPullLimits; readonly budget?: PullBudget } = {},
): Promise<SyncPullResult> {
  // Measured from entry, so the lock wait below counts against it (D38(6)).
  const budget = opts.budget ?? pullBudget(SYNC_PULL_BUDGET_MS, MERGE_START_MIN_MS);
  const none: SyncPullResult = { heldFiles: null, onRecovered: null, pullReason: null, checkedAt: null };
  if (!(await hasRemote(workspacePath))) {
    return none; // Empty workspace, no remote
  }

  // PR-C §2.1 (#3244): per-entry-function RLS-baseline probe — see
  // `authProbe` doc-comment for the load-bearing rationale.
  if (!(await authProbe(userId, "syncPull"))) {
    log.warn({ userIdHash: hashUserId(userId) }, "Sync pull aborted — auth probe failed");
    return none;
  }

  // D38(6): one workspace's git writers run one at a time on this host (a sibling pull never reads this one's in-flight
  // MERGE_AUTOSTASH as an unfinished merge). R2-B (verify-coverage P2-1): the wait races what is left of the budget; a
  // lock that is not free in time is `pull_deadline` and nothing runs under it.
  const locked = await withWorkspaceGitLock(
    workspacePath,
    () => pullLocked(userId, workspacePath, service, workspaceId, opts.limits, budget),
    { waitMs: budget.remaining() },
  );
  if (locked === WORKSPACE_GIT_LOCK_TIMEOUT) {
    reportPullHeld("pull_deadline", { userId, workspaceId }, "default");
    return { ...none, pullReason: "pull_deadline" };
  }
  return locked;
}

async function pullLocked(
  userId: string,
  workspacePath: string,
  service: SupabaseClient,
  workspaceId: string,
  limitsOpt: KbPullLimits | undefined,
  budget: PullBudget,
): Promise<SyncPullResult> {
  const none: SyncPullResult = { heldFiles: null, onRecovered: null, pullReason: null, checkedAt: null };
  const ctx = { userId, workspaceId };
  let isolated: IsolatedPushDirHandle | undefined;
  try {
    // D26(1): ONE status run feeds the unmerged scan and the auto-commit allowlist, and the scan runs first.
    const status = await readStatus(workspacePath, "syncPull");
    if (mergeInProgress(workspacePath, status)) {
      await pinInterruptedAutostash(workspacePath); // D36(c): a stranded autostash survives gc until #12719 recovers it
      reportPullHeld("unresolved_merge", ctx);
      return { ...none, pullReason: "unresolved_merge" };
    }

    const installationId = await getInstallationId(userId, workspaceId);
    if (!installationId) {
      log.warn({ userId }, "No installation ID found for sync pull");
      return none;
    }

    // Auto-commit any uncommitted changes before pulling to avoid conflicts.
    // Path-scoped to `knowledge-base/` — see #2905.
    await autoCommit(workspacePath, allowlisted(status), "pull", userId);

    const head = readWorkspaceHeadRef(workspacePath);
    let result: KbPullStep;
    let held: { total: number; onRecovered: number; checkedAt: string } | null = null;
    let repo: { url: string; owner: string; repo: string } | null = null;
    try {
      repo = await resolveRepoUrl(userId, workspaceId);
    } catch (err) {
      if (!(err instanceof KbRemoteError)) throw err;
    }
    if (repo === null) {
      result = { reason: "remote_state", remoteCause: "repo_url_unresolved" };
    } else {
      let refusal: IsolatedPushDirRefusal | undefined;
      try {
        isolated = createIsolatedPushDir(workspacePath);
      } catch (err) {
        if (!(err instanceof IsolatedPushDirRefusal)) throw err;
        refusal = err;
      }
      if (!isolated) {
        result = { reason: "isolated_refused", ...(refusal ? { isolatedReason: refusal.reason } : {}) };
      } else {
        const writer = kbPullWriter(workspacePath);
        const limits = limitsOpt ? { limits: limitsOpt } : {};
        const merged = await mergeVerifiedDefault({
          isolated,
          installationId,
          url: repo.url,
          headSha: head.sha,
          refName: head.refName,
          writer,
          budget,
          ...limits,
        });
        result = merged;
        if (PULL_STAMPS.has(merged.reason)) await stampBestEffort(service, workspaceId);
        if (PULL_ADOPTS.has(merged.reason) && merged.remote) {
          const side = await adoptSideTip({
            isolated,
            installationId,
            url: repo.url,
            owner: repo.owner,
            repo: repo.repo,
            remote: merged.remote,
            headSha: readWorkspaceHeadRef(workspacePath).sha,
            writer,
            budget,
            ...limits,
          });
          if (side) result = side;
        }
        // #12714 (D29(1), D39(a)(b), W1): after the merge and the adoption (up_to_date too), on this run's remote tip and
        // the HEAD those steps left, through the ONE write path (server/kb-sync-held-refresh.ts) with this pull's injected
        // service client: every attempt writes, a null count too, with checked_at = this run's ls-remote instant. No
        // remote read: no tip, so no attempt. X5 (R2-B, verify-coverage P3-6): HEAD not on the remote's default branch is no
        // attempt either, as in the self-heal (the cc refresh does not yet apply X5: tasks.md 11.6). D42 (R2-B, verify-coverage P3-5): a default merge that
        // `merged` or found the workspace `up_to_date` clears the pull-blocked state; any other reason leaves it as it is.
        if (merged.remote && head.refName === `refs/heads/${merged.remote.defaultBranch}`) {
          const clears = merged.reason === "merged" || merged.reason === "up_to_date";
          const counted = await writeHeldFromIsolated({
            isolated,
            workspacePath,
            workspaceId,
            T: merged.remote.tip,
            headSha: readWorkspaceHeadRef(workspacePath).sha,
            checkedAt: merged.remote.readAt,
            service,
            ...(clears ? { pullBlocked: null } : {}),
          });
          if (counted) held = { ...counted, checkedAt: merged.remote.readAt.toISOString() };
        }
      }
    }
    reportPullHeld(result.reason, ctx, result.ref, result);
    return {
      heldFiles: held?.total ?? null,
      onRecovered: held?.onRecovered ?? null,
      pullReason: result.reason,
      // SyncPullResult contract: null exactly when heldFiles is (the stored checked_at is written regardless, D39(b))
      checkedAt: held?.checkedAt ?? null,
    };
  } catch (err) {
    // D25(7): no raw error reaches Sentry (git's argv names the URL and shas): the class name and the first app frame only.
    const errName = err instanceof Error ? err.name : typeof err;
    const frame = firstAppFrame(err);
    log.warn({ userIdHash: hashUserId(userId), errName, ...(frame ? { frame } : {}) }, "Sync pull failed — continuing with local state");
    reportSilentFallback(null, {
      feature: "session-sync",
      op: "syncPull",
      // workspacePath omitted intentionally — it embeds the raw userId
      // (workspacePath = `<root>/<userId>`), which bypasses the
      // hashExtraUserId boundary's top-level rename (Recital 26 +
      // ADR-029 rename-at-boundary). The pseudonymous userId carries the
      // diagnostic value; the path adds no information.
      extra: { userId, errName, ...(frame ? { frame } : {}) },
      message: "Sync pull failed — continuing with local state",
    });
    // R2-B (obs F3, verify-coverage P3-17): a closed reason for the legacy runner's line, and this run's one pull-held line.
    reportPullHeld("pull_unexpected", ctx, undefined, { errName, ...(frame ? { frame } : {}) });
    return { ...none, pullReason: "pull_unexpected" };
  } finally {
    disposeIsolated(isolated, "session-sync");
  }
}

/**
 * The X1 stamp, best effort (quality P3-3): a failed write never turns a completed merge into a failed pull (the result
 * and its `kb-sync.pull-held` line stand); it is reported on its own op.
 */
async function stampBestEffort(service: SupabaseClient, workspaceId: string): Promise<void> {
  try {
    await updateLastSynced(service, workspaceId);
  } catch (err) {
    const errName = err instanceof Error ? err.name : typeof err;
    log.warn({ op: "kb-sync.pull-stamp", errName, workspaceId }, "KB sync pull: the last-synced stamp failed");
    reportSilentFallback(null, {
      feature: "session-sync",
      op: "kb-sync.pull-stamp",
      extra: { workspaceId, errName },
      message: "KB sync pull: the last-synced stamp failed",
    });
  }
}

/**
 * The path-scoped auto-commit (#2905) of `allowed` (the status run's `knowledge-base/` entries). Best-effort: a failure
 * is logged and reported (stage, exit status and a closed bucket only), never thrown.
 */
async function autoCommit(workspacePath: string, allowed: string[], stage: "pull" | "push", userId: string): Promise<void> {
  try {
    if (allowed.length === 0) {
      log.info({ userIdHash: hashUserId(userId) }, "No allowlisted changes to commit — skipping auto-commit");
      return;
    }
    await runConnectedRepoGitAsync(["add", "--", ...allowed], { cwd: workspacePath });
    await runConnectedRepoGitAsync(["commit", "-m", stage === "pull" ? AUTO_COMMIT_MSG_PULL : AUTO_COMMIT_MSG_PUSH], { cwd: workspacePath });
  } catch (err) {
    // pattern P3-16, gdpr: no raw `err` in the pino line (its message is the argv, which names tenant file paths); the class
    // name, the exit status and the first app frame only.
    const frame = firstAppFrame(err);
    const exit = (err as { status?: unknown } | null)?.status;
    log.warn(
      { userId, errName: err instanceof Error ? err.name : typeof err, ...(typeof exit === "number" ? { exit } : {}), ...(frame ? { frame } : {}) },
      `Auto-commit before ${stage} failed`,
    );
    const failure = autoCommitFailure(err, stage);
    if (failure) {
      reportSilentFallback(failure, {
        feature: "session-sync",
        op: `auto-commit-${stage}`,
        extra: { userId },
        message: stage === "pull" ? "Auto-commit before sync pull failed" : "Auto-commit before sync push failed",
      });
    }
  }
}

/**
 * Push the session's knowledge-base changes after an agent session (#12600). Only a commit the server built reaches the
 * remote: `S` = the remote tip's verified root with HEAD's `knowledge-base` entry, parent the remote tip, Soleur's
 * message and identity (server/kb-sync-publish.ts). Best-effort: failures are logged but never throw. It never stamps
 * `repo_last_synced_at` (W5: only `syncPull` does); it writes the held-files count (#12714) from its `finally` whenever the
 * publish's `onHeldFiles` hook computed one.
 */
export async function syncPush(
  userId: string,
  workspacePath: string,
  // ADR-044 PR-B: injected service client + the caller's ONE resolved active
  // workspace id (see syncPull / agent-runner.ts).
  service: SupabaseClient,
  workspaceId: string,
  /** `budget` is a test seam (R2-B); production passes none: `SYNC_PUSH_BUDGET_MS` from this call's entry. */
  opts: { readonly budget?: PushBudget } = {},
): Promise<void> {
  const budget: PushBudget = opts.budget ?? pullBudget(SYNC_PUSH_BUDGET_MS, 0);
  if (!(await hasRemote(workspacePath))) {
    return; // Empty workspace, no remote
  }

  // PR-C §2.1 (#3244): per-entry-function RLS-baseline probe — see
  // `authProbe` doc-comment for the load-bearing rationale.
  if (!(await authProbe(userId, "syncPush"))) {
    log.warn({ userIdHash: hashUserId(userId) }, "Sync push aborted — auth probe failed");
    return;
  }

  // D38(6): serialized with this workspace's pull and self-heal on this host. R2-B (verify-coverage P2-1): the publish holds
  // the lock, so it runs on a budget: the wait races it (`push_deadline` when the lock is not free in time), and inside,
  // the remote read and each push start only while it allows, each capped at what is left. A started git child is never
  // killed mid-way beyond its own (capped) timeout.
  const locked = await withWorkspaceGitLock(workspacePath, () => pushLocked(userId, workspacePath, service, workspaceId, budget), {
    waitMs: budget.remaining(),
  });
  if (locked === WORKSPACE_GIT_LOCK_TIMEOUT) reportPushHeld("push_deadline", "held", { userId, workspaceId });
}

async function pushLocked(
  userId: string,
  workspacePath: string,
  service: SupabaseClient,
  workspaceId: string,
  budget: PushBudget,
): Promise<void> {
  const ctx = { userId, workspaceId };
  try {
    // ONE status run feeds the unmerged scan and the auto-commit allowlist (D21).
    const status = await readStatus(workspacePath, "syncPush");
    // A conflicted session-start merge: committing would publish conflict markers (matrix 17).
    if (mergeInProgress(workspacePath, status)) {
      await pinInterruptedAutostash(workspacePath); // D36(c)
      reportPushHeld("merge_in_progress", "held", ctx);
      return;
    }

    // Auto-commit any uncommitted changes before pushing.
    // Path-scoped to `knowledge-base/` — see #2905.
    await autoCommit(workspacePath, allowlisted(status), "push", userId);

    if (!(await hasLocalCommits(workspacePath))) {
      log.debug({ userId }, "No local commits to push");
      return;
    }

    const installationId = await getInstallationId(userId, workspaceId);
    if (!installationId) {
      log.warn({ userId }, "No installation ID found for sync push");
      return;
    }

    // Frozen HEAD, read from the files (no git child): the sha every later step builds on and CASes against.
    let head: { sha: string; refName: string | null };
    try {
      head = readWorkspaceHeadRef(workspacePath);
    } catch {
      throw new KbSyncError("head_unreadable");
    }
    if (head.refName === null) {
      reportPushHeld("detached_head", "held", ctx);
      return;
    }

    const result = await publishKbOnly({
      ...ctx,
      workspacePath,
      installationId,
      headSha: head.sha,
      refName: head.refName,
      writer: kbWorkspaceWriter(workspacePath),
      budget,
      // #12714 (D29(1), D39(a)(b)): the publish runs this hook from its `finally`, before its isolated dir is disposed, on
      // every exit that read the remote tip (held exits too); the helper computes and writes (null with checked_at).
      onHeldFiles: async ({ isolatedDir, T, headSha, readAt }) => {
        await writeHeldFromIsolated({ isolated: isolatedDir, workspacePath, workspaceId, T, headSha, checkedAt: readAt, service });
      },
    });

    if (result.kind === "fallback_failed" && result.fallbackReason === "side_push_transient") {
      // D21: the side push failed on the network; the next turn retries it. A warning OFF the paging op, debounced per workspace.
      mirrorWarnWithDebounce(
        null,
        {
          feature: "session-sync",
          op: "kb-sync.side-push-transient",
          extra: { userId },
          tags: { fallback_reason: result.fallbackReason, push_class: result.pushErr?.pushClass ?? "none" },
          message: "KB-sync side push failed transiently — retried next session",
        },
        workspaceId,
        "kb-sync-side-push-transient",
      );
      return;
    }
    if (result.kind === "fallback_failed") {
      // `reason` discriminates "the fallback ran and failed" from the
      // persistent_other branch below (which never entered the fallback)
      // WITHOUT splitting the Sentry op — the issue-alert + its op-contract
      // test pin the single `kb-sync.protected-fallback-failed` op. The closed
      // `fallback_reason` tag names the step (#12600).
      // CTO ruling D8: a null error (an Error loses these tags to the pino-mirror capture, #8629), debounced per
      // workspace and reason (the fallback can fail every turn, R16).
      mirrorWithDebounce(
        null,
        {
          feature: "session-sync",
          op: "kb-sync.protected-fallback-failed",
          extra: { userId, reason: "fallback_failed" },
          tags: {
            reason: "fallback_failed",
            fallback_reason: result.fallbackReason,
            push_class: result.pushErr?.pushClass ?? "none",
          },
          message:
            "KB-sync protected-branch fallback failed — writes preserved on default for retry",
        },
        workspaceId,
        `kb-sync-fallback-failed:${result.fallbackReason}`,
      );
      return;
    }
    if (result.kind === "fallback") {
      // #5426 — protected default: writes routed to soleur/kb-sync + PR.
      warnSilentFallback(null, {
        feature: "session-sync",
        op: "kb-sync.push-protected-fallback",
        extra: {
          userId,
          prUrl: result.prUrl,
          commitCount: result.commitCount,
        },
        message:
          "KB-sync push rejected by branch protection — routed to soleur/kb-sync + PR",
      });
      // Fall through to history recording (writes delivered).
    } else if (result.kind !== "pushed") {
      // Held or nothing to sync: no push happened, so no bookkeeping (CPO condition C4).
      return;
    }

    // Best-effort: record KB file count for analytics sparklines
    try {
      await recordKbSyncHistory(userId, workspacePath);
    } catch (err) {
      log.warn({ userIdHash: hashUserId(userId), errName: err instanceof Error ? err.name : typeof err }, "KB sync history recording failed");
      reportSilentFallback(err, {
        feature: "session-sync",
        op: "recordKbSyncHistory",
        // workspacePath dropped — see syncPull catch for the rationale.
        extra: { userId },
        message: "KB sync history recording failed",
      });
    }

    // W5 (D29(9)): no `repo_last_synced_at` stamp here: only `syncPull` stamps it, so "Updated from GitHub" stays true.
    log.info({ userId }, "Sync push completed");
  } catch (err) {
    if (err instanceof KbSyncError && err.pushClass === "persistent_other") {
      // Non-protection persistent reject (e.g. shallow update not allowed): the next turn hits it again, so the emit is
      // debounced per workspace (D21) on the same op (the issue alert keys on it).
      // D8: null error, the cause in tags (the Error path's tags are lost to the pino-mirror capture, #8629).
      mirrorWithDebounce(
        null,
        {
          feature: "session-sync",
          op: "kb-sync.protected-fallback-failed",
          extra: { userId, reason: "persistent_other" },
          tags: { reason: "persistent_other", push_class: "persistent_other" },
          message:
            "KB-sync push persistently rejected (non-protection) — not retried",
        },
        workspaceId,
        "kb-sync-persistent-other",
      );
      return;
    }
    // D8: null error, the closed reason and push class in tags. A non-KbSyncError carries only its class name and (D20) its
    // first app code frame as `file:line`: its message is git's argv (the URL and the refspec, R2), so it reaches neither
    // Sentry nor the pino line (pattern P3-16, gdpr: no raw `err` key).
    const kbErr = err instanceof KbSyncError ? err : null;
    const frame = kbErr ? undefined : firstAppFrame(err);
    log.warn(
      { userId, errName: err instanceof Error ? err.name : typeof err, ...(kbErr ? { reason: kbErr.reason } : {}), ...(frame ? { frame } : {}) },
      "Sync push failed — next session will retry",
    );
    reportSilentFallback(null, {
      feature: "session-sync",
      op: "syncPush",
      // workspacePath dropped — see syncPull catch for the rationale.
      extra: kbErr ? { userId } : { userId, errName: err instanceof Error ? err.name : typeof err, ...(frame ? { frame } : {}) },
      tags: {
        reason: kbErr ? kbErr.reason : "unclassified",
        push_class: kbErr?.pushClass ?? "none",
        // D21: the closed refusal reason of an isolated_refused, never a path
        ...(kbErr?.isolatedReason ? { isolated_reason: kbErr.isolatedReason } : {}),
      },
      message: "Sync push failed — next session will retry",
    });
  }
}

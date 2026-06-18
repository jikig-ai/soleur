// ---------------------------------------------------------------------------
// Concierge dispatch self-heal orchestrator (FIX 1a).
//
// `server/repo-readiness.ts` stays a PURE decision (AC4): it keys only on
// `repo_status`/`repo_error` and never touches disk or the DB. This module is
// the I/O ORCHESTRATOR that wraps that pure decision with the actual recovery —
// extracted into its own file so the pure module gains no I/O imports.
//
// The bug it closes (plan Reconciliation): the readiness gate at
// `cc-dispatcher.ts:1563` short-circuits a `repo_status=error` workspace with a
// thrown `RepoNotReadyError` BEFORE the on-disk self-heal (`:1697`
// `ensureWorkspaceRepoCloned`) can re-clone — the
// `short-circuit-guard-must-sit-after-the-recovery-it-gates` anti-pattern. This
// orchestrator attempts the existing idempotent, `.git`-absent-gated re-clone
// under an optimistic lock and RE-EVALUATES before honestly blocking.
//
// Write boundary (AC5b): cc-dispatcher is OFF the service-role allowlist and a
// tenant-client UPDATE on `workspaces` is silently RLS-filtered to zero rows.
// The `claimCloneLock`/`setRepoStatus` seams are therefore wired (in
// cc-dispatcher) to the SECURITY DEFINER RPCs (`claim_repo_clone_lock` /
// `set_repo_status`, migration 108) called via the TENANT `.rpc()`. This module
// only knows the seam contracts; it never reaches for a service client.
//
// Seams are injected (AC4) so the decision is DB-free in unit test, mirroring
// the `__setGraftForTests` pattern in `ensure-workspace-repo.ts`.
// ---------------------------------------------------------------------------

import { reportSilentFallback } from "@/server/observability";
import { sanitizeGitStderr } from "@/server/git-auth";
import {
  evaluateRepoReadiness as pureEvaluateRepoReadiness,
  repoErrorMsg,
  REPO_CLONING_MSG,
  type RepoReadiness,
} from "@/server/repo-readiness";
import type {
  EnsureWorkspaceRepoArgs,
  ReprovisionOutcome,
} from "@/server/ensure-workspace-repo";

/** The reason persisted (and shown) when the dispatch self-heal clone fails. */
const SELF_HEAL_FAILED_REASON =
  "automatic repository recovery failed; please reconnect";

export interface RepoSelfHealArgs {
  userId: string;
  /** The ACTIVE workspace id (ADR-044) the lock + status writes target. */
  workspaceId: string;
  workspacePath: string;
  /**
   * The EFFECTIVE (promoted, entitlement-gated) installation id — NOT the raw
   * stored one (AC6,
   * `2026-06-15-parallel-recovery-path-must-reuse-same-resource-selection`).
   * null = not connected → no recovery possible.
   */
  installationId: number | null;
  /** The connected repo URL (normalized). null/empty = not connected. */
  repoUrl: string | null;
  /** `workspaces.repo_status` as read for the gate. */
  status: string | null | undefined;
  /** `users.repo_error` (sanitized at rest) as read for the gate. */
  repoError: string | null | undefined;
}

export interface RepoSelfHealSeams {
  /** The PURE readiness decision (defaults to the real one in production). */
  evaluateRepoReadiness: (
    status: string | null | undefined,
    repoError: string | null | undefined,
  ) => RepoReadiness;
  /**
   * Optimistic clone lock (RPC `claim_repo_clone_lock`). Returns true iff THIS
   * caller flipped a recoverable (error | stale-cloning) row to 'cloning'.
   */
  claimCloneLock: (workspaceId: string) => Promise<boolean>;
  /**
   * Terminal status write (RPC `set_repo_status`). `error` carries a
   * (pre-sanitized) reason; `ready` clears it.
   */
  setRepoStatus: (
    workspaceId: string,
    status: "ready" | "error",
    error: string | null,
  ) => Promise<void>;
  /** The existing idempotent, `.git`-absent-gated, fail-soft re-clone. */
  ensureWorkspaceRepoCloned: (
    args: EnsureWorkspaceRepoArgs,
  ) => Promise<ReprovisionOutcome>;
  /** `existsSync(<workspacePath>/.git)` — injected so the decision is fs-free in test. */
  gitDirExists: (workspacePath: string) => boolean;
}

/**
 * Resolve dispatch readiness, attempting the on-disk self-heal before honestly
 * blocking. Recovery policy is SPLIT by DB state (plan Bug 2 Phase 2.2):
 *
 *   FAST PATH — `{ ok:true }` (ready/not_connected/unknown) AND `.git` PRESENT
 *     → return immediately. The ONLY added cost over the legacy fast path is the
 *     local `gitDirExists` (existsSync) probe; NO DB/JWT round-trip
 *     (cc-dispatcher keeps `getFreshTenantClient` behind its own existsSync gate
 *     so this orchestrator is not even entered on the common case — AC7).
 *
 *   READY-BUT-`.git`-ABSENT (Bug 2, NEW) — a DB-`ready` workspace whose physical
 *     clone is gone (the member cold-dispatch headline). LOCK-FREE graft:
 *     `claim_repo_clone_lock` CANNOT acquire a `ready` row by construction (its
 *     WHERE matches only error|stale-cloning, migration 108:97-110), so the lock
 *     is unavailable here — concurrency is guarded by the clone's own `.git`
 *     sentinel re-check (ensure-workspace-repo.ts:239, per-attempt randomUUID
 *     temp dir + atomic rename). On SUCCESS the row is ALREADY `ready`, so
 *     `setRepoStatus` is SKIPPED (no-op + avoids a spurious member-row write +
 *     RPC round-trip). On FAILURE → `setRepoStatus(error,reason)` + Sentry, so
 *     the member reads the honest reason on the next dispatch (AC6c).
 *
 *   ERROR / STALE-CLONING (`{ ok:false, code:"error" }`) — KEEP the optimistic
 *     `claim_repo_clone_lock` thundering-herd guard (AC7b):
 *       - loser → `{ ok:false, code:"cloning" }` honest-wait, NO clone.
 *       - winner → re-clone; "ok" → setRepoStatus(ready,null) → `{ ok:true }`;
 *         "failed" → setRepoStatus(error,reason) + Sentry → `{ ok:false }`.
 *
 *   FRESH `cloning` → honest-wait unchanged (the staleness escape lives in the
 *     lock RPC; a live setup clone is never disturbed).
 */
export async function resolveRepoReadinessWithSelfHeal(
  args: RepoSelfHealArgs,
  seams: RepoSelfHealSeams,
): Promise<RepoReadiness> {
  const decision = seams.evaluateRepoReadiness(args.status, args.repoError);
  const hasConnection = args.installationId !== null && !!args.repoUrl;

  // FAST PATH — ready/not_connected/unknown. Short-circuit ONLY when `.git` is
  // present (or there is no connection to clone, e.g. not_connected). A
  // `ready`-but-`.git`-absent CONNECTED workspace falls through to the lock-free
  // graft below (Bug 2). All other `{ ok:true }` shapes return unchanged.
  if (decision.ok) {
    if (!hasConnection || seams.gitDirExists(args.workspacePath) === true) {
      return decision;
    }
    // ready + connected + `.git` ABSENT → lock-free graft (no claimCloneLock).
    return graftReadyButGitAbsent(args, seams);
  }

  // error/stale-cloning that cannot recover (no install / no repoUrl / `.git`
  // present) and fresh `cloning` fall through to the unchanged honest block.
  const canRecover =
    decision.code === "error" &&
    hasConnection &&
    seams.gitDirExists(args.workspacePath) === false;

  if (!canRecover) {
    return decision;
  }

  // Recoverable error: claim the optimistic lock (RPC) — the thundering-herd
  // guard. Lock-FREE is the READY entry's policy only (above).
  const won = await seams.claimCloneLock(args.workspaceId);
  if (!won) {
    // Another dispatch is actively healing within the window — honest-wait,
    // never double-clone.
    return { ok: false, code: "cloning", message: REPO_CLONING_MSG };
  }

  const outcome = await seams.ensureWorkspaceRepoCloned({
    userId: args.userId,
    workspacePath: args.workspacePath,
    installationId: args.installationId,
    repoUrl: args.repoUrl,
  });

  if (outcome === "ok") {
    await seams.setRepoStatus(args.workspaceId, "ready", null);
    return { ok: true };
  }

  return failHonestly(args, seams);
}

/**
 * Bug 2 lock-free graft for a DB-`ready` workspace whose `.git` is gone. No
 * `claimCloneLock` (a `ready` row is unacquirable by the RPC); the clone's own
 * `.git`-sentinel re-check handles concurrency. SUCCESS skips `setRepoStatus`
 * (already ready); FAILURE persists the honest error so the member reads it next
 * dispatch (AC6c).
 */
async function graftReadyButGitAbsent(
  args: RepoSelfHealArgs,
  seams: RepoSelfHealSeams,
): Promise<RepoReadiness> {
  const outcome = await seams.ensureWorkspaceRepoCloned({
    userId: args.userId,
    workspacePath: args.workspacePath,
    installationId: args.installationId,
    repoUrl: args.repoUrl,
  });

  // SUCCESS on the ready entry — the row is ALREADY repo_status='ready'. SKIP
  // the setRepoStatus(ready) write: it is a no-op on workspaces.repo_status and
  // an RPC round-trip of no value.
  if (outcome === "ok") return { ok: true };

  return failHonestly(args, seams);
}

/**
 * A genuine recovery attempt that did not land `.git`. Persist the honest error
 * reason (sanitized) onto the workspace (read back by the gate for the
 * dispatching member — AC6c), mirror to Sentry, then block honestly.
 */
async function failHonestly(
  args: RepoSelfHealArgs,
  seams: RepoSelfHealSeams,
): Promise<RepoReadiness> {
  const reason = sanitizeGitStderr(SELF_HEAL_FAILED_REASON);
  await seams.setRepoStatus(args.workspaceId, "error", reason);
  reportSilentFallback(new Error("dispatch repo self-heal clone failed"), {
    feature: "cc-dispatcher",
    op: "repo-readiness-self-heal",
    extra: { userId: args.userId, workspaceId: args.workspaceId },
    message:
      "Concierge dispatch self-heal clone failed; honest-blocking the dispatch after a real recovery attempt",
  });
  return {
    ok: false,
    code: "error",
    message: repoErrorMsg(reason),
    errorCode: "repo_setup_failed",
  };
}

// Re-export the pure decision so the production wiring (cc-dispatcher) can pass
// it as the default seam without a second import line.
export { pureEvaluateRepoReadiness as evaluateRepoReadiness };

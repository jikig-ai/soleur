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
 * Resolve dispatch readiness, attempting the on-disk self-heal for a
 * recoverable `error` row before honestly blocking.
 *
 * Logic (plan Phase 2 steps 1-4):
 *   1. Pure decision; `{ ok:true }` (ready/not_connected/unknown) returns
 *      immediately — the zero-seam fast path.
 *   2. `{ ok:false, code:"error" }` AND installation AND repoUrl AND `.git`
 *      ABSENT → claim the lock:
 *        - loser → `{ ok:false, code:"cloning" }` honest-wait, NO clone.
 *        - winner → re-clone; "ok" → setRepoStatus(ready,null) → `{ ok:true }`;
 *          "failed" → setRepoStatus(error,reason) + Sentry → `{ ok:false }`.
 *   3. fresh `cloning` → unchanged honest-wait (the staleness escape lives in
 *      the lock RPC; a live setup clone is never disturbed).
 *   4. else (no install / no repoUrl / `.git` present) → original `{ ok:false }`.
 */
export async function resolveRepoReadinessWithSelfHeal(
  args: RepoSelfHealArgs,
  seams: RepoSelfHealSeams,
): Promise<RepoReadiness> {
  const decision = seams.evaluateRepoReadiness(args.status, args.repoError);

  // 1. Fast path — ready/not_connected/unknown never touch a seam.
  if (decision.ok) return decision;

  // 3 + 4 (non-error, or error that cannot recover) fall through to the
  // unchanged honest block below; only the recoverable `error` branch heals.
  const canRecover =
    decision.code === "error" &&
    args.installationId !== null &&
    !!args.repoUrl &&
    seams.gitDirExists(args.workspacePath) === false;

  if (!canRecover) {
    // fresh `cloning` → honest-wait unchanged; `error` with no install / no
    // repoUrl / `.git` present → cannot recover, honest block unchanged.
    return decision;
  }

  // 2. Recoverable error: claim the optimistic lock (RPC).
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

  // "failed" — a real recovery attempt that did not land `.git`. Persist the
  // honest error reason (sanitized) and mirror to Sentry, then block honestly.
  const reason = sanitizeGitStderr(SELF_HEAL_FAILED_REASON);
  await seams.setRepoStatus(args.workspaceId, "error", reason);
  reportSilentFallback(
    new Error("dispatch repo self-heal clone failed"),
    {
      feature: "cc-dispatcher",
      op: "repo-readiness-self-heal",
      extra: { userId: args.userId, workspaceId: args.workspaceId },
      message:
        "Concierge dispatch self-heal clone failed; honest-blocking the dispatch after a real recovery attempt",
    },
  );
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

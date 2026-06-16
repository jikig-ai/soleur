// In-flight work durability (#5275, deferred #5240 design item #4 — the
// PRESERVE half). When a client disconnects mid-turn, the 30s grace timer
// fires `abortSession`; the disconnect abort branch persists the partial
// assistant TEXT but the workspace's uncommitted git changes sit dirty and
// unreferenced on the persistent volume — a later resume can clobber them.
//
// This module gives those bytes a durable, restorable home: a snapshot commit
// built over a TEMP index and pointed at by `refs/checkpoints/<conversationId>`.
// HEAD, the real index, and the working tree are NEVER mutated by a checkpoint
// (so sibling conversations sharing the workspace clone see nothing change), and
// restore is GATED — it only materializes the snapshot when doing so provably
// cannot overwrite newer work; otherwise it refuses-and-reports honestly.
//
// Load-bearing constraint (see the plan): the interactive workspace is a SHARED
// clone keyed by `workspace_id`, not a per-conversation worktree, and per-user
// concurrency can be > 1. So a blind "restore the snapshot" would clobber a
// concurrent sibling's edits. The clean-tree precondition is the PRIMARY
// no-clobber guarantor; the sibling-slot probe (team workspaces only) is a belt.
//
// Constraints honored:
//   - NO `git stash` (incl. `git stash create`) — hook-blocked
//     (`hr-never-git-stash-in-worktrees`); the checkpoint is commit-tree/ref based.
//   - NO `git add -A` / `git add .` — this is a user-repo writer
//     (`hr-never-git-add-a-in-user-repo-agents`); paths are explicitly enumerated.
//   - Snapshot reads are serialized via `withWorkspacePermissionLock` so a
//     concurrent sibling write cannot tear the snapshot.
import { promisify } from "node:util";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { rm } from "node:fs/promises";

import { reportSilentFallback } from "./observability";
import { withWorkspacePermissionLock } from "./workspace-permission-lock";
import { createChildLogger } from "./logger";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { workspacePathForWorkspaceId } from "./workspace-resolver";

const log = createChildLogger("inflight-checkpoint");

/** Greenfield ref namespace — `git grep "refs/checkpoints"` returns 0 elsewhere.
 *  No existing prune/observability covers it; v1 relies on consume-on-restore +
 *  account-deletion clone removal (orphan-TTL prune deferred). */
const CHECKPOINT_REF_PREFIX = "refs/checkpoints/";

/** Honest refuse-and-report copy (single string regardless of dirty vs
 *  sibling-active reason — the reason feeds only the Sentry op extra, never a
 *  second UI state). Reuses the merged FR1 honest-status voice
 *  (`cc-workflow-end-messages.ts` WORKSPACE_RECLAIMED_MESSAGE): honest about the
 *  outcome, actionable, never leaks an internal enum, and reads sensibly to a
 *  teammate on a shared (team) workspace — not only to a second tab. */
export const CHECKPOINT_REFUSED_MESSAGE =
  "Your earlier in-progress changes are saved but were not auto-applied because newer work is already present. They remain saved at a checkpoint and were not overwritten.";

export function checkpointRefName(conversationId: string): string {
  return `${CHECKPOINT_REF_PREFIX}${conversationId}`;
}

type PlumbingResult = { ok: boolean; stdout: string; stderr: string };

/**
 * Private git-plumbing exec wrapper. The plumbing verbs
 * (`write-tree`/`commit-tree`/`update-ref`/`read-tree`/`checkout-index`/
 * `for-each-ref`) are greenfield in server code — they are NOT in
 * `session-sync.ts ALLOWED_GIT_SUBCOMMANDS`, and `runConnectedRepoGit` is
 * private to that module, so this is a deliberate sibling modeled on
 * `_cron-safe-commit.ts runGit`: async `promisify(execFile)`, no-throw
 * `{ ok, stdout, stderr }` return, host-config isolation.
 *
 * Identity is supplied via env (config is nulled) so `commit-tree` works in the
 * isolated environment without depending on the clone's user.name/email.
 */
async function runPlumbingGit(
  cwd: string,
  args: string[],
  extraEnv?: Record<string, string>,
): Promise<PlumbingResult> {
  // Lazy import mirrors `_cron-safe-commit.ts`: sibling test files mock
  // `node:child_process` with spawn-only factories, and a top-level
  // `promisify(execFile)` would crash at module load in every file that
  // transitively imports this one.
  const { execFile } = await import("node:child_process");
  const execFileP = promisify(execFile);
  try {
    const { stdout, stderr } = await execFileP("git", args, {
      cwd,
      env: {
        ...process.env,
        GIT_CONFIG_GLOBAL: "/dev/null",
        GIT_CONFIG_SYSTEM: "/dev/null",
        GIT_CONFIG_NOSYSTEM: "1",
        GIT_AUTHOR_NAME: "Soleur Checkpoint",
        GIT_AUTHOR_EMAIL: "checkpoint@soleur.local",
        GIT_COMMITTER_NAME: "Soleur Checkpoint",
        GIT_COMMITTER_EMAIL: "checkpoint@soleur.local",
        ...extraEnv,
      },
      maxBuffer: 32 * 1024 * 1024,
    });
    return { ok: true, stdout, stderr };
  } catch (err) {
    const e = err as Error & { stdout?: string; stderr?: string };
    return { ok: false, stdout: e.stdout ?? "", stderr: e.stderr ?? e.message };
  }
}

/**
 * Enumerate every changed working-tree path from `git status --porcelain=v1 -z`.
 *
 * Deliberately WIDER than `session-sync.ts getAllowlistedChanges` (which is
 * scoped to `knowledge-base/**` only): in-flight *work* durability means the
 * agent's CODE edits, not just KB files — restricting to `knowledge-base/**`
 * would silently drop exactly the work this feature exists to preserve. We reuse
 * the porcelain-parse SHAPE (repo-root-relative `-z` tokens, rename DESTINATION
 * kept) but with an "all changes except the deny-set" predicate — still an
 * explicit enumerated list handed to `git add -- <paths>`, never `-A` (the
 * `hr-never-git-add-a` rule forbids the wildcard verb, not a wide explicit list).
 *
 * Untracked working-tree changes never surface as `R`/`C` (rename detection is
 * an index/diff concept), but we still handle the staged-rename shape for
 * completeness: the destination is the status entry; the source is a bare
 * NUL-separated token that we also capture so its deletion is snapshotted.
 *
 * `.git/` contents are never emitted by porcelain, and the temp index lives
 * outside the worktree, so the practical deny-set is empty; gitignored build
 * artifacts (node_modules, .next) are already excluded by git itself.
 */
function parsePorcelainChanges(porcelainZ: string): string[] {
  const paths: string[] = [];
  const tokens = porcelainZ.split("\0");
  for (let i = 0; i < tokens.length; i++) {
    const entry = tokens[i];
    if (entry.length < 4) continue; // status (2) + space + path
    const status = entry.slice(0, 2);
    const path = entry.slice(3);
    if (path !== "") paths.push(path);
    // R (rename) / C (copy) emit the SOURCE path as a separate bare token —
    // capture it too (so a rename's source-deletion is in the snapshot), then
    // advance past it.
    if (status[0] === "R" || status[0] === "C") {
      const src = tokens[i + 1];
      if (src) paths.push(src);
      i++;
    }
  }
  return paths;
}

/** Build a unique temp index path OUTSIDE the worktree — an index inside the
 *  clone would show as `?? .tmpidx` and pollute `status` / sibling reads
 *  (plan-review P1-3). */
function tempIndexPath(): string {
  return join(tmpdir(), `soleur-ckpt-${randomUUID()}.idx`);
}

/**
 * Durably checkpoint the workspace's uncommitted working-tree changes to
 * `refs/checkpoints/<conversationId>`. Fire-and-forget on the degraded abort
 * path — returns `void`, never throws: a checkpoint failure mirrors to Sentry
 * but MUST NOT break the abort branch's partial-text persist (AC6).
 *
 * HEAD, the real index, and the working tree are never mutated.
 */
export async function checkpointInflightWork(
  workspacePath: string,
  conversationId: string,
  userId: string,
): Promise<void> {
  try {
    await withWorkspacePermissionLock(workspacePath, async () => {
      const status = await runPlumbingGit(workspacePath, [
        "status",
        "--porcelain=v1",
        "-z",
      ]);
      if (!status.ok) {
        throw new Error(`status failed: ${status.stderr}`);
      }
      const changes = parsePorcelainChanges(status.stdout);
      if (changes.length === 0) {
        // Nothing to checkpoint (clean tree) — benign no-op, no ref written.
        log.info(
          { op: "checkpoint-on-abort", conversationId },
          "inflight-checkpoint: clean tree, nothing to checkpoint",
        );
        return;
      }

      const tmpIndex = tempIndexPath();
      const indexEnv = { GIT_INDEX_FILE: tmpIndex };
      try {
        // Seed the temp index from HEAD, then stage only the explicitly
        // enumerated changed paths into it (NEVER `git add -A`).
        const readTree = await runPlumbingGit(
          workspacePath,
          ["read-tree", "HEAD"],
          indexEnv,
        );
        if (!readTree.ok) throw new Error(`read-tree HEAD failed: ${readTree.stderr}`);

        const add = await runPlumbingGit(
          workspacePath,
          ["add", "--", ...changes],
          indexEnv,
        );
        if (!add.ok) throw new Error(`add failed: ${add.stderr}`);

        const writeTree = await runPlumbingGit(
          workspacePath,
          ["write-tree"],
          indexEnv,
        );
        if (!writeTree.ok) throw new Error(`write-tree failed: ${writeTree.stderr}`);
        const tree = writeTree.stdout.trim();

        const message = `checkpoint: conversation ${conversationId} (in-flight, ${new Date().toISOString()})`;
        const commit = await runPlumbingGit(workspacePath, [
          "commit-tree",
          tree,
          "-p",
          "HEAD",
          "-m",
          message,
        ]);
        if (!commit.ok) throw new Error(`commit-tree failed: ${commit.stderr}`);
        const commitSha = commit.stdout.trim();

        const updateRef = await runPlumbingGit(workspacePath, [
          "update-ref",
          checkpointRefName(conversationId),
          commitSha,
        ]);
        if (!updateRef.ok) throw new Error(`update-ref failed: ${updateRef.stderr}`);

        log.info(
          { op: "checkpoint-on-abort", conversationId, ref: checkpointRefName(conversationId) },
          "inflight-checkpoint: wrote checkpoint ref",
        );
      } finally {
        await rm(tmpIndex, { force: true }).catch(() => {});
      }
    });
  } catch (err) {
    // Silent-fallback site (cq-silent-fallback-must-mirror-to-sentry): the abort
    // path must survive a checkpoint failure. Mirror, never re-throw.
    reportSilentFallback(err, {
      feature: "inflight-checkpoint",
      op: "checkpoint-on-abort",
      extra: { userId, conversationId },
    });
  }
}

/**
 * #5356 — resolve the conversation-bound checkpoint clone and checkpoint its
 * in-flight work. Extracted from `agent-runner.ts`'s disconnect branch so BOTH
 * the legacy path AND the cc-soleur-go dispatcher hook (`cc-dispatcher.ts`)
 * drive ONE enforcement point for the load-bearing clone-resolution invariant.
 *
 * The clone is resolved from the CONVERSATION's bound `workspace_id`
 * (`conversations.workspace_id` → `workspacePathForWorkspaceId`), the same
 * source the resume restore reads — NEVER the mutable active-workspace resolver
 * (`resolveActiveWorkspacePath`), which can drift during the 30s grace window
 * and write the ref onto a clone the restore never consults (silent
 * no-checkpoint + a stranded ref).
 *
 * Fire-and-forget: NEVER throws. A resolve or checkpoint failure mirrors to
 * Sentry (`cq-silent-fallback-must-mirror-to-sentry`) but must not break the
 * caller's terminal path (the legacy abort branch's partial-text persist, or
 * the cc close hook's unconditional bash-gate drain). `stage` distinguishes the
 * cc vs legacy call site in the Sentry extra while keeping both on the shared
 * `op: "checkpoint-on-abort"` monitor.
 */
export async function checkpointInflightWorkForConversation(
  userId: string,
  conversationId: string,
  stage:
    | "resolve-workspace-path"
    | "cc-resolve-workspace-path" = "resolve-workspace-path",
): Promise<void> {
  try {
    const checkpointTenant = await getFreshTenantClient(userId);
    const { data: convRow, error: convErr } = await checkpointTenant
      .from("conversations")
      .select("workspace_id")
      .eq("id", conversationId)
      .single();
    const checkpointWorkspaceId =
      (convRow as { workspace_id?: string | null } | null)?.workspace_id ??
      null;
    if (convErr || !checkpointWorkspaceId) {
      throw new Error(
        `checkpoint: could not resolve conversation workspace_id${convErr ? `: ${convErr.message}` : ""}`,
      );
    }
    const checkpointWorkspacePath =
      workspacePathForWorkspaceId(checkpointWorkspaceId);
    await checkpointInflightWork(checkpointWorkspacePath, conversationId, userId);
  } catch (checkpointErr) {
    reportSilentFallback(checkpointErr, {
      feature: "inflight-checkpoint",
      op: "checkpoint-on-abort",
      extra: { userId, conversationId, stage },
    });
  }
}

export type RestoreResult = {
  restored: boolean;
  reason?: "no-checkpoint" | "dirty" | "sibling-active" | "stale-base";
};

/**
 * Gated restore of a prior in-flight checkpoint into the SAME physical
 * workspace. Materializes the snapshot ONLY when it provably cannot overwrite
 * newer work — ALL of:
 *   - working tree CLEAN (`git status --porcelain` empty), AND
 *   - the checkpoint's parent still equals current HEAD (HEAD-parity) — the
 *     clean-tree check alone is NOT sufficient: the workspace clone's HEAD can
 *     advance between checkpoint and resume (`git pull --autostash` runs on every
 *     `startAgentSession` via `gitWithInstallationAuth` in `session-sync.ts`, and
 *     `workspace-sync.ts` does `pull --ff-only` / `reset --hard`). A clean tree at
 *     HEAD=B does not make a HEAD=A-based snapshot safe to materialize — the
 *     full-tree write would revert every file changed between A and B, AND
 *   - no sibling slot active — a concurrent sibling conversation on the SAME
 *     shared clone (per-user concurrency can be >1, including the solo two-tab
 *     case) means the snapshot may carry the sibling's dirt; restoring it over a
 *     now-clean tree would clobber the sibling. The caller probes this for EVERY
 *     resume (no solo skip — `workspace_id === userId` still permits concurrency 2).
 * Otherwise it refuses-and-reports (no overwrite, ref retained) so the user's
 * newer work is never clobbered.
 *
 * Materialization handles deletions: `checkout-index` only WRITES index entries,
 * so a file the in-flight work DELETED would be resurrected; we explicitly `rm`
 * the paths the checkpoint dropped vs its parent after the checkout.
 *
 * The real index is never staged (temp-index materialization). On a successful
 * restore the ref is CONSUMED so a later resume does not re-restore. A
 * materialization failure AFTER the precondition passes THROWS (the caller
 * surfaces an honest retryable error) — never a silent path.
 */
export async function restoreInflightCheckpoint(
  workspacePath: string,
  conversationId: string,
  opts: { siblingSlotActive: boolean },
): Promise<RestoreResult> {
  return withWorkspacePermissionLock(workspacePath, async () => {
    const ref = checkpointRefName(conversationId);

    const verify = await runPlumbingGit(workspacePath, [
      "rev-parse",
      "--verify",
      "--quiet",
      ref,
    ]);
    if (!verify.ok || verify.stdout.trim() === "") {
      // No checkpoint — normal path, no message, no mirror.
      return { restored: false, reason: "no-checkpoint" };
    }

    // Safety-precondition reads. A read failure here means we cannot PROVE the
    // restore is safe → throw so the caller surfaces an honest retryable error
    // (matching the materialization-failure path; never a silent return).
    const status = await runPlumbingGit(workspacePath, ["status", "--porcelain"]);
    if (!status.ok) {
      const err = new Error(`status failed: ${status.stderr}`);
      reportSilentFallback(err, {
        feature: "inflight-checkpoint",
        op: "restore-failed",
        extra: { conversationId, stage: "status-probe" },
      });
      throw err;
    }
    const treeDirty = status.stdout.trim() !== "";

    // HEAD-parity: the checkpoint's first parent is the HEAD it was taken over.
    const refParent = await runPlumbingGit(workspacePath, ["rev-parse", `${ref}^1`]);
    const head = await runPlumbingGit(workspacePath, ["rev-parse", "HEAD"]);
    if (!refParent.ok || !head.ok) {
      const err = new Error(
        `head-parity probe failed: ${refParent.stderr || head.stderr}`,
      );
      reportSilentFallback(err, {
        feature: "inflight-checkpoint",
        op: "restore-failed",
        extra: { conversationId, stage: "head-parity-probe" },
      });
      throw err;
    }
    const staleBase = refParent.stdout.trim() !== head.stdout.trim();

    if (treeDirty || opts.siblingSlotActive || staleBase) {
      // Refuse-and-report: do NOT overwrite. One honest user message (the
      // caller emits CHECKPOINT_REFUSED_MESSAGE); reason feeds only the op
      // extra for triage. Ref is retained so the work stays recoverable.
      const reason = treeDirty
        ? "dirty"
        : opts.siblingSlotActive
          ? "sibling-active"
          : "stale-base";
      reportSilentFallback(null, {
        feature: "inflight-checkpoint",
        op: "restore-refused",
        message: "in-flight checkpoint not auto-applied (newer work present)",
        extra: { conversationId, reason },
      });
      return { restored: false, reason };
    }

    // Safe (clean tree, HEAD unmoved, no sibling) → materialize via a temp index
    // OUTSIDE the worktree (a `read-tree` into the REAL index would leave the
    // snapshot staged, breaking the "index untouched" invariant — plan-review P0-2).
    const tmpIndex = tempIndexPath();
    const indexEnv = { GIT_INDEX_FILE: tmpIndex };
    try {
      const readTree = await runPlumbingGit(
        workspacePath,
        ["read-tree", ref],
        indexEnv,
      );
      if (!readTree.ok) throw new Error(`read-tree ${ref} failed: ${readTree.stderr}`);

      const checkout = await runPlumbingGit(
        workspacePath,
        ["checkout-index", "-a", "-f"],
        indexEnv,
      );
      if (!checkout.ok) throw new Error(`checkout-index failed: ${checkout.stderr}`);

      // `checkout-index` only writes — it never deletes. Re-apply the in-flight
      // deletions: paths present in the parent (= current HEAD, guaranteed by the
      // HEAD-parity gate) but dropped in the checkpoint tree. Without this, a file
      // the user deleted mid-turn is silently resurrected on restore.
      const deleted = await runPlumbingGit(workspacePath, [
        "diff",
        "--name-only",
        "-z",
        "--diff-filter=D",
        `${ref}^1`,
        ref,
      ]);
      if (!deleted.ok) throw new Error(`diff (deletions) failed: ${deleted.stderr}`);
      const deletedPaths = deleted.stdout.split("\0").filter((p) => p !== "");
      for (const rel of deletedPaths) {
        await rm(join(workspacePath, rel), { force: true });
      }

      // Consume the ref — one-shot restore.
      const del = await runPlumbingGit(workspacePath, ["update-ref", "-d", ref]);
      if (!del.ok) throw new Error(`update-ref -d failed: ${del.stderr}`);

      log.info(
        { op: "restore-inflight", conversationId, ref, deletedCount: deletedPaths.length },
        "inflight-checkpoint: restored and consumed checkpoint ref",
      );
      return { restored: true };
    } catch (err) {
      // Materialization failed AFTER the safety precondition passed — the work
      // is intact at the ref, but the worktree may be half-written. Mirror with
      // the triage op AND re-throw so the caller surfaces an honest, retryable
      // client error via its terminal catch (never a silent solo path). Distinct
      // from refuse-and-report (an expected operational outcome that returns).
      reportSilentFallback(err, {
        feature: "inflight-checkpoint",
        op: "restore-failed",
        extra: { conversationId, stage: "materialize" },
      });
      throw err;
    } finally {
      await rm(tmpIndex, { force: true }).catch(() => {});
    }
  });
}

// Erasure cascade (Art. 17): checkpoint refs live ON the workspace clone, so
// account deletion's `deleteWorkspace(userId)` (server/account-delete.ts) — which
// removes the whole clone directory — reaps them with zero extra code for the
// solo case (`userId === workspaces.id`). Per-conversation cleanup is
// consume-on-restore (the `update-ref -d` after a successful restore above). A
// dedicated ref-prune for orphaned refs (a `disconnected` conversation never
// resumed AND never deleted) is DEFERRED behind a ref-count gauge — refs
// self-clean for the dominant paths and the named bytes already survive un-reaped
// today, so a pointer to them adds no new disk-pressure class.

// ---------------------------------------------------------------------------
// #5733 D0 — consume the EXISTING cc-dispatcher dispatch-time clone outcome.
//
// The cold path already clones in-process into the agent's OWN `workspacePath`
// (`cc-dispatcher.ts:1987` `await ensureWorkspaceRepoCloned(...)`) — the only
// placement guaranteed to share the agent's bwrap filesystem. The defect was
// that its `"failed"` outcome was DISCARDED: a silent clone failure flowed into
// a false `ready` and a doomed agent spawn. This helper consumes that outcome
// loudly + F4-safely. It is NOT a second clone site (architecture P0 — the clone
// already ran) and reads NO service-role column (ADR-044 cc-dispatcher posture).
//
// The DISTINCT `repo_clone_failed` Sentry event is emitted upstream, inside
// `ensureWorkspaceRepoCloned`'s clone catch (with the real, sanitized git stderr),
// so EVERY caller surfaces it — this helper owns ONLY the F4-gated status write +
// the honest-block verdict for the cold dispatch surface.
// ---------------------------------------------------------------------------

import { existsSync } from "node:fs";
import { join } from "node:path";

import type { ReprovisionOutcome } from "@/server/ensure-workspace-repo";

/** Client/operator-facing reason persisted on a solo/owner clone failure. A
 *  STATIC constant with NO dynamic input (no path/token/url), so — like
 *  `failConnectionUnresolved`'s message — it needs no `sanitizeGitStderr`. The
 *  rich, sanitized git stderr lives in the `repo_clone_failed` Sentry event
 *  (emitted inside `ensureWorkspaceRepoCloned`), never in this DB status write. */
const CLONE_FAILED_REASON =
  "automatic repository clone failed; please reconnect";

export interface DispatchCloneConsumeArgs {
  /** The captured `ensureWorkspaceRepoCloned` return value from `:1987`. */
  outcome: ReprovisionOutcome;
  userId: string;
  /** The unified ACTIVE workspace id. solo/owner ⇔ `activeWorkspaceId === userId`. */
  activeWorkspaceId: string;
  /** The agent's own resolved workspace path (already UUID-guarded upstream via
   *  `workspacePathForWorkspaceId`; this helper does NOT re-derive it). */
  workspacePath: string;
}

export interface DispatchCloneConsumeSeams {
  /** `existsSync(<ws>/.git)` — injected for the fs-free CAS unit test. */
  gitDirPresent?: (workspacePath: string) => boolean;
  /** Terminal status write — cc-dispatcher wires the SECURITY DEFINER
   *  `set_repo_status` RPC via the TENANT client (off the service-role allowlist). */
  setRepoStatus: (status: "error", reason: string) => Promise<void>;
}

/**
 * Consume the dispatch-time clone outcome.
 *   - `"ok"`            → `"proceed"` (clone landed / benign no-op; the `:2010`
 *                         host-confirm gate is the authoritative backstop).
 *   - `"failed"` + `.git` PRESENT after the attempt (CAS — a concurrent winner
 *                         landed it) → `"proceed"` and NO status write (never
 *                         clobber a fresh `ready`).
 *   - `"failed"` + `.git` ABSENT → honest `"block"`; flip `repo_status→error`
 *                         ONLY on the solo/owner path (`activeWorkspaceId===userId`)
 *                         — a member must not flip a co-owned workspace's shared
 *                         status (emit-only on the team path).
 */
export async function consumeDispatchCloneOutcome(
  args: DispatchCloneConsumeArgs,
  seams: DispatchCloneConsumeSeams,
): Promise<"proceed" | "block"> {
  // Block ONLY on the EXPLICIT `"failed"` signal. `"ok"` (and any non-`"failed"`
  // value) proceeds — the `:2010` host-confirm gate is the authoritative backstop
  // and a benign skip must never honest-block.
  if (args.outcome !== "failed") return "proceed";

  const gitDirPresent =
    seams.gitDirPresent ?? ((p: string) => existsSync(join(p, ".git")));

  // CAS — a concurrent winner (reconcile / another tab / `/api/repo/setup`) may
  // have landed `.git` after this clone's failure. Never clobber a fresh `ready`,
  // and let the agent proceed (the `:2010` gate re-probes the now-present tree).
  if (gitDirPresent(args.workspacePath)) return "proceed";

  // `.git` genuinely absent after a failed clone → honest-block. F4: flip the
  // shared status ONLY on the solo/owner path.
  if (args.activeWorkspaceId === args.userId) {
    await seams.setRepoStatus("error", CLONE_FAILED_REASON);
  }
  return "block";
}

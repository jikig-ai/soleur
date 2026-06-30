// ---------------------------------------------------------------------------
// Concierge dispatch readiness gate (#5394).
//
// Closes the connect-repo race at the source: a Concierge / `/soleur:go`
// dispatch must NOT spawn an agent against a workspace whose repo is still
// `cloning` or whose setup `error`'d. This module is the PURE predicate +
// typed error + user-facing copy; the wiring (read `repo_status`, throw, catch,
// emit) lives in `cc-dispatcher.ts`. Keeping the decision pure lets the AC7
// unit test drive every branch DB-free.
//
// Source-of-truth: both `repo_status` AND the error REASON are read from
// `workspaces` (the ADR-044 source of truth, correct for shared workspaces).
// As of migration 110 the gate reads `workspaces.repo_error`, and as of
// migration 113 `set_repo_status` WRITES the reason to `workspaces.repo_error`
// (keyed on the membership-checked `p_workspace_id`) — the dropped
// `users.repo_error` split-write is gone, so a member-triggered heal failure
// surfaces the correct reason on that member's next dispatch. The at-rest
// reason is already sanitized at the write boundary (`/api/repo/setup` →
// `sanitizeGitStderr`); the gate unwraps it through the SHARED
// `parseErrorPayload` so there is no inline re-derivation and no leak surface.
// ---------------------------------------------------------------------------

import { parseErrorPayload, sanitizeGitStderr } from "@/server/git-auth";

/** Exact copy shown while the repo is cloning. Imported by both the gate and
 *  its test so the string never drifts. */
export const REPO_CLONING_MSG =
  "Your repository is still being set up — it'll be ready in a moment.";

/** Build the error-state message. Reason is already sanitized at rest; this
 *  only frames it with the reconnect CTA. */
export function repoErrorMsg(reason: string): string {
  return `Repository setup failed: ${reason}. Reconnect in Settings → Repository.`;
}

/**
 * Thrown by the Concierge dispatch factory when the active workspace's
 * `repo_status` is `cloning` or `error`. One class for both states because the
 * dispatch catch handles them identically — emit `{type:"error", message,
 * errorCode?}` and SKIP the Sentry mirror (an expected transient/benign state,
 * not an incident). The distinction between the two is DATA (`code` +
 * `errorCode?`), not a second type. Mirrors the `MissingByokKeyError` shape
 * (`extends Error`, fixed `this.name`).
 */
export class RepoNotReadyError extends Error {
  constructor(
    readonly code: "cloning" | "error",
    message: string,
    readonly errorCode?: "repo_setup_failed",
  ) {
    super(message);
    this.name = "RepoNotReadyError";
  }
}

export type RepoReadiness =
  | { ok: true }
  | {
      ok: false;
      code: "cloning" | "error";
      message: string;
      errorCode?: "repo_setup_failed";
    };

/**
 * Pure readiness decision. ONLY `cloning`/`error` block; everything else
 * (`ready`, `not_connected`, a null/transient read, or any unknown future
 * status) is `{ ok: true }` — FAIL-OPEN, so a `ready` founder is never blocked
 * by a status-read blip and an unrecognized state degrades to the existing
 * repo-less path / #5392 fallback rather than a hard block.
 */
export function evaluateRepoReadiness(
  status: string | null | undefined,
  repoError: string | null | undefined,
): RepoReadiness {
  switch (status) {
    case "cloning":
      return { ok: false, code: "cloning", message: REPO_CLONING_MSG };
    case "error": {
      // New writes are sanitized at rest (JSON `message` via sanitizeGitStderr
      // at the write boundary). Re-sanitize defensively so a LEGACY plain-stderr
      // row (unwrapped verbatim by parseErrorPayload) cannot leak an absolute
      // path / raw stderr through the gate (AC9, user-impact FINDING).
      const unwrapped =
        parseErrorPayload(repoError).errorMessage ?? "setup failed";
      const reason = sanitizeGitStderr(unwrapped);
      return {
        ok: false,
        code: "error",
        message: repoErrorMsg(reason),
        errorCode: "repo_setup_failed",
      };
    }
    default:
      return { ok: true };
  }
}

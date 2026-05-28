// #4224 — push-event reconcilability check. Pure function for testability.
// Returns ok=true iff the push is to the operator's default branch and is
// NOT a branch deletion (after=zeros). Tag pushes, non-default branches,
// and malformed payloads (missing repository.default_branch) all drop.
//
// Extracted to its own module per cq-nextjs-route-files-http-only-exports —
// route.ts may not export anything besides HTTP method handlers.

const SHA_ZEROS = "0000000000000000000000000000000000000000";

export type ReconcilablePushBody = {
  ref?: string;
  before?: string;
  after?: string;
  repository?: { default_branch?: string; full_name?: string };
};

export type ReconcilablePushResult =
  | {
      ok: true;
      defaultBranch: string;
      headSha: string;
      beforeSha: string;
      fullName: string;
    }
  | { ok: false; reason: string };

export function isReconcilablePush(
  body: ReconcilablePushBody,
): ReconcilablePushResult {
  const defaultBranch = body.repository?.default_branch;
  if (typeof defaultBranch !== "string" || defaultBranch.length === 0) {
    return { ok: false, reason: "missing-default-branch" };
  }
  const ref = body.ref;
  if (typeof ref !== "string" || !ref.startsWith("refs/heads/")) {
    return { ok: false, reason: "non-branch-ref" };
  }
  const branchName = ref.slice("refs/heads/".length);
  if (branchName !== defaultBranch) {
    return { ok: false, reason: "non-default-branch" };
  }
  const after = body.after;
  if (typeof after !== "string" || after === SHA_ZEROS) {
    return { ok: false, reason: "branch-deletion-or-missing-after" };
  }
  // Fail-closed (ADR-044 P0-2): repository.full_name is the bare owner/repo
  // slug the reconcile composes into a URL to match workspaces by repo.
  // Absent → skip; NEVER fall back to an installation-id-only match (which
  // would mis-route a 1:N installation across distinct workspaces).
  const fullName = body.repository?.full_name;
  if (typeof fullName !== "string" || fullName.length === 0) {
    return { ok: false, reason: "missing-full-name" };
  }
  const before = typeof body.before === "string" ? body.before : SHA_ZEROS;
  return { ok: true, defaultBranch, headSha: after, beforeSha: before, fullName };
}

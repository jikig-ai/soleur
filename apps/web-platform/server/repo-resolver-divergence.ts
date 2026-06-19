// ---------------------------------------------------------------------------
// Repo-resolver divergence breadcrumb (ADR-044 PR-1, FR4).
//
// The dual-resolver divergence this PR fixes was ZERO-Sentry / invisible. This
// emits a queryable breadcrumb when the membership self-heal RESETS a non-member
// claim to solo, or when a post-switch self-heal fails — so the NEXT occurrence
// is queryable by fingerprint (no SSH). The Sentry issue-alert ROUTING rule is a
// fast-follow (see plan §Infrastructure); making the signal queryable is PR-1's
// observability job.
// ---------------------------------------------------------------------------

import { reportSilentFallback } from "@/server/observability";

// Dedupe by (op, userId, claim) fingerprint — NOT just `op`. The non-member
// reset is read-time and mutates nothing, so without claim-pair fingerprinting
// it would re-fire on EVERY dispatch for a removed member → a breadcrumb storm
// that buries the first-occurrence signal (deepen arch P1). Process-local; a
// fresh process re-emits once, which is the intended first-occurrence behavior.
const seenFingerprints = new Set<string>();

/** Test seam — clear the dedupe set between cases (vitest isolates per file,
 *  but a single file exercising multiple fingerprints needs a reset). */
export function _resetResolverDivergenceDedupeForTests(): void {
  seenFingerprints.clear();
}

export type RepoResolverDivergenceOp =
  | "non-member-claim-reset"
  | "self-heal-failed"
  // Dispatch-time divergence (this PR): a member cold-dispatch into a
  // genuinely-connected workspace (repoUrl present / repo_status indicates a
  // connection) whose credential read `resolve_workspace_installation_id`
  // returned NULL (membership-deny or a transient RPC blip). The readiness gate
  // would otherwise fast-path this into a repo-less agent spawn; instead it
  // fails honestly and emits THIS op so the previously-dark dispatch path is
  // queryable + paging. Distinct from the catch-block `self-heal-failed` op
  // (an orchestration-infra crash) — see cc-dispatcher.ts emit-site notes.
  | "connected-null-install-at-dispatch"
  // On-disk corruption divergence (2026-06-19): a cold dispatch into a
  // genuinely-connected workspace (install NON-null, distinct from the op above)
  // whose `<ws>/.git` EXISTS but is not a valid work tree (partial/interrupted
  // clone, failed atomic-rename). The presence-only readiness gate used to
  // fast-path this into a repo-less spawn (silent). The corrupt-worktree graft
  // now removes a positively-fingerprinted empty-corrupt `.git`, re-clones, and
  // emits THIS op. `extra.recovered` distinguishes a self-healed re-clone
  // (true) from an unrecovered honest-block (false).
  | "corrupt-worktree-at-dispatch";

/**
 * Emit a fingerprint-deduped `repo_resolver_divergence` breadcrumb. `userId` is
 * pseudonymized to `userIdHash` at the `reportSilentFallback` emit boundary
 * (ADR-029); `extra` otherwise carries ONLY the two workspace ids — no
 * `repoUrl`/`installationId`/raw-userId (security P2).
 */
export function reportRepoResolverDivergence(args: {
  userId: string;
  op: RepoResolverDivergenceOp;
  activeClaimWorkspaceId: string;
  resolvedWorkspaceId: string;
  /**
   * Corrupt-worktree op only: true when the corrupt `.git` was removed and
   * re-cloned successfully (self-healed), false when the re-clone failed and the
   * dispatch honest-blocks. Omitted for the other ops. Non-credential, safe in
   * `extra`. Folded into the dedupe fingerprint so a recovered breadcrumb and a
   * later unrecovered page on the same workspace are not collapsed.
   */
  recovered?: boolean;
}): void {
  const recoveredKey =
    args.recovered === undefined ? "" : `:${args.recovered ? "r" : "u"}`;
  const fingerprint = `${args.op}:${args.userId}:${args.activeClaimWorkspaceId}${recoveredKey}`;
  if (seenFingerprints.has(fingerprint)) return;
  seenFingerprints.add(fingerprint);

  reportSilentFallback(new Error("repo_resolver_divergence"), {
    feature: "repo-resolver-divergence",
    op: args.op,
    extra: {
      userId: args.userId, // → userIdHash at the emit boundary (never raw)
      activeClaimWorkspaceId: args.activeClaimWorkspaceId,
      resolvedWorkspaceId: args.resolvedWorkspaceId,
      ...(args.recovered === undefined ? {} : { recovered: args.recovered }),
    },
  });
}

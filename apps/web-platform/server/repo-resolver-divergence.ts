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
  // Per-dispatch reprovision-path divergence (ADR-044 PR-3): the warm+cold
  // `reprovisionWorkspaceOnDispatch` (cc-dispatcher.ts:2899) used to re-derive the
  // workspace id via three divergent resolvers — the membership-verified path
  // diverged from the raw-claim install/repo, so a non-member/stale-claim member
  // grafted the team repo into the solo `/workspaces/<userId>` (no `.git`). The fix
  // resolves ONCE via the membership-verified resolver and threads the single id;
  // this op fires when that resolve RESETS a non-member claim to solo (formerly
  // zero-Sentry on the reprovision path). Distinct from the cold-factory
  // `non-member-claim-reset` so the two sites are queryable independently.
  | "reprovision-non-member-claim-reset";

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
}): void {
  const fingerprint = `${args.op}:${args.userId}:${args.activeClaimWorkspaceId}`;
  if (seenFingerprints.has(fingerprint)) return;
  seenFingerprints.add(fingerprint);

  reportSilentFallback(new Error("repo_resolver_divergence"), {
    feature: "repo-resolver-divergence",
    op: args.op,
    extra: {
      userId: args.userId, // → userIdHash at the emit boundary (never raw)
      activeClaimWorkspaceId: args.activeClaimWorkspaceId,
      resolvedWorkspaceId: args.resolvedWorkspaceId,
    },
  });
}

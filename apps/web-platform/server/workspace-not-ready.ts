// ---------------------------------------------------------------------------
// Workspace-not-ready dispatch-boundary states (ADR-044 PR-1, FR2).
//
// `repo-readiness.ts` is a PURE `(repo_status, repoError)` predicate with no
// access to solo/team, the target team id, or role. The member-in-solo-no-repo
// and the transient db-error states never flow through that readiness layer, so
// their copy is assembled HERE and thrown from the cc-dispatcher boundary
// (where userId, the `resolveActiveWorkspace` result incl. `resetFromClaim`, and
// the repo state are all in scope). repo-readiness.ts stays pure.
//
// The two states are intentionally distinct from `RepoNotReadyError`
// (cloning/error): those are a connected workspace mid-setup; these are "this
// workspace has nowhere to work" (transient read fault, or a member reset to an
// empty solo workspace).
// ---------------------------------------------------------------------------

/** Transient copy for a probe DB error. No switcher, no reconnect — a transient
 *  fault must never tell the user to take a structural action. */
export const WORKSPACE_DB_ERROR_MSG =
  "Temporary problem reaching your workspace — try again in a moment.";

/**
 * Copy for a member whose dispatch resolved to a solo workspace with no project
 * connected (incl. the `resetFromClaim` reset case). NO reconnect CTA — the
 * member does not own the connection; the actionable path is to switch to the
 * team workspace that holds the project. `teamName` is best-effort: a reset user
 * is provably a NON-member of the target team, so the name is RLS-unresolvable
 * by construction → the name-omitted fallback is the normal outcome (FR2).
 */
export function noRepoSwitchMsg(teamName?: string): string {
  const where = teamName
    ? `your team's project lives in **${teamName}**`
    : "your project lives in a team workspace";
  return `This workspace has no project connected. If ${where}, switch workspaces and try again.`;
}

/**
 * Discriminated not-ready state surfaced at the dispatch boundary.
 *   - `db-error` → transient membership-probe fault (from
 *     `resolveActiveWorkspace` `{ok:false}`); retryable, no structural CTA.
 *   - `no-repo-switch` → a member reset to an empty solo workspace; the client
 *     renders a workspace-switcher affordance. `targetTeamId` is the discarded
 *     `resetFromClaim` claim, carried on the WS frame for the switcher (the
 *     team name is omitted when RLS-unresolvable).
 */
export type WorkspaceNotReadyState =
  | { kind: "db-error" }
  | { kind: "no-repo-switch"; targetTeamId: string; teamName?: string };

/**
 * Thrown by the Concierge dispatch factory when the resolved workspace cannot
 * host a dispatch. The dispatch catch maps `state` to the WS error frame
 * (transient copy + no errorCode for `db-error`; `workspace_switch_required` +
 * `switchToWorkspaceId` for `no-repo-switch`). Mirrors the `RepoNotReadyError`
 * shape (`extends Error`, fixed `this.name`); like it, the catch SKIPS the
 * Sentry mirror (expected/benign states, not incidents — the divergence
 * breadcrumb fires separately and deduped in Phase 4).
 */
export class WorkspaceNotReadyError extends Error {
  constructor(readonly state: WorkspaceNotReadyState) {
    super(
      state.kind === "db-error"
        ? WORKSPACE_DB_ERROR_MSG
        : noRepoSwitchMsg(state.teamName),
    );
    this.name = "WorkspaceNotReadyError";
  }
}

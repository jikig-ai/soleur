// ---------------------------------------------------------------------------
// Concierge installation self-heal — skip observability
//
// feat-one-shot-concierge-gh-403-self-heal (Bug B). When the self-heal denies
// promotion to the repo-owner installation (the user keeps a possibly-wrong
// install and `gh` may still 403), that decision must be a QUERYABLE Sentry
// event — not an observability-dark silent keep. On-call must be able to answer
// "why did this dispatch keep the wrong install and 403?" from Sentry alone,
// with NO SSH (hr-observability-layer-citation, cq-silent-fallback-must-mirror-to-sentry).
//
// Extracted as a tiny pure helper so the skip decision is unit-testable without
// standing up the per-dispatch cc factory.
// ---------------------------------------------------------------------------

import { reportSilentFallback } from "./observability";

export interface SelfHealSkipContext {
  /** Pseudonymized at the reportSilentFallback boundary (Recital 26). */
  userId: string;
  /** The stored (possibly-wrong) installation id that is being kept. */
  storedInstallationId: number;
  /** The connected repo's owner login the dispatch is acting against. */
  owner: string;
  /**
   * Why promotion was skipped — a probe-outcome label such as `"not-member"`,
   * `"indeterminate"`, `"token-mint-failed"`, `"no-owner-install"`, or
   * `"org-type-stored-install"`. NEVER a token value (hr-github-app-auth-not-pat).
   */
  membershipProbeOutcome: string;
  /** The installation actually used for the dispatch (== stored on a skip). */
  effectiveInstallationId: number;
}

/**
 * Mirror a Concierge installation self-heal SKIP to Sentry + Better Stack as a
 * queryable EVENT. `reportSilentFallback(null, …)` routes to
 * `Sentry.captureMessage` (an event, searchable by `feature:cc-dispatcher
 * op:self-heal-skip`) plus a pino `logger.error` line — a bare `log.info` would
 * be breadcrumb-only and is explicitly rejected for the skip path.
 */
export function mirrorSelfHealSkip(ctx: SelfHealSkipContext): void {
  reportSilentFallback(null, {
    feature: "cc-dispatcher",
    op: "self-heal-skip",
    extra: {
      userId: ctx.userId,
      storedInstallationId: ctx.storedInstallationId,
      owner: ctx.owner,
      membershipProbeOutcome: ctx.membershipProbeOutcome,
      effectiveInstallationId: ctx.effectiveInstallationId,
    },
    message:
      "Concierge installation self-heal: promotion to repo-owner install skipped; keeping stored installation (gh ops may 403)",
  });
}

/**
 * Guard 3 — contribution-triggered entry.
 *
 * The CLO ruling of 2026-09-04 makes this the load-bearing mitigation for the
 * public coverage map: the Art. 6(1)(f) balancing, the Art. 13 (not Art. 14)
 * notice route and the Art. 17(3)(e) ground ALL rest on every account in the
 * roster belonging to someone who has themselves signed the Individual CLA
 * here. So it is enforced as a property of the artifact, at two sites — this
 * one (CI) and the write path (`apps/cla-evidence/scripts/ccla-add.sh`).
 *
 * Both, deliberately. Without the CI half, one hurried write bypasses the rule
 * permanently, on a surface from which nothing can be erased.
 */

/** Thrown when a roster account has no Individual CLA signature. */
export class ContributionTriggeredEntryError extends Error {
  readonly exitCode = 4;
  constructor(message: string) {
    super(message);
    this.name = "ContributionTriggeredEntryError";
  }
}

/** The upstream `contributor-assistant` ledger shape (flat, keyed on numeric id). */
export interface SignatureLedger {
  signedContributors: ReadonlyArray<{ id: number; name?: string }>;
}

interface RosterLike {
  organizations: ReadonlyArray<{
    record_ref: string;
    representatives: ReadonlyArray<{ id: number; login: string }>;
  }>;
}

/**
 * Assert every roster account has signed the ICLA. Returns the number of
 * accounts actually checked, so a caller can reconcile it against an
 * independently-derived count — a gate that reports "0 checked" and exits 0 is
 * indistinguishable from a healthy one otherwise.
 *
 * Throws rather than returning a boolean: the failure is a compliance defect,
 * not a branch.
 */
export function assertContributionTriggeredEntry(
  roster: RosterLike,
  ledger: SignatureLedger,
): number {
  // A check whose reference set is unreadable passes everything. Refuse
  // outright rather than degrading to an empty set.
  if (!ledger || !Array.isArray((ledger as Partial<SignatureLedger>).signedContributors)) {
    throw new ContributionTriggeredEntryError(
      "ICLA signature ledger missing or malformed (no `signedContributors` array) — " +
        "refusing to evaluate contribution-triggered entry against an unusable reference set",
    );
  }

  const signed = new Set(
    ledger.signedContributors
      .map((c) => c?.id)
      .filter((id): id is number => typeof id === "number" && Number.isFinite(id)),
  );

  const accounts = roster.organizations.flatMap((o) =>
    o.representatives.map((r) => ({ id: r.id, login: r.login, org: o.record_ref })),
  );

  if (accounts.length > 0 && signed.size === 0) {
    throw new ContributionTriggeredEntryError(
      "ICLA signature ledger is EMPTY while the roster carries " +
        `${accounts.length} account(s) — an empty reference set would pass every id, so this is refused`,
    );
  }

  // Collect EVERY offender. A check that stops at the first member is itself
  // the defect (row G3-M2).
  const missing = accounts.filter((a) => !signed.has(a.id));
  if (missing.length > 0) {
    const detail = missing.map((m) => `${m.login} (id ${m.id}, org ${m.org})`).join("; ");
    throw new ContributionTriggeredEntryError(
      `${missing.length} roster account(s) have no Individual CLA signature: ${detail}. ` +
        "Contribution-triggered entry: an account enters the roster only at or after that " +
        "person has signed the ICLA on a pull request here.",
    );
  }

  return accounts.length;
}

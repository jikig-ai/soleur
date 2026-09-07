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
  signedContributors: ReadonlyArray<{ id: number; name?: string; created_at?: string }>;
}

/**
 * The moment the coverage-map notice existed in the Individual CLA (§ 0).
 *
 * Membership of the ledger is NOT the property the Art. 13 posture rests on.
 * The claim four documents make is that the person was told **at the moment
 * they signed** — and someone who signed before that paragraph existed was
 * not. Both accounts in the ledger today are in exactly that position
 * (54279 signed 2026-02-27, 92384917 signed 2026-05-04); rostering either
 * would make Privacy Policy § 4.5's unconditional "You are told before any
 * record about you exists" false about a real person.
 *
 * The value is a deliberate FLOOR, not the notice's exact landing time, which
 * is this PR's merge commit and is unknowable while the code is being written.
 * The two directions are not symmetric: an epoch set too EARLY admits someone
 * who was never told (unrecoverable, on a surface with no erasure), while one
 * set too LATE refuses someone who was (recoverable — they re-sign, or the
 * operator records direct notice). So it is set strictly after the merge
 * window and may be lowered later against the merge commit's own date.
 */
export const COVERAGE_MAP_NOTICE_EPOCH = "2026-09-08T00:00:00Z";

/**
 * Accounts that signed BEFORE the notice existed and have since been given it
 * directly, each with the register entry recording that. Empty by design: an
 * id belongs here only once the direct notice is a matter of record, never to
 * unblock a write. Adding one without the citation is the defect this set
 * exists to make visible rather than to permit.
 */
export const DIRECT_NOTICE_GIVEN: ReadonlyArray<{ id: number; register_ref: string }> = [];

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

  // --- the TEMPORAL half of contribution-triggered entry ------------------
  // Membership alone does not carry the Art. 13 claim; WHEN the signature was
  // made does. Checked after the membership half so an account with no
  // signature at all is reported as unsigned rather than as un-noticed.
  const epoch = Date.parse(COVERAGE_MAP_NOTICE_EPOCH);
  const noticedDirectly = new Set(DIRECT_NOTICE_GIVEN.map((d) => d.id));
  const signedAt = new Map(
    ledger.signedContributors.map((c) => [c.id, c?.created_at] as const),
  );

  const preNotice: string[] = [];
  for (const a of accounts) {
    if (noticedDirectly.has(a.id)) continue;
    const at = signedAt.get(a.id);
    // Fail CLOSED on an absent or unparseable timestamp: "we cannot tell when
    // they signed" is not "they signed late enough".
    const t = typeof at === "string" ? Date.parse(at) : Number.NaN;
    if (!Number.isFinite(t)) {
      preNotice.push(`${a.login} (id ${a.id}, org ${a.org}) — ledger carries no usable signature timestamp`);
    } else if (t < epoch) {
      preNotice.push(`${a.login} (id ${a.id}, org ${a.org}) — signed ${at}, before the notice existed`);
    }
  }
  if (preNotice.length > 0) {
    throw new ContributionTriggeredEntryError(
      `${preNotice.length} roster account(s) signed the ICLA BEFORE the coverage-map notice ` +
        `existed (epoch ${COVERAGE_MAP_NOTICE_EPOCH}): ${preNotice.join("; ")}. ` +
        "Their signature cannot have informed them of a publication the document did not yet " +
        "describe, so writing them would falsify the Art. 13 claim the roster rests on. " +
        "Give the notice directly, record it in knowledge-base/legal/ccla-register.md, then add " +
        "the id to DIRECT_NOTICE_GIVEN with that citation — or wait for them to sign again.",
    );
  }

  return accounts.length;
}

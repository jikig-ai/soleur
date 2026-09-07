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

// A static import, NOT `require`: this module is ESM, and `require` resolved
// fine under vitest's interop while throwing `require is not defined` under
// `tsx` — which is the runtime the write path (`ccla-add.sh`) actually uses.
// The import is side-effect free, so the module stays pure to import.
import { execFileSync } from "node:child_process";

/**
 * The path and the sentence that together locate the coverage-map notice.
 *
 * The ANCHOR is a phrase that exists only in the § 0 paragraph this feature
 * adds, so `git log -S` over it returns the commit that introduced the notice.
 */
export const NOTICE_DOC = "docs/legal/individual-cla.md";
export const NOTICE_ANCHOR = "public corporate coverage map";

/**
 * When the coverage-map notice became true of the repository, DERIVED from git.
 *
 * This was a hardcoded constant and that was wrong, for a reason worth keeping:
 * the moment being described is created by merging the very commit that would
 * declare it, so no literal written before the merge can name it. A floor set
 * before the merge date silently degrades this gate to membership-only for
 * everyone who signs in the gap — the same vacuity as an unparseable epoch,
 * reached by the calendar instead of by an edit, and in the direction that
 * cannot be undone once a row is published. A floor set after it refuses people
 * who WERE noticed, and their only escape would be a `DIRECT_NOTICE_GIVEN`
 * entry asserting a direct notice that never happened.
 *
 * `git log --first-parent -S<anchor> --format=%cI` over the ICLA returns the
 * moment the paragraph reached the first-parent line of the current branch —
 * which under every merge method this repo permits is the merge itself. It
 * therefore resolves to the exact moment the notice landed on the default
 * branch, and keeps resolving correctly afterwards. Both directions close
 * permanently and without anyone remembering to lower a number. See the flag
 * matrix at the call site: neither flag alone is correct.
 *
 * Fails CLOSED: an unresolvable epoch refuses every account rather than
 * admitting them, because "we cannot establish when the notice existed" is not
 * "it existed early enough".
 *
 * A SECOND IMPLEMENTATION OF THIS DERIVATION EXISTS, and it is pinned to this
 * one. `scripts/followthroughs/ccla-representative-icla-7922.sh --print-epoch`
 * re-derives the same moment in bash, because that probe runs under `env -i` on
 * a CI runner with no node toolchain. Its companion suite asserts the two agree
 * BYTE FOR BYTE across a family of synthetic repositories (one-touch,
 * two-touch, merge, rebase-replay, squash), so editing `--first-parent`, `%cI`,
 * the oldest-match rule or the `--` separator here reddens a suite two
 * directories away. That is deliberate — the alternative is the two drifting
 * apart silently, with the merge gate and the operator's watch disagreeing
 * about when the notice existed — but it is worth knowing before you change the
 * argv array below.
 */
export function resolveCoverageMapNoticeEpoch(repoRoot?: string): string {
  let out = "";
  try {
    // NOTICE_DOC is repo-root-relative, so the lookup must run from the root —
    // never from the caller's CWD. A pathspec that matches nothing yields an
    // empty log, which is indistinguishable from "the notice was never added"
    // and would take the fail-closed path for the wrong reason.
    const root =
      repoRoot ??
      execFileSync("git", ["rev-parse", "--show-toplevel"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      }).trim();
    out = execFileSync(
      "git",
      // `--first-parent` AND `%cI`, and NEITHER is sufficient alone. This repo
      // permits all three merge methods (allow_merge_commit and
      // allow_rebase_merge are both true, there is no merge-queue rule pinning
      // SQUASH, and main carries 35 merge commits in its last 300), so the
      // epoch must be right under every one of them. Measured:
      //
      //   method         plain %aI   --first-parent %aI   --first-parent %cI
      //   squash         merge ✓     merge ✓              merge ✓
      //   merge commit   BRANCH ✗    merge ✓              merge ✓
      //   rebase         BRANCH ✗    BRANCH ✗             merge ✓
      //
      // A merge commit leaves the branch commit reachable off the first-parent
      // line with BOTH dates intact, so only `--first-parent` moves it; a
      // rebase replays the commit onto main preserving its AUTHOR date, so only
      // `%cI` moves it. Either flag alone leaves the epoch at the pre-merge date
      // and admits every signature made in the gap — the same silent
      // degradation to membership-only as the hardcoded constant, reached by a
      // merge-button choice instead of the calendar.
      ["log", "--first-parent", "-S", NOTICE_ANCHOR, "--format=%cI", "--", NOTICE_DOC],
      { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    );
  } catch (e) {
    throw new ContributionTriggeredEntryError(
      `could not derive the coverage-map notice epoch from git history of ${NOTICE_DOC}: ` +
        `${e instanceof Error ? e.message : String(e)}. Refusing every account rather than ` +
        "assuming the notice predates them.",
    );
  }
  // Oldest line = the commit that INTRODUCED the paragraph.
  const lines = out.split("\n").map((l) => l.trim()).filter(Boolean);
  const introduced = lines[lines.length - 1];
  if (!introduced || !Number.isFinite(Date.parse(introduced))) {
    throw new ContributionTriggeredEntryError(
      `the coverage-map notice anchor ${JSON.stringify(NOTICE_ANCHOR)} was not found in the git ` +
        `history of ${NOTICE_DOC}. Either the notice is absent or the anchor was reworded; ` +
        "refusing every account until the epoch can be established.",
    );
  }
  return introduced;
}

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
  /** Injectable for tests; derived from git history by default. */
  noticeEpoch: string = resolveCoverageMapNoticeEpoch(),
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
  const epoch = Date.parse(noticeEpoch);
  // O-9: the citation is the whole point of the exemption, so it is VALIDATED
  // rather than merely typed. `register_ref: ""` would otherwise unblock a
  // write exactly as a real citation does, on a surface from which nothing can
  // be erased. Checked here rather than left to review because the set is
  // empty today and the first entry is precisely when nobody is looking.
  for (const d of DIRECT_NOTICE_GIVEN) {
    if (typeof d.register_ref !== "string" || d.register_ref.trim() === "") {
      throw new ContributionTriggeredEntryError(
        `DIRECT_NOTICE_GIVEN carries an entry for id ${d.id} with no register citation. ` +
          "The exemption exists only where the direct notice is a matter of record; an entry " +
          "without a citation is an unrecorded claim, so it is refused rather than honoured.",
      );
    }
  }
  const noticedDirectly = new Set(DIRECT_NOTICE_GIVEN.map((d) => d.id));
  const signedAt = new Map(
    // O-8: `c?.id`, matching the membership half. `c.id` on a null ledger entry
    // throws a bare TypeError (exit 1), losing the documented exit-4 contract.
    ledger.signedContributors.map((c) => [c?.id, c?.created_at] as const),
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
        `existed (epoch ${noticeEpoch}, derived from git history of ${NOTICE_DOC}): ` +
        `${preNotice.join("; ")}. ` +
        "Their signature cannot have informed them of a publication the document did not yet " +
        "describe, so writing them would falsify the Art. 13 claim the roster rests on. " +
        "Give the notice directly, record it in knowledge-base/legal/ccla-register.md, then add " +
        "the id to DIRECT_NOTICE_GIVEN with that citation — or wait for them to sign again.",
    );
  }

  return accounts.length;
}

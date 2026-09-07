// RED-first per cq-write-failing-tests-before. Phase 2 of feat-ccla-signing-mechanism.
// Guard 3 — contribution-triggered entry is a property of the artifact.
//
// This is the CLO ruling's load-bearing mitigation: the Art. 6(1)(f) balancing,
// the Art. 13 notice route (NOT Art. 14 — this comment used to say 14, which
// inverts the point of the whole mechanism) and the Art. 17(3)(e) ground all
// rest on every roster
// id belonging to someone who has themselves signed the Individual CLA here.
// It is enforced by the artifact, not by an instruction in a script nobody
// re-reads — because one hurried write bypasses a convention permanently, on a
// surface from which nothing can be erased.
//
// Rows G3-M1..G3-M4 each drive this suite RED. G3-M5 (the write-side half in
// ccla-add.sh) is covered by apps/cla-evidence/scripts/ccla-add.test.sh.
import { describe, it, expect } from "vitest";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ContributionTriggeredEntryError,
  assertContributionTriggeredEntry,
  COVERAGE_MAP_NOTICE_EPOCH,
} from "@/scripts/cla-evidence/roster-entry-gate";
import { validateRosterRecord } from "@/scripts/cla-evidence/schema";

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const ROSTER_REL = "apps/cla-evidence/roster/ccla-roster.json";

/** Signed AFTER the coverage-map notice existed — the ordinary case. */
const AFTER_NOTICE = "2026-10-01T00:00:00Z";
/** Signed BEFORE it existed — cannot have been informed by signing. */
const BEFORE_NOTICE = "2026-05-04T13:13:53Z";

const ledger = (ids: number[], created_at: string = AFTER_NOTICE) => ({
  signedContributors: ids.map((id) => ({ name: `user-${id}`, id, created_at })),
});

const rosterWith = (repIds: number[][]) => ({
  schema_version: "1.0",
  organizations: repIds.map((ids, i) => ({
    legal_name: `Org ${i}`,
    record_ref: `CCLA-000${i}`,
    signed_at: "2026-09-04T00:00:00Z",
    cla_doc: { path: "docs/legal/corporate-cla.md", git_sha: "8384674", content_sha256: "a".repeat(64) },
    executed_instrument_sha256: "b".repeat(64),
    representatives: ids.map((id) => ({
      id,
      login: `user-${id}`,
      authorized_from: "2026-09-04T00:00:00Z",
      removed_at: null,
    })),
  })),
});

describe("Guard 3 — contribution-triggered entry", () => {
  it("accepts a roster whose every id has signed the ICLA, and reports the count checked", () => {
    const checked = assertContributionTriggeredEntry(rosterWith([[54279, 92384917]]), ledger([54279, 92384917]));
    // G3-M4 (dispatch): a gate that reports "0 ids checked" and exits 0 must RED.
    // The expected count is derived independently of the gate's own return.
    expect(checked).toBe(2);
  });

  // The row above cannot tell `checked` apart from `signed.size` or
  // `ledger.signedContributors.length`: every fixture where the two sets are the
  // SAME SIZE agrees with all three. Both wrong implementations report how many
  // people signed the ICLA repo-wide rather than how many roster rows were
  // examined — a gate that says "4 checked" over a 1-row roster is reporting a
  // number it did not measure. Only a ledger strictly larger than the roster
  // separates them.
  it("G3-M4b: the count is roster rows examined, NOT ledger size", () => {
    expect(assertContributionTriggeredEntry(rosterWith([[54279]]), ledger([54279, 92384917, 111, 222]))).toBe(1);
  });

  it("G3-M4c: the same id designated by two organisations counts as two rows checked", () => {
    expect(assertContributionTriggeredEntry(rosterWith([[54279], [54279]]), ledger([54279, 92384917]))).toBe(2);
  });

  it("G3-M1: a roster row whose id has NO ICLA signature is rejected, naming the id", () => {
    expect(() => assertContributionTriggeredEntry(rosterWith([[999999]]), ledger([54279]))).toThrow(
      ContributionTriggeredEntryError,
    );
    try {
      assertContributionTriggeredEntry(rosterWith([[999999]]), ledger([54279]));
      throw new Error("expected assertContributionTriggeredEntry to throw");
    } catch (e) {
      expect(e).toBeInstanceOf(ContributionTriggeredEntryError);
      expect((e as Error).message).toContain("999999");
    }
  });

  it("G3-M2: a SECOND unsigned row after a valid first is still rejected", () => {
    // A check that stops at the first member is itself the defect.
    expect(() =>
      assertContributionTriggeredEntry(rosterWith([[54279], [999999]]), ledger([54279])),
    ).toThrow(ContributionTriggeredEntryError);
  });

  it("G3-M2: EVERY offender is named, not just the first", () => {
    // Asserting only that it throws cannot distinguish "reports all" from
    // "reports the first" — with one offender the two are identical. This is
    // the arm that kills a `.slice(0, 1)` on the offender list.
    try {
      assertContributionTriggeredEntry(rosterWith([[999998, 999999]]), ledger([54279]));
      throw new Error("expected assertContributionTriggeredEntry to throw");
    } catch (e) {
      const msg = (e as Error).message;
      expect(e).toBeInstanceOf(ContributionTriggeredEntryError);
      expect(msg).toContain("999998");
      expect(msg).toContain("999999");
      expect(msg).toContain("2 roster account(s)");
    }
  });

  it("G3-M2 (sibling): a second unsigned representative inside ONE organisation is rejected", () => {
    expect(() =>
      assertContributionTriggeredEntry(rosterWith([[54279, 999999]]), ledger([54279])),
    ).toThrow(ContributionTriggeredEntryError);
  });

  it("G3-M3: an EMPTY signature ledger is refused, and says SO rather than blaming the accounts", () => {
    // Note what this arm can and cannot see. On the VERDICT the empty-ledger
    // guard is equivalent to the generic missing-account branch: with an empty
    // reference set every account is missing, so removing the guard still
    // throws and no fixture could tell the difference.
    //
    // It earns its place on the DIAGNOSIS. "The ledger did not load" and "these
    // people have not signed the ICLA" call for opposite operator actions, and
    // collapsing the first into the second is the failure AP-021 forbids. So
    // the message is the observable, and asserting it is what makes neutering
    // the guard detectable at all.
    for (const l of [ledger([]), { signedContributors: [] } as { signedContributors: never[] }]) {
      try {
        assertContributionTriggeredEntry(rosterWith([[54279]]), l);
        throw new Error("expected assertContributionTriggeredEntry to throw");
      } catch (e) {
        expect(e).toBeInstanceOf(ContributionTriggeredEntryError);
        expect((e as Error).message).toContain("ledger is EMPTY");
      }
    }
  });

  it("G3-M3 (sibling): a malformed/stub ledger is refused, not read as empty", () => {
    expect(() =>
      assertContributionTriggeredEntry(rosterWith([[54279]]), {} as unknown as { signedContributors: [] }),
    ).toThrow(ContributionTriggeredEntryError);
  });

  it("must-PASS: two organisations, all ids signed, one carrying a past removed_at", () => {
    const roster = rosterWith([[54279], [92384917]]);
    roster.organizations[1].representatives[0].removed_at = "2026-09-01T00:00:00Z" as unknown as null;
    // A withdrawal-of-designation marker does not exempt the row from the gate:
    // the id is still committed to a public surface, so it still had to have
    // signed. (The marker is NOT erasure and must never be described as one.)
    expect(assertContributionTriggeredEntry(roster, ledger([54279, 92384917]))).toBe(2);
  });

  it("matches an id that differs only in login case/spelling — the ledger is keyed on numeric id", () => {
    const roster = rosterWith([[92384917]]);
    // The fixture ledger's `name` for this id is `user-92384917`; the roster row
    // says `elvalio`. They disagree on EVERY character, and the row still passes,
    // because nothing here reads `name`. That is the property: a login can be
    // renamed and reused, a numeric id cannot.
    roster.organizations[0].representatives[0].login = "elvalio";
    expect(assertContributionTriggeredEntry(roster, ledger([92384917]))).toBe(1);
  });
});

describe("Guard 3 — the TRACKED roster, cross-checked against the real ICLA ledger", () => {
  const rosterPath = join(repoRoot, ROSTER_REL);

  // The ledger lives on an orphan branch the upstream action maintains, NOT in
  // this checkout's history. `actions/checkout` defaults to `fetch-depth: 1`
  // single-branch, so `origin/cla-signatures` is simply absent in every job that
  // has not asked for it — and this suite is in REPO_WIDE_SUITES, so it runs in
  // `test-webplat`, which has not. `git show` then exits 128 and reds the
  // required `test` check repo-wide, on every PR, for a reason unrelated to the
  // PR. Fetch the one ref we need, shallowly, and let a genuine unavailability
  // surface as an explicit refusal rather than as either a green run or a
  // mystery 128.
  const readRealLedger = (): { signedContributors: Array<{ id: number }> } => {
    const show = () =>
      execFileSync("git", ["show", "origin/cla-signatures:signatures/cla.json"], {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      });
    try {
      return JSON.parse(show());
    } catch {
      // Missing locally. One shallow fetch of exactly this ref.
      execFileSync(
        "git",
        ["fetch", "--depth=1", "origin", "+refs/heads/cla-signatures:refs/remotes/origin/cla-signatures"],
        { cwd: repoRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
      );
      return JSON.parse(show());
    }
  };

  it("anti-vacuity: the artifact under test is the tracked roster, not an inline fixture", () => {
    // `endsWith(ROSTER_REL)` on a path BUILT by joining ROSTER_REL is a
    // tautology, so it is gone. What is worth asserting is that the file exists
    // and parses as the roster it claims to be.
    expect(existsSync(rosterPath)).toBe(true);
    expect(validateRosterRecord(JSON.parse(readFileSync(rosterPath, "utf8"))).schema_version).toBe("1.0");
  });

  // Two arms over ONE code path. The tracked roster is empty until the first
  // corporate contributor lands, so the arm below it takes the early return and
  // never calls the gate at all — `assertContributionTriggeredEntry = () => 0`
  // would pass it. This arm runs the identical wiring against the identical real
  // ledger with a synthetic roster carrying a known-unsigned id, so the
  // cross-check is proven to bite today rather than on some future PR.
  it("the real ledger, fed a roster row that never signed, is REFUSED", () => {
    const realLedger = readRealLedger();
    expect(Array.isArray(realLedger.signedContributors)).toBe(true);
    expect(realLedger.signedContributors.length).toBeGreaterThan(0);
    // Not a plausible id: chosen far outside GitHub's issued range so it cannot
    // collide with a real signer and turn this arm green by accident.
    const NEVER_SIGNED = 2_147_483_646;
    expect(realLedger.signedContributors.some((c) => c.id === NEVER_SIGNED)).toBe(false);
    expect(() => assertContributionTriggeredEntry(rosterWith([[NEVER_SIGNED]]), realLedger)).toThrow(
      ContributionTriggeredEntryError,
    );
    // The far side has MOVED, and that is the finding rather than a regression.
    // Every account in today's real ledger signed before the coverage-map
    // notice existed, so none may be rostered — and the refusal must name the
    // TEMPORAL reason, not read as "they never signed". Asserting the message
    // is what separates the two, since both throw the same error type.
    const signedId = realLedger.signedContributors[0].id;
    let msg = "";
    try {
      assertContributionTriggeredEntry(rosterWith([[signedId]]), realLedger);
      throw new Error("expected a refusal for a pre-notice signer");
    } catch (e) {
      msg = e instanceof Error ? e.message : String(e);
    }
    expect(msg).toContain("coverage-map notice existed");
    expect(msg).not.toContain("have no Individual CLA signature");
  });

  it("the temporal half: signed AFTER the notice passes, BEFORE is refused, unknown fails closed", () => {
    const id = 54279;
    // must-PASS — membership plus a timestamp at/after the epoch.
    expect(assertContributionTriggeredEntry(rosterWith([[id]]), ledger([id], AFTER_NOTICE))).toBe(1);

    // must-FAIL — signed before the notice paragraph existed.
    expect(() =>
      assertContributionTriggeredEntry(rosterWith([[id]]), ledger([id], BEFORE_NOTICE)),
    ).toThrow(ContributionTriggeredEntryError);

    // must-FAIL, fail-CLOSED — "we cannot tell when" is not "late enough".
    // This is the direction that silently admits, so it gets its own row.
    const noTimestamp = { signedContributors: [{ name: `user-${id}`, id }] };
    expect(() => assertContributionTriggeredEntry(rosterWith([[id]]), noTimestamp)).toThrow(
      ContributionTriggeredEntryError,
    );
    const malformed = { signedContributors: [{ name: `user-${id}`, id, created_at: "soon" }] };
    expect(() => assertContributionTriggeredEntry(rosterWith([[id]]), malformed)).toThrow(
      ContributionTriggeredEntryError,
    );
  });

  it("the epoch is a real ISO instant, not a placeholder a comparison would silently pass", () => {
    expect(Number.isFinite(Date.parse(COVERAGE_MAP_NOTICE_EPOCH))).toBe(true);
    // A NaN epoch makes every `t < epoch` false, so the whole temporal half
    // would vanish while every other row here stayed green.
    expect(COVERAGE_MAP_NOTICE_EPOCH).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it("the tracked roster is schema-valid and every id in it has signed the ICLA", () => {
    const roster = validateRosterRecord(JSON.parse(readFileSync(rosterPath, "utf8")));
    const realLedger = readRealLedger();
    const expected = roster.organizations.reduce((n, o) => n + o.representatives.length, 0);
    if (expected === 0) {
      // Steady state before the first corporate contributor. Assert the
      // emptiness positively rather than skipping — a skipped guard reads as a
      // passing one in the run summary. Asserting on the REPRESENTATIVE count
      // rather than `organizations === []`: an organisation that has signed but
      // designated nobody yet is legitimate, and would break the stricter form.
      expect(roster.organizations.flatMap((o) => o.representatives)).toEqual([]);
      return;
    }
    expect(assertContributionTriggeredEntry(roster, realLedger)).toBe(expected);
  });
});

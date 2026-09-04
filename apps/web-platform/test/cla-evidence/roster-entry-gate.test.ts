// RED-first per cq-write-failing-tests-before. Phase 2 of feat-ccla-signing-mechanism.
// Guard 3 — contribution-triggered entry is a property of the artifact.
//
// This is the CLO ruling's load-bearing mitigation: the Art. 6(1)(f) balancing,
// the Art. 14 discharge and the Art. 17(3)(e) ground all rest on every roster
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
} from "@/scripts/cla-evidence/roster-entry-gate";
import { validateRosterRecord } from "@/scripts/cla-evidence/schema";

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const ROSTER_REL = "apps/cla-evidence/roster/ccla-roster.json";

const ledger = (ids: number[]) => ({
  signedContributors: ids.map((id) => ({ name: `user-${id}`, id })),
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

  it("G3-M2 (sibling): a second unsigned representative inside ONE organisation is rejected", () => {
    expect(() =>
      assertContributionTriggeredEntry(rosterWith([[54279, 999999]]), ledger([54279])),
    ).toThrow(ContributionTriggeredEntryError);
  });

  it("G3-M3: an EMPTY signature ledger is refused outright, not treated as permissive", () => {
    // A check whose reference set is empty passes everything. This is the
    // fail-open the gate exists to prevent.
    expect(() => assertContributionTriggeredEntry(rosterWith([[54279]]), ledger([]))).toThrow(
      ContributionTriggeredEntryError,
    );
    expect(() =>
      assertContributionTriggeredEntry(rosterWith([[54279]]), { signedContributors: [] }),
    ).toThrow(ContributionTriggeredEntryError);
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
    roster.organizations[0].representatives[0].login = "elvalio"; // ledger says "Elvalio"
    expect(assertContributionTriggeredEntry(roster, ledger([92384917]))).toBe(1);
  });
});

describe("Guard 3 — the TRACKED roster, cross-checked against the real ICLA ledger", () => {
  const rosterPath = join(repoRoot, ROSTER_REL);

  it("anti-vacuity: the artifact under test is the tracked roster, not an inline fixture", () => {
    expect(existsSync(rosterPath)).toBe(true);
    expect(rosterPath.endsWith(ROSTER_REL)).toBe(true);
  });

  it("the tracked roster is schema-valid and every id in it has signed the ICLA", () => {
    const roster = validateRosterRecord(JSON.parse(readFileSync(rosterPath, "utf8")));
    const raw = execFileSync("git", ["show", "origin/cla-signatures:signatures/cla.json"], {
      cwd: repoRoot,
      encoding: "utf8",
    });
    const realLedger = JSON.parse(raw);

    // The real ledger must be non-empty, or this whole check is vacuous.
    expect(Array.isArray(realLedger.signedContributors)).toBe(true);
    expect(realLedger.signedContributors.length).toBeGreaterThan(0);

    const expected = roster.organizations.reduce((n, o) => n + o.representatives.length, 0);
    if (expected === 0) {
      // Steady state before the first corporate contributor. Assert the
      // emptiness positively rather than skipping — a skipped guard reads as a
      // passing one in the run summary.
      expect(roster.organizations).toEqual([]);
      return;
    }
    expect(assertContributionTriggeredEntry(roster, realLedger)).toBe(expected);
  });
});

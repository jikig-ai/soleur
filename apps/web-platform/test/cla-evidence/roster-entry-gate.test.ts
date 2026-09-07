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
// ccla-add.sh) is covered by apps/cla-evidence/test/ccla-add.test.sh.
import { describe, it, expect } from "vitest";
import { execFileSync } from "node:child_process";
import { gitFixtureEnv } from "../../../../plugins/soleur/test/lib/git-fixture-env";
import { gitCleanEnv } from "../../../../plugins/soleur/test/lib/git-clean-env";
import { existsSync, readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  ContributionTriggeredEntryError,
  assertContributionTriggeredEntry,
  resolveCoverageMapNoticeEpoch,
  DIRECT_NOTICE_GIVEN,
  NOTICE_ANCHOR,
  NOTICE_DOC,
} from "@/scripts/cla-evidence/roster-entry-gate";
import { validateRosterRecord } from "@/scripts/cla-evidence/schema";

// gitCleanEnv, not gitFixtureEnv: this reads the REAL repo, so it must not carry a fixture
// ceiling — but it must still not inherit GIT_DIR, which would resolve a different toplevel.
const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
  encoding: "utf8",
  env: gitCleanEnv(),
}).trim();
const ROSTER_REL = "apps/cla-evidence/roster/ccla-roster.json";

/** Signed AFTER the coverage-map notice existed — the ordinary case. */
const AFTER_NOTICE = "2026-10-01T00:00:00Z";
/** Signed BEFORE it existed — cannot have been informed by signing. */
const BEFORE_NOTICE = "2026-05-04T13:13:53Z";

const ledger = (ids: number[], created_at: string = AFTER_NOTICE) => ({
  signedContributors: ids.map((id) => ({ name: `user-${id}`, id, created_at })),
});

/**
 * A fixed epoch for the CONTROLLED arms. The real epoch is derived from git, so
 * injecting here keeps those rows pure and keeps them from drifting the day the
 * notice commit is rewritten by a squash merge.
 */
const EPOCH = "2026-09-04T13:06:16+02:00";

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
        env: gitCleanEnv(),
      });
    try {
      return JSON.parse(show());
    } catch {
      // Missing locally. One shallow fetch of exactly this ref.
      execFileSync(
        "git",
        // `--no-tags` is load-bearing: `git fetch` auto-follows tags, and the
        // gate runner samples the repo's refs as a read-only boundary — a plain
        // fetch wrote 157 tags and tripped "[FATAL] A SUITE WROTE TO THE LIVE
        // REPOSITORY" on CI run 34123093118.
        ["fetch", "--no-tags", "--depth=1", "origin", "+refs/heads/cla-signatures:refs/remotes/origin/cla-signatures"],
        { cwd: repoRoot, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env: gitCleanEnv() },
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
    expect(assertContributionTriggeredEntry(rosterWith([[id]]), ledger([id], AFTER_NOTICE), EPOCH)).toBe(1);

    // must-FAIL — signed before the notice paragraph existed.
    expect(() =>
      assertContributionTriggeredEntry(rosterWith([[id]]), ledger([id], BEFORE_NOTICE), EPOCH),
    ).toThrow(ContributionTriggeredEntryError);

    // must-FAIL, fail-CLOSED — "we cannot tell when" is not "late enough".
    // This is the direction that silently admits, so it gets its own row.
    const noTimestamp = { signedContributors: [{ name: `user-${id}`, id }] };
    expect(() => assertContributionTriggeredEntry(rosterWith([[id]]), noTimestamp, EPOCH)).toThrow(
      ContributionTriggeredEntryError,
    );
    const malformed = { signedContributors: [{ name: `user-${id}`, id, created_at: "soon" }] };
    expect(() => assertContributionTriggeredEntry(rosterWith([[id]]), malformed, EPOCH)).toThrow(
      ContributionTriggeredEntryError,
    );
  });

  // The epoch was a hardcoded constant and that was the defect: the moment it
  // names is CREATED by merging the commit that declares it, so any literal
  // written beforehand is wrong in one of two directions — and the direction
  // that admits an un-noticed account cannot be undone. These rows assert the
  // derivation, not a value.
  it("the notice epoch is DERIVED from git history, and is a real instant", () => {
    const epoch = resolveCoverageMapNoticeEpoch(repoRoot);
    expect(Number.isFinite(Date.parse(epoch))).toBe(true);
  });

  // The tracked document has exactly ONE commit touching the anchor today, so
  // "oldest" and "newest" are the same value there and an assertion against the
  // real repo cannot tell them apart — a 1-of-1 quantification. Taking the
  // NEWEST match would walk the epoch forward on every later edit to the ICLA
  // and begin refusing people who were properly noticed, so the distinction has
  // to be instantiated somewhere. This builds a throwaway repo where the anchor
  // is touched twice, which is the only place the two answers disagree.
  it("resolves to the commit that INTRODUCED the anchor, not the most recent one touching it", () => {
    const tmp = mkdtempSync(join(tmpdir(), "notice-epoch-"));
    try {
      const git = (...args: string[]) =>
        execFileSync("git", args, {
          cwd: tmp,
          encoding: "utf8",
          stdio: ["ignore", "pipe", "pipe"],
          env: gitFixtureEnv(tmp),
        });
      git("init", "-q");
      git("config", "user.email", "t@example.com");
      git("config", "user.name", "t");
      mkdirSync(join(tmp, "docs", "legal"), { recursive: true });
      const doc = join(tmp, NOTICE_DOC);

      // Both dates pinned: the resolver reads `%cI`, and `--date` sets only the
      // AUTHOR date — leaving the committer dates at "now" would make the two
      // commits indistinguishable and quietly restore the 1-of-1 case.
      const commitAt = (msg: string, iso: string) =>
        execFileSync("git", ["commit", "-q", "-m", msg], {
          cwd: tmp,
          encoding: "utf8",
          stdio: ["ignore", "pipe", "pipe"],
          env: { ...gitFixtureEnv(tmp), GIT_AUTHOR_DATE: iso, GIT_COMMITTER_DATE: iso },
        });

      writeFileSync(doc, `intro\nthe ${NOTICE_ANCHOR} is described here\n`);
      git("add", "-A");
      commitAt("add the notice", "2026-01-01T00:00:00+00:00");

      writeFileSync(doc, `intro\nthe ${NOTICE_ANCHOR} is described here, twice: ${NOTICE_ANCHOR}\n`);
      git("add", "-A");
      commitAt("touch the anchor again", "2026-06-01T00:00:00+00:00");

      const all = git("log", "--first-parent", "-S", NOTICE_ANCHOR, "--format=%cI", "--", NOTICE_DOC)
        .trim()
        .split("\n")
        .map((l) => l.trim())
        .filter(Boolean);
      // Guard the fixture itself: if the second commit did not register as an
      // anchor change, this row silently reverts to the 1-of-1 case it exists
      // to escape.
      expect(all.length).toBe(2);

      const resolved = resolveCoverageMapNoticeEpoch(tmp);
      expect(Date.parse(resolved)).toBe(Date.parse("2026-01-01T00:00:00+00:00"));
      expect(Date.parse(resolved)).not.toBe(Date.parse("2026-06-01T00:00:00+00:00"));
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  it("the anchor still exists in the document it claims to locate", () => {
    // If the § 0 paragraph is reworded without updating NOTICE_ANCHOR, the
    // derivation stops finding it. That must REFUSE, not silently pass — so
    // this row pins the coupling that makes the fail-closed path reachable.
    const doc = readFileSync(join(repoRoot, NOTICE_DOC), "utf8");
    expect(doc).toContain(NOTICE_ANCHOR);
  });

  // The epoch must be the moment the notice reached the DEFAULT BRANCH, and
  // this repo permits all three merge methods (allow_merge_commit and
  // allow_rebase_merge are both true, and there is no merge-queue rule pinning
  // SQUASH). Under a merge commit the branch commit stays reachable with both
  // dates intact; under a rebase the commit is replayed preserving its AUTHOR
  // date. Either one leaves the epoch at the PRE-MERGE date and admits every
  // signature made in the gap. The property cannot rest on which button is
  // pressed, so all three methods are instantiated here.
  it.each(["squash", "merge-commit", "rebase"] as const)(
    "resolves to the MERGE moment under a %s merge, not the branch date",
    (method) => {
      const tmp = mkdtempSync(join(tmpdir(), `notice-merge-${method}-`));
      try {
        const at = (iso: string) => ({ GIT_AUTHOR_DATE: iso, GIT_COMMITTER_DATE: iso });
        const git = (args: string[], env: Record<string, string> = {}) =>
          execFileSync("git", args, {
            cwd: tmp,
            encoding: "utf8",
            stdio: ["ignore", "pipe", "pipe"],
            env: { ...gitFixtureEnv(tmp), ...env },
          });
        const BRANCH_AT = "2026-09-04T00:00:00+00:00";
        const MERGE_AT = "2026-09-12T00:00:00+00:00";

        git(["init", "-q", "-b", "main"]);
        git(["config", "user.email", "t@example.com"]);
        git(["config", "user.name", "t"]);
        writeFileSync(join(tmp, "README"), "base\n");
        git(["add", "-A"]);
        git(["commit", "-q", "-m", "base"], at("2026-01-01T00:00:00+00:00"));

        git(["checkout", "-q", "-b", "feat"]);
        mkdirSync(join(tmp, "docs", "legal"), { recursive: true });
        writeFileSync(join(tmp, NOTICE_DOC), `the ${NOTICE_ANCHOR} is here\n`);
        git(["add", "-A"]);
        git(["commit", "-q", "-m", "notice"], at(BRANCH_AT));

        // main moves on, so the branch is genuinely behind at merge time.
        git(["checkout", "-q", "main"]);
        writeFileSync(join(tmp, "README"), "base\nmore\n");
        git(["add", "-A"]);
        git(["commit", "-q", "-m", "other"], at("2026-09-05T00:00:00+00:00"));

        if (method === "squash") {
          git(["merge", "--squash", "feat"]);
          git(["commit", "-q", "-m", "squash the notice"], at(MERGE_AT));
        } else if (method === "merge-commit") {
          git(["merge", "--no-ff", "feat", "-q", "-m", "merge"], at(MERGE_AT));
        } else {
          git(["checkout", "-q", "feat"]);
          git(["rebase", "-q", "main"], at(MERGE_AT));
          git(["checkout", "-q", "main"]);
          git(["merge", "-q", "--ff-only", "feat"]);
        }

        const resolved = resolveCoverageMapNoticeEpoch(tmp);
        expect(Date.parse(resolved)).toBe(Date.parse(MERGE_AT));
        // The failure this pins is landing on the BRANCH date, which would
        // admit everyone who signed between the branch and the merge.
        expect(Date.parse(resolved)).not.toBe(Date.parse(BRANCH_AT));
      } finally {
        rmSync(tmp, { recursive: true, force: true });
      }
    },
  );

  // O-9. The set is empty today, so this arm exercises the validation through
  // the exported array's own contract rather than by mutating it: an entry with
  // a blank citation must be refused, because the citation is the only thing
  // that distinguishes a recorded direct notice from an assertion.
  it("a DIRECT_NOTICE_GIVEN entry without a register citation is refused", () => {
    // The shipped set must stay empty AND every entry (now or later) must carry
    // a non-blank citation — asserted as a property, so a future addition is
    // covered by this row rather than needing a new one.
    for (const d of DIRECT_NOTICE_GIVEN) {
      expect(typeof d.register_ref === "string" && d.register_ref.trim() !== "").toBe(true);
    }
    expect(DIRECT_NOTICE_GIVEN.length).toBe(0);
  });

  it("an unresolvable epoch REFUSES rather than admitting everyone", () => {
    // Fail-closed is the whole safety argument: "we cannot establish when the
    // notice existed" must never read as "it existed early enough".
    // Two DIFFERENT unresolvable shapes, because they take different branches
    // and only one of them was reachable before: a path where git itself fails,
    // and a healthy repo where the ANCHOR is simply absent. The second is the
    // one that fires if the § 0 paragraph is ever reworded, and a permissive
    // return there would hand every account an epoch of 1970.
    expect(() => resolveCoverageMapNoticeEpoch("/nonexistent-repo-path-for-this-test")).toThrow(
      ContributionTriggeredEntryError,
    );

    const tmp = mkdtempSync(join(tmpdir(), "notice-anchor-absent-"));
    try {
      const git = (...args: string[]) =>
        execFileSync("git", args, {
          cwd: tmp,
          encoding: "utf8",
          stdio: ["ignore", "pipe", "pipe"],
          env: gitFixtureEnv(tmp),
        });
      git("init", "-q");
      git("config", "user.email", "t@example.com");
      git("config", "user.name", "t");
      mkdirSync(join(tmp, "docs", "legal"), { recursive: true });
      // The document exists and has history — it just never carried the anchor.
      writeFileSync(join(tmp, NOTICE_DOC), "an individual CLA with no coverage-map paragraph\n");
      git("add", "-A");
      git("commit", "-q", "-m", "icla without the notice");
      expect(() => resolveCoverageMapNoticeEpoch(tmp)).toThrow(ContributionTriggeredEntryError);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
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

// RED-first per cq-write-failing-tests-before. Phase 2 of feat-ccla-signing-mechanism.
// Guard 2 — the roster schema is closed, and schema_version is asserted at parse.
//
// The mutation matrix below was derived from the plan's `## Guard Contract`
// BEFORE the guard existed. Rows G2-M1..G2-M5 each drive this suite RED.
import { describe, it, expect } from "vitest";
import {
  RosterSchema,
  SCHEMA_VERSION,
  SchemaVersionMismatchError,
  validateRosterRecord,
} from "@/scripts/cla-evidence/schema";

/**
 * A minimal roster that MUST validate. Every mutation below is this object
 * with exactly one thing changed, so a RED row attributes to that one change.
 */
const validRoster = () => ({
  schema_version: "1.0",
  organizations: [
    {
      legal_name: "Example Fixture Co",
      record_ref: "CCLA-0001",
      signed_at: "2026-09-04T00:00:00Z",
      cla_doc: {
        path: "docs/legal/corporate-cla.md",
        git_sha: "8384674",
        content_sha256: "a".repeat(64),
      },
      executed_instrument_sha256: "b".repeat(64),
      representatives: [{ id: 92384917, login: "Elvalio", authorized_from: "2026-09-04T00:00:00Z", removed_at: null }],
    },
  ],
});

describe("Guard 2 — RosterSchema", () => {
  it("accepts the canonical roster shape", () => {
    const r = validateRosterRecord(validRoster());
    // Anti-vacuity: assert we actually validated a populated structure. Deleting
    // this count assertion is the documented harness mutation and must RED.
    expect(r.organizations).toHaveLength(1);
    expect(r.organizations[0].representatives).toHaveLength(1);
  });

  it("pins schema_version as the STRING '1.0', mirroring schema.ts", () => {
    // An integer 1 here would contradict the precedent TR1 mandates.
    expect(SCHEMA_VERSION).toBe("1.0");
    expect(typeof SCHEMA_VERSION).toBe("string");
  });

  it("G2-M1: a bumped schema_version in the payload throws with exit code 3", () => {
    const bad = { ...validRoster(), schema_version: "2.0" };
    expect(() => validateRosterRecord(bad)).toThrow(SchemaVersionMismatchError);
    try {
      validateRosterRecord(bad);
      throw new Error("expected validateRosterRecord to throw");
    } catch (e) {
      expect(e).toBeInstanceOf(SchemaVersionMismatchError);
      expect((e as SchemaVersionMismatchError).exitCode).toBe(3);
    }
  });

  it("G2-M2: a missing schema_version throws", () => {
    const bad = validRoster() as Record<string, unknown>;
    delete bad.schema_version;
    expect(() => validateRosterRecord(bad)).toThrow(SchemaVersionMismatchError);
  });

  it("G2-M3: an undeclared TOP-LEVEL key is rejected by .strict()", () => {
    const bad = { ...validRoster(), signatory_email: "someone@example.com" };
    expect(() => validateRosterRecord(bad)).toThrow(SchemaVersionMismatchError);
  });

  it("G2-M3: an undeclared key nested in a representative is rejected by .strict()", () => {
    // This is the half a four-name denylist walks straight through, and it is
    // why the key set is closed by construction rather than denylisted.
    const bad = validRoster();
    (bad.organizations[0].representatives[0] as Record<string, unknown>).signatory_name = "A Person";
    expect(() => validateRosterRecord(bad)).toThrow(SchemaVersionMismatchError);
  });

  it("G2-M3: an undeclared key nested in an organisation is rejected by .strict()", () => {
    const bad = validRoster();
    (bad.organizations[0] as Record<string, unknown>).corporate_email = "legal@example.com";
    expect(() => validateRosterRecord(bad)).toThrow(SchemaVersionMismatchError);
  });

  it("G2-M4: a SECOND organisation invalid after a valid first is still rejected", () => {
    // A validator that stops at the first member is itself the defect.
    const bad = validRoster();
    const second = JSON.parse(JSON.stringify(bad.organizations[0]));
    second.record_ref = "CCLA-0002";
    second.representatives[0].id = "92384917"; // string where an int is declared
    bad.organizations.push(second);
    expect(() => validateRosterRecord(bad)).toThrow(SchemaVersionMismatchError);
  });

  it("G2-M4 (sibling): a second representative invalid after a valid first is rejected", () => {
    const bad = validRoster();
    bad.organizations[0].representatives.push({
      id: "54279" as unknown as number,
      login: "deruelle",
      authorized_from: "2026-09-04T00:00:00Z",
      removed_at: null,
    });
    expect(() => validateRosterRecord(bad)).toThrow(SchemaVersionMismatchError);
  });

  it("rejects a non-64-hex executed_instrument_sha256", () => {
    const bad = validRoster();
    bad.organizations[0].executed_instrument_sha256 = "not-a-hash";
    expect(() => validateRosterRecord(bad)).toThrow(SchemaVersionMismatchError);
  });

  it("B1-c-2: legal_name may be null (sole trader — held off-repo), record_ref still required", () => {
    // Must-PASS, non-canonical. An organisation trading under a natural
    // person's name gets the opaque record_ref only.
    const soleTrader = validRoster();
    soleTrader.organizations[0].legal_name = null as unknown as string;
    expect(() => validateRosterRecord(soleTrader)).not.toThrow();

    const noRef = validRoster();
    delete (noRef.organizations[0] as Record<string, unknown>).record_ref;
    expect(() => validateRosterRecord(noRef)).toThrow(SchemaVersionMismatchError);
  });

  // The three G2-M3 rows above name five keys — `signatory_email`,
  // `signatory_name`, `corporate_email`, `notes`, `comment`. A
  // `.passthrough().superRefine()` carrying exactly that five-name DENYLIST
  // satisfies every one of them, which is precisely the implementation the
  // schema's own comment says `.strict()` defeats. The claim is about keys
  // NOBODY would think to denylist, so the fixture has to use one: an
  // undeclared key with no meaning at all, at every level the roster has.
  // `cla_doc` is the fourth level and the one most likely to lose its
  // `.strict()` by accident, because `ClaDocSchema` is shared with the evidence
  // record where it is deliberately NOT strict — and `cla_doc.signatory_email`
  // is exactly the shape the CLO ruling forbids.
  it("G2-M3: an undeclared key nobody would denylist is rejected at ALL FOUR levels", () => {
    const levels: Array<[string, (r: ReturnType<typeof validRoster>) => Record<string, unknown>]> = [
      ["top level", (r) => r as unknown as Record<string, unknown>],
      ["organisation", (r) => r.organizations[0] as unknown as Record<string, unknown>],
      ["representative", (r) => r.organizations[0].representatives[0] as unknown as Record<string, unknown>],
      ["cla_doc", (r) => r.organizations[0].cla_doc as unknown as Record<string, unknown>],
    ];
    for (const [label, at] of levels) {
      const roster = validRoster();
      at(roster).zz_unforeseen = 1;
      expect(() => validateRosterRecord(roster), label).toThrow(SchemaVersionMismatchError);
    }
  });

  // Seven constraints the suite declared and never fixtured. Each row below was
  // measured to survive the battery as written: relaxing the constraint in
  // schema.ts left every other fixture green. A regex or a format that no
  // fixture ever violates is documentation, not a guard.
  it("G2-M6: each declared field constraint refuses its own violation", () => {
    const cases: Array<[string, (r: ReturnType<typeof validRoster>) => void]> = [
      ["record_ref shape", (r) => void (r.organizations[0].record_ref = "NOPE")],
      ["signed_at needs an offset", (r) => void (r.organizations[0].signed_at = "2026-09-04")],
      [
        "authorized_from needs an offset",
        (r) => void (r.organizations[0].representatives[0].authorized_from = "2026-09-04"),
      ],
      [
        "removed_at is a timestamp or null, not free text",
        (r) => void (r.organizations[0].representatives[0].removed_at = "yesterday" as unknown as null),
      ],
      ["cla_doc.git_sha shape", (r) => void (r.organizations[0].cla_doc.git_sha = "not-a-sha")],
      [
        "sha256 is lowercase hex",
        (r) => void (r.organizations[0].executed_instrument_sha256 = "B".repeat(64)),
      ],
      ["id is a positive integer", (r) => void (r.organizations[0].representatives[0].id = 0)],
      // The roster is permanently public. An unbounded string field is a place
      // to put something that is not a login and not a company name.
      ["login is bounded at GitHub's own 39-char ceiling", (r) => void (r.organizations[0].representatives[0].login = "x".repeat(40))],
      ["legal_name is bounded", (r) => void (r.organizations[0].legal_name = "x".repeat(201))],
    ];
    for (const [label, mutate] of cases) {
      const roster = validRoster();
      mutate(roster);
      expect(() => validateRosterRecord(roster), label).toThrow(SchemaVersionMismatchError);
    }
  });

  // The far side of the withdrawal marker. `removed_at` is nullable BY DESIGN,
  // and tightening it to `z.null()` — the mutation that breaks every withdrawal
  // the operator will ever record — is invisible to a suite whose every fixture
  // leaves it null. This is the only must-PASS that sees it.
  it("G2-M6b: a past withdrawal-of-designation timestamp is ACCEPTED", () => {
    const withdrawn = validRoster();
    withdrawn.organizations[0].representatives[0].removed_at = "2026-09-01T00:00:00Z" as unknown as null;
    expect(() => validateRosterRecord(withdrawn)).not.toThrow();
  });

  it("the schema admits NO free-text field on this permanently-public surface", () => {
    // An operator `notes` string was drafted into the schema and removed. The
    // roster is world-readable and cannot be erased, and no limb of the
    // Art. 6(1)(f) balancing test covers unbounded operator prose about a third
    // party. This asserts the ABSENCE, so reintroducing such a key reds here
    // rather than landing quietly.
    const withFreeText = validRoster();
    (withFreeText.organizations[0] as Record<string, unknown>).notes = "countersigned by CLO";
    expect(() => validateRosterRecord(withFreeText)).toThrow(SchemaVersionMismatchError);

    const withComment = validRoster();
    (withComment.organizations[0] as Record<string, unknown>).comment = "ex-employee, left under a cloud";
    expect(() => validateRosterRecord(withComment)).toThrow(SchemaVersionMismatchError);
  });

  it("G2-M5 (dispatch): validateRosterRecord must parse, not pass the payload through", () => {
    // If the validator returned its input unvalidated, this obviously-invalid
    // payload would come back instead of throwing.
    expect(() => validateRosterRecord({ nonsense: true })).toThrow(SchemaVersionMismatchError);
    expect(RosterSchema.safeParse({ nonsense: true }).success).toBe(false);
  });
});

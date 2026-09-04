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
      legal_name: "Convergence SARL",
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

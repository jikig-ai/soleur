/**
 * PR-I (#4078) Phase 9.5 — Revocation-reason enum exhaustiveness + parity (TR6).
 *
 * Three complementary gates in ONE file (mirrors action-class-exhaustive.test.ts):
 *
 *   (a) Parity: `REVOCATION_REASON_COPY` covers every `RevocationReason`
 *       member (compile-time via `satisfies`, embedded in source). Runtime
 *       parity asserted across all enum members + copy keys.
 *   (b) Exhaustiveness: a switch over `RevocationReason` with `_exhaustive:
 *       never` rail (compile-time). Adding a 9th value without updating
 *       this switch fails `tsc --noEmit`.
 *   (c) Cardinality lock: the enum has EXACTLY 8 members (count locked
 *       at the runtime layer; AC6 separately locks it at the SQL CHECK
 *       constraint layer via psql).
 *   (d) Migration-source enum parity: the 8 values in mig 053's CHECK
 *       constraint match the 8 keys in REVOCATION_REASON_COPY one-to-one.
 *       Catches drift if either side adds a value without the other.
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, test } from "vitest";

import {
  REVOCATION_REASON_COPY,
  type RevocationReason,
} from "@/lib/messages/trust-tier-copy";

// (a) Parity gate — compile-time. REVOCATION_REASON_COPY is declared
// `as const` and typed as Record<RevocationReason, ...> indirectly via
// `keyof typeof REVOCATION_REASON_COPY`. The `satisfies` rail below is
// the compile-time enforcement (any new enum value without a copy entry
// breaks tsc here before the file runs).
const _copyCover: Record<RevocationReason, { label: string; description: string }> =
  REVOCATION_REASON_COPY satisfies Record<
    RevocationReason,
    { label: string; description: string }
  >;
void _copyCover;

// (b) Exhaustiveness rail — compile-time. Adding a 9th RevocationReason
// member without a switch arm here fails `tsc --noEmit` with
// `TS2322 ... not assignable to type 'never'`.
function assertExhaustive(r: RevocationReason): string {
  switch (r) {
    case "founder_revoked":
      return "founder_revoked";
    case "quota_exhausted":
      return "quota_exhausted";
    case "expired":
      return "expired";
    case "dsr_erasure":
      return "dsr_erasure";
    case "regulator_ordered":
      return "regulator_ordered";
    case "vendor_tos_revoked":
      return "vendor_tos_revoked";
    case "policy_violation":
      return "policy_violation";
    case "quarantine_retroactive":
      return "quarantine_retroactive";
    default: {
      const _exhaustive: never = r;
      void _exhaustive;
      return "founder_revoked";
    }
  }
}
void assertExhaustive;

describe("revocation-reason registry — runtime gates", () => {
  test("(c) cardinality: REVOCATION_REASON_COPY has exactly 8 keys", () => {
    expect(Object.keys(REVOCATION_REASON_COPY)).toHaveLength(8);
  });

  test("(d) parity: every key has non-empty label + description", () => {
    for (const [key, copy] of Object.entries(REVOCATION_REASON_COPY)) {
      expect(copy.label.length, `${key} label empty`).toBeGreaterThan(0);
      expect(
        copy.description.length,
        `${key} description empty`,
      ).toBeGreaterThan(0);
    }
  });

  test("(e) migration-source parity: mig 053 CHECK enum matches TS keys", () => {
    // Read the migration file and extract the 8 quoted values from the
    // template_authorizations_revocation_reason_check CHECK constraint.
    const migPath = join(
      __dirname,
      "../../../supabase/migrations/053_template_authorizations.sql",
    );
    const sql = readFileSync(migPath, "utf8");

    // Find the CHECK block. Regex matches: ... IN ( 'a', 'b', ..., 'h' )
    const checkBlockMatch = sql.match(
      /template_authorizations_revocation_reason_check[\s\S]*?IN\s*\(([\s\S]*?)\)/,
    );
    expect(
      checkBlockMatch,
      "mig 053 must define template_authorizations_revocation_reason_check",
    ).not.toBeNull();

    const valuesBlob = checkBlockMatch![1]!;
    const sqlValues = Array.from(valuesBlob.matchAll(/'([a-z_]+)'/g)).map(
      (m) => m[1]!,
    );

    expect(
      sqlValues.length,
      "mig 053 CHECK must list exactly 8 values",
    ).toBe(8);

    // Set-equality between SQL CHECK values and TS keys (order-
    // independent; the SQL side accepts the value in any order).
    expect(new Set(sqlValues)).toEqual(
      new Set(Object.keys(REVOCATION_REASON_COPY)),
    );
  });
});

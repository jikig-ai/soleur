import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 144_pending_checkout_sessions.sql.
//
// File-parse only, mirroring 136-workflow-cost-rollup.test.ts. It asserts the
// SQL's SHAPE; behaviour is covered by the route-level vitest cases in
// api-checkout-idempotency.test.ts.
//
// Anchoring note: every assertion anchors on a syntactic construct, never a
// bare token — `pending_checkout_sessions`, `ON DELETE CASCADE` and RLS terms
// also appear in this migration's own header comments, so a bare-token grep
// would pass vacuously on prose. LAWFUL_BASIS is itself a comment annotation,
// so it is asserted against the RAW file by construction.
//
// Plan: 2026-09-28-fix-billing-checkout-server-idempotency-plan.md Phase 1.

const MIGRATIONS_DIR = path.join(__dirname, "../../supabase/migrations");
const MIGRATION_PATH = path.join(
  MIGRATIONS_DIR,
  "144_pending_checkout_sessions.sql",
);
const DOWN_PATH = path.join(
  MIGRATIONS_DIR,
  "144_pending_checkout_sessions.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");

/** Strip `--` line comments. Assertions over executable SQL run on this. */
function stripSqlComments(sqlText: string): string {
  return sqlText.replace(/--[^\n]*/g, "");
}

describe("migration 144_pending_checkout_sessions", () => {
  it("creates the table with user_id as PRIMARY KEY", () => {
    const code = stripSqlComments(sql);
    expect(code).toMatch(
      /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.pending_checkout_sessions\s*\(/i,
    );
    expect(code).toMatch(
      /user_id\s+uuid\s+PRIMARY\s+KEY\s+REFERENCES\s+public\.users\s*\(\s*id\s*\)/i,
    );
  });

  it("declares ON DELETE CASCADE on the users FK (Art. 17 erasure path)", () => {
    const code = stripSqlComments(sql);
    expect(code).toMatch(
      /REFERENCES\s+public\.users\s*\(\s*id\s*\)\s+ON\s+DELETE\s+CASCADE/i,
    );
  });

  it("carries the claim/reuse columns the route writes", () => {
    const code = stripSqlComments(sql);
    expect(code).toMatch(/\bsession_id\s+text\b/i);
    expect(code).toMatch(/\btarget_tier\s+text\b/i);
    expect(code).toMatch(
      /\bcreated_at\s+timestamptz\s+NOT\s+NULL\s+DEFAULT\s+now\s*\(\s*\)/i,
    );
  });

  it("enables RLS with zero policies (service-role only)", () => {
    const code = stripSqlComments(sql);
    expect(code).toMatch(
      /ALTER\s+TABLE\s+public\.pending_checkout_sessions\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
    );
    expect(code).not.toMatch(
      /CREATE\s+POLICY[^;]*ON\s+public\.pending_checkout_sessions\b/i,
    );
    expect(code).not.toMatch(
      /CREATE\s+POLICY[^;]*ON\s+pending_checkout_sessions\b/i,
    );
  });

  it("carries the LAWFUL_BASIS contract annotation (Art. 6(1)(b))", () => {
    // The annotation IS a comment — asserted against the raw file by design.
    expect(sql).toMatch(/--\s*LAWFUL_BASIS:\s*Art\.\s*6\(1\)\(b\)/);
  });

  it("documents the transient lifecycle in COMMENT ON TABLE (Art. 5(1)(e))", () => {
    expect(sql).toMatch(
      /COMMENT\s+ON\s+TABLE\s+public\.pending_checkout_sessions\s+IS/i,
    );
  });

  it("uses no non-transactional DDL (runner wraps each file in a transaction)", () => {
    const code = stripSqlComments(sql);
    expect(code).not.toMatch(/\bCONCURRENTLY\b/i);
  });

  describe("144_pending_checkout_sessions.down.sql", () => {
    const down = readFileSync(DOWN_PATH, "utf8");

    it("drops the table", () => {
      const code = stripSqlComments(down);
      expect(code).toMatch(
        /DROP\s+TABLE\s+IF\s+EXISTS\s+public\.pending_checkout_sessions\b/i,
      );
    });
  });
});

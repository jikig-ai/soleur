import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// BYOK Delegations PR-A (#4232) — WORM column-enumeration sentinel
// (SS F4, plan §Phase 4.22).
//
// The byok_delegations_no_mutate trigger is a structural-diff WORM
// guard: it enumerates every column of byok_delegations explicitly
// across three legitimate UPDATE shapes (revoke flip / Art. 17
// anonymise / cap-update flip). A future migration that adds a column
// to byok_delegations WITHOUT updating the trigger creates a fail-
// OPEN — the new column's mutation becomes silently permitted by every
// shape (the trigger compares OLD vs NEW for ENUMERATED columns only;
// non-enumerated columns are invisible to the diff).
//
// This test fails loudly when a column from byok_delegations does not
// appear in the trigger body. The plan §Phase 4.22 originally specified
// a live-DB version (information_schema.columns + pg_get_functiondef);
// this offline source-grep variant runs in the standard unit suite
// without TENANT_INTEGRATION_TEST gating and catches the same class
// of regression at PR review time (before the migration even applies).
//
// Why offline is sufficient: any change to byok_delegations.<col>
// MUST land in the SAME migration that defines the trigger (we can't
// have a sibling migration adding a column without our trigger seeing
// it, because the file is single-source-of-truth at write time). The
// live-DB variant would only catch drift introduced via direct-SQL
// outside the migration system — a path that already violates
// `hr-all-infrastructure-provisioning-servers`.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/064_byok_delegations.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");

// Strip line comments so commented-out column mentions don't false-
// match the trigger body presence check.
const executable = sql.replace(/--[^\n]*/g, "");

function extractTableColumns(): string[] {
  // Grab the CREATE TABLE ... ( ... ); block.
  const m = executable.match(
    /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.byok_delegations\s*\(([\s\S]*?)\n\);/,
  );
  if (!m) throw new Error("CREATE TABLE block not found");
  const body = m[1];
  // Each column line starts with `<name> <type> ...`; CONSTRAINT lines
  // start with `CONSTRAINT`. Filter to identifier-first lines, strip
  // trailing commas.
  const cols: string[] = [];
  for (const rawLine of body.split("\n")) {
    const line = rawLine.trim();
    if (!line) continue;
    if (line.startsWith("CONSTRAINT")) continue;
    // Skip multi-line continuations (lines starting with OR / AND / NOT
    // inside a CHECK constraint that wasn't preceded by CONSTRAINT —
    // none in our table, but defensive).
    const idMatch = line.match(/^([a-z_][a-z0-9_]*)\s+(?:uuid|int|text|timestamptz)\b/i);
    if (idMatch) cols.push(idMatch[1]);
  }
  if (cols.length === 0) throw new Error("no columns extracted");
  return cols;
}

function extractWormTriggerBody(): string {
  // Match from CREATE OR REPLACE FUNCTION byok_delegations_no_mutate
  // through the closing $$ + ; delimiter.
  const m = executable.match(
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.byok_delegations_no_mutate\(\)[\s\S]*?\$\$;/,
  );
  if (!m) throw new Error("byok_delegations_no_mutate function body not found");
  return m[0];
}

describe("byok_delegations WORM column-enumeration sentinel (SS F4)", () => {
  const cols = extractTableColumns();
  const trigger = extractWormTriggerBody();

  it("extracted at least the 14 v3 columns", () => {
    // Sanity-check the extractor itself — if this drops to 0 or under 10,
    // the table-shape regex regressed silently and every per-column
    // assertion below would vacuously pass.
    expect(cols.length).toBeGreaterThanOrEqual(14);
  });

  it("trigger body is non-empty (extractor sanity)", () => {
    expect(trigger.length).toBeGreaterThan(500);
  });

  for (const col of [
    "grantor_user_id",
    "grantee_user_id",
    "workspace_id",
    "daily_usd_cap_cents",
    "hourly_usd_cap_cents",
    "created_by_user_id",
    "created_at",
    "expires_at",
    "revoked_at",
    "revoked_by_user_id",
    "revocation_reason",
    "cap_updated_at",
    "cap_updated_by_user_id",
  ]) {
    it(`trigger body references column "${col}" (column-enum coverage)`, () => {
      expect(trigger).toContain(col);
    });
  }

  it("every extracted column appears in the trigger body (dynamic enumeration)", () => {
    const missing: string[] = [];
    for (const col of cols) {
      if (col === "id") continue; // PRIMARY KEY id is immutable by Postgres; trigger doesn't need to enumerate it.
      if (!trigger.includes(col)) missing.push(col);
    }
    expect(
      missing.length,
      `WORM trigger body does NOT reference these columns of byok_delegations: ${missing.join(", ")}. ` +
        `Adding a column to byok_delegations without updating byok_delegations_no_mutate creates a fail-OPEN ` +
        `(the new column's mutation becomes silently permitted under every shape). ` +
        `Update the trigger to enumerate the new column in each of Shape 1 (revoke flip), Shape 2 (anonymise), ` +
        `and Shape 3 (cap-update flip).`,
    ).toBe(0);
  });
});

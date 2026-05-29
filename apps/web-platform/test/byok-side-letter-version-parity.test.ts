import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

// AC4 (feat-byok-delegation-consent, #4625): the TS constant
// BYOK_SIDE_LETTER_VERSION MUST equal the literal returned by the SQL
// function public.current_byok_side_letter_version() (migration 083). The
// SECURITY DEFINER lease gate resolve_byok_key_owner compares the stored
// side_letter_version against the SQL function, so a one-sided bump (TS
// without SQL, or SQL without TS) silently diverges dev from prd and
// either fails-open stale acceptances or locks out fresh ones.
//
// This is the CI parity gate: it runs in the standard vitest suite, so a
// mismatch FAILS THE BUILD (not just a runtime surprise). It is an offline
// text-lint over the migration source — no live DB required. Bump BOTH the
// TS constant and the SQL literal in the same migration.

const GATE_MIGRATION = path.join(
  __dirname,
  "../supabase/migrations/083_byok_delegation_consent_gate.sql",
);

function extractSqlVersionLiteral(sql: string): string | null {
  // Isolate the current_byok_side_letter_version() function body, then pull
  // the first single-quoted string literal it returns.
  const fnMatch = sql.match(
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.current_byok_side_letter_version\s*\(\s*\)[\s\S]*?AS\s+\$\$([\s\S]*?)\$\$\s*;/i,
  );
  if (!fnMatch) return null;
  const body = fnMatch[1];
  const literalMatch = body.match(/'([^']*)'/);
  return literalMatch ? literalMatch[1] : null;
}

describe("BYOK side-letter version parity (AC4 — CI gate)", () => {
  const sql = readFileSync(GATE_MIGRATION, "utf8");

  it("migration 083 defines current_byok_side_letter_version() returning a literal", () => {
    expect(extractSqlVersionLiteral(sql)).not.toBeNull();
  });

  it("SQL current_byok_side_letter_version() === TS BYOK_SIDE_LETTER_VERSION", () => {
    const sqlVersion = extractSqlVersionLiteral(sql);
    expect(sqlVersion).toBe(BYOK_SIDE_LETTER_VERSION);
  });
});

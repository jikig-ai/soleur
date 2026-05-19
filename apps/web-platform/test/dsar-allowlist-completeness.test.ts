import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { resolve, join } from "node:path";

// Phase 5 file-parse lint per AC28 + S6 of plan rev-2.
//
// Walks every migration file in supabase/migrations/, extracts each
// `create table public.<name>` block, classifies the table as
// "user-FK" if it has a column that references public.users(id) or
// auth.users(id) (directly or transitively via FK chains we encode
// here), and asserts that every user-FK table appears in either
// `DSAR_TABLE_ALLOWLIST` or `DSAR_TABLE_EXCLUSIONS` with a non-empty
// reason.
//
// Failure mode this prevents: a future migration adds
// `public.feature_x_settings (user_id uuid references public.users)`
// and ships without anyone updating the DSAR allowlist — the user's
// Art. 15 export silently omits that data class for years.
//
// Per plan AC28 the canonical detector is `information_schema +
// key_column_usage + referential_constraints`, but for unit-test
// portability (no live SQL connection) we re-implement the same
// invariant at the migration-source level. The plan's intent is "the
// allowlist is provably-complete against the schema"; both substrates
// honour it.

import {
  DSAR_TABLE_ALLOWLIST,
  DSAR_TABLE_EXCLUSIONS,
  DSAR_TABLES_KNOWN,
} from "../server/dsar-export-allowlist";

const MIGRATIONS_DIR = resolve(__dirname, "../supabase/migrations");

interface ParsedTable {
  name: string;
  columns: string;
  sourceFile: string;
}

function loadMigrationsByFile(): { file: string; sql: string }[] {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith(".sql"))
    .sort();
  return files.map((f) => ({
    file: f,
    sql: readFileSync(join(MIGRATIONS_DIR, f), "utf-8"),
  }));
}

function parseTables(): ParsedTable[] {
  const tableRe =
    /create\s+table\s+(?:if\s+not\s+exists\s+)?public\.([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\)\s*;/gi;
  const out: ParsedTable[] = [];
  for (const { file, sql } of loadMigrationsByFile()) {
    for (const match of sql.matchAll(tableRe)) {
      out.push({ name: match[1], columns: match[2], sourceFile: file });
    }
  }
  return out;
}

function tableReferencesUsers(
  table: ParsedTable,
  knownUserChildren: Set<string>,
): boolean {
  // Direct reference to public.users(id) or auth.users(id).
  if (
    /references\s+public\.users\s*\(\s*id\s*\)/i.test(table.columns) ||
    /references\s+auth\.users\s*\(\s*id\s*\)/i.test(table.columns)
  ) {
    return true;
  }
  // Transitive: references a known user-FK descendant. Pattern e.g.
  //   conversation_id uuid REFERENCES public.conversations(id)
  for (const childTable of knownUserChildren) {
    const re = new RegExp(`references\\s+public\\.${childTable}\\s*\\(`, "i");
    if (re.test(table.columns)) return true;
  }
  return false;
}

function discoverUserFkTables(tables: ParsedTable[]): Map<string, ParsedTable> {
  // First pass: direct references. Subsequent passes: transitive
  // references to first-pass results until no growth (handles
  // arbitrary chain depth).
  const known = new Map<string, ParsedTable>();
  for (const t of tables) {
    if (tableReferencesUsers(t, new Set())) known.set(t.name, t);
  }
  let grew = true;
  while (grew) {
    grew = false;
    for (const t of tables) {
      if (known.has(t.name)) continue;
      if (tableReferencesUsers(t, new Set(known.keys()))) {
        known.set(t.name, t);
        grew = true;
      }
    }
  }
  return known;
}

describe("DSAR allowlist completeness (AC28 + S6)", () => {
  const tables = parseTables();
  const userFkTables = discoverUserFkTables(tables);

  it("discovers at least the canonical user-FK tables", () => {
    expect(userFkTables.has("conversations")).toBe(true);
    expect(userFkTables.has("messages")).toBe(true);
    expect(userFkTables.has("api_keys")).toBe(true);
    expect(userFkTables.has("kb_share_links")).toBe(true);
    expect(userFkTables.has("team_names")).toBe(true);
  });

  it("every user-FK table is either in the allowlist or exclusions", () => {
    const missing: string[] = [];
    for (const tableName of userFkTables.keys()) {
      if (!DSAR_TABLES_KNOWN.has(tableName)) {
        missing.push(tableName);
      }
    }
    expect(
      missing,
      `Tables found in migrations with FK to public.users / auth.users ` +
        `(or transitive) that are missing from both DSAR_TABLE_ALLOWLIST ` +
        `and DSAR_TABLE_EXCLUSIONS: ${missing.join(", ")}. Add to one of ` +
        `these in apps/web-platform/server/dsar-export-allowlist.ts. ` +
        `An exclusion MUST carry a reason explaining why the table holds ` +
        `no Art. 15-relevant personal data.`,
    ).toEqual([]);
  });

  it("every excluded table has a non-empty reason", () => {
    for (const [table, reason] of Object.entries(DSAR_TABLE_EXCLUSIONS)) {
      expect(
        reason.trim().length,
        `Excluded table "${table}" has an empty reason. Per AC28+S6, ` +
          `every exclusion MUST document WHY the table is excluded.`,
      ).toBeGreaterThan(20);
    }
  });

  it("allowlist and exclusions do not overlap", () => {
    const overlap = Object.keys(DSAR_TABLE_ALLOWLIST).filter(
      (t) => t in DSAR_TABLE_EXCLUSIONS,
    );
    expect(
      overlap,
      `Tables appear in BOTH allowlist and exclusions: ${overlap.join(", ")}. ` +
        `Choose one.`,
    ).toEqual([]);
  });

  it("ownerField for every allowlisted table matches a column in the migration", () => {
    for (const [table, spec] of Object.entries(DSAR_TABLE_ALLOWLIST)) {
      if (spec.joinVia) continue; // owner resolved via parent table
      const parsed =
        userFkTables.get(table) ?? tables.find((t) => t.name === table);
      if (!parsed) continue; // sanity-discovery test catches absence
      const colRe = new RegExp(`\\b${spec.ownerField}\\b\\s+uuid`, "i");
      expect(
        colRe.test(parsed.columns),
        `Allowlisted table "${table}" declares ownerField "${spec.ownerField}" ` +
          `but no matching uuid column found in its CREATE TABLE definition. ` +
          `Migration: ${parsed.sourceFile}.`,
      ).toBe(true);
    }
  });
});

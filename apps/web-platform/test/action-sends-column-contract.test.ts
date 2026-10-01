/**
 * Every column the app names on `action_sends` must exist in the migrations.
 *
 * Every suite that touches the table mocks the Supabase client, and a mock
 * answers for any column name. `action_sends.created_at` has never existed (the
 * timestamp is `clicked_at`, migration 051), yet the leader loop read it from
 * 2026-09-03 until #8803's review: every spawn failed at
 * `read-action-send-created-at`, and the dashboard cost route answered 0 cents,
 * both behind green suites. This contract reads the DDL, not a fixture.
 */

import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

const APP = join(__dirname, "..");
const MIGRATIONS = join(APP, "supabase/migrations");

const TYPE = "(?:uuid|text|timestamptz|boolean|jsonb|smallint|integer|bigint)";

/** Columns declared by CREATE TABLE plus every `ALTER TABLE … ADD COLUMN`. */
function declaredColumns(): Set<string> {
  const cols = new Set<string>();
  for (const f of readdirSync(MIGRATIONS).filter((n) => n.endsWith(".sql") && !n.endsWith(".down.sql"))) {
    const sql = readFileSync(join(MIGRATIONS, f), "utf8");
    const create = sql.match(/CREATE TABLE(?: IF NOT EXISTS)? public\.action_sends \(([\s\S]*?)\n\);/);
    if (create) {
      for (const m of create[1].matchAll(new RegExp(`^\\s+([a-z_]+)\\s+${TYPE}\\b`, "gm"))) cols.add(m[1]);
    }
    for (const stmt of sql.matchAll(/ALTER TABLE(?: IF EXISTS)? public\.action_sends\b([\s\S]*?);/g)) {
      for (const m of stmt[1].matchAll(/ADD COLUMN(?: IF NOT EXISTS)?\s+([a-z_]+)/g)) cols.add(m[1]);
    }
  }
  return cols;
}

/** Column names a `.from("action_sends")` chain reads, filters or orders on. */
export function referencedColumns(src: string): string[] {
  const out: string[] = [];
  for (const chain of src.matchAll(/\.from\(\s*"action_sends"\s*\)([\s\S]*?);/g)) {
    const body = chain[1];
    for (const s of body.matchAll(/\.select\(\s*"([^"]*)"/g)) {
      for (const c of s[1].split(",")) if (c.trim()) out.push(c.trim());
    }
    for (const f of body.matchAll(/\.(?:eq|is|neq|gt|gte|lt|lte|in|order|not)\(\s*"([a-z_]+)"/g)) out.push(f[1]);
  }
  return out;
}

function sourceFiles(dir: string): string[] {
  const out: string[] = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "node_modules" || e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...sourceFiles(p));
    else if (/\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name)) out.push(p);
  }
  return out;
}

describe("action_sends column contract (#8803)", () => {
  const declared = declaredColumns();

  it("the DDL parse finds the table's known columns (instrument check)", () => {
    for (const c of ["id", "user_id", "message_id", "clicked_at", "failure_reason", "acknowledged_at", "undone_at"]) {
      expect(declared.has(c), c).toBe(true);
    }
    expect(declared.has("created_at")).toBe(false);
  });

  it("the reference scan flags a column the table does not have (positive control)", () => {
    const refs = referencedColumns('sb.from("action_sends").select("created_at").eq("id", x).single();');
    expect(refs).toEqual(["created_at", "id"]);
  });

  it("every column referenced on action_sends in app/, server/ and lib/ is declared", () => {
    const refs: { file: string; col: string }[] = [];
    for (const dir of ["app", "server", "lib"]) {
      for (const file of sourceFiles(join(APP, dir))) {
        for (const col of referencedColumns(readFileSync(file, "utf8"))) {
          refs.push({ file: relative(APP, file), col });
        }
      }
    }
    // Non-vacuity: the table is read and written from several routes.
    expect(refs.length).toBeGreaterThanOrEqual(30);
    const unknown = refs.filter((r) => r.col !== "*" && !declared.has(r.col));
    expect(unknown, "columns named on action_sends that no migration declares").toEqual([]);
  });
});

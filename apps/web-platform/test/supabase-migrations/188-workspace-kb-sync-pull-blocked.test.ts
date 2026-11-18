import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { stripSqlComments, collapseSql } from "../helpers/sql-lex";

// Migration-shape test for 188_workspace_kb_sync_pull_blocked.sql (#12714, rulings D42, D45(c), RC-I).
//
// Offline text lint: nothing in CI applies or reverts 188 here (the tenant-integration job applies it to dev; never this
// test). The live catalog proof is supabase/verify/188_workspace_kb_sync_pull_blocked.sql, run by hand like verify/187.
//
// Why 188 exists: 187 was applied to the shared dev project by CI before the review added the third column, so 187 is
// frozen (its test pins the applied blob) and the third column, the three-column RPC, the lock timeout and the
// LAWFUL_BASIS / anon-barrier header land here. RETURNS TABLE cannot change shape under CREATE OR REPLACE (42P13), so the
// RPC is DROP FUNCTION IF EXISTS, then CREATE, with 187's definer, search_path, member check and grants re-issued.

const MIG = path.join(__dirname, "../../supabase/migrations");
const UP = path.join(MIG, "188_workspace_kb_sync_pull_blocked.sql");
const DOWN = path.join(MIG, "188_workspace_kb_sync_pull_blocked.down.sql");
const VERIFY = path.join(__dirname, "../../supabase/verify/188_workspace_kb_sync_pull_blocked.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const up = read(UP);
const down = read(DOWN);
const verify = read(VERIFY);
const upExec = collapseSql(stripSqlComments(up));
const downExec = collapseSql(stripSqlComments(down));
const verifyExec = collapseSql(stripSqlComments(verify));

const FN = "get_workspace_kb_sync_held";
const SIG = `public.${FN}(uuid)`;
const SIG_RE = SIG.replace(/[.()]/g, "\\$&");

/** Every statement position of `re` in `sql` (collapsed, comments stripped). */
const positions = (sql: string, re: RegExp): number[] => [...sql.matchAll(new RegExp(re, "gi"))].map((m) => m.index ?? -1);

/** The CREATE FUNCTION statement for the RPC in `sql`; "" when absent. */
const fnStmt = (sql: string): string =>
  sql.match(new RegExp(`CREATE (?:OR REPLACE )?FUNCTION public\\.${FN}\\([\\s\\S]*?\\$\\$[\\s\\S]*?\\$\\$;`, "i"))?.[0] ?? "";

/** The definer / path / volatility / member-check shape both the up and the down must recreate. */
function expectHardenedRpc(stmt: string): void {
  expect(stmt, `CREATE FUNCTION public.${FN}(...) missing`).not.toBe("");
  expect(stmt).toMatch(new RegExp(`public\\.${FN}\\(p_workspace_id uuid\\)`, "i"));
  expect(stmt).toMatch(/\bSECURITY DEFINER\b/i);
  expect(stmt).toMatch(/SET search_path\s*=\s*public,pg_temp/i);
  expect(stmt).toMatch(/\bSTABLE\b/i);
  expect(stmt).toMatch(/\bLANGUAGE sql\b/i);
  // Member check keyed on the caller's identity, never a caller-supplied user id.
  expect(stmt).toMatch(/public\.is_workspace_member\(p_workspace_id,auth\.uid\(\)\)/i);
  expect(stmt).toMatch(/FROM public\.workspaces w WHERE w\.id\s*=\s*p_workspace_id/i);
  expect(stmt).not.toMatch(/repo_url|github_installation_id|repo_error/i);
}

/** A DROP+CREATE resets the ACL: the file must REVOKE from every role and GRANT to authenticated alone, after the CREATE. */
function expectGrantsAfterCreate(sql: string): void {
  const create = sql.search(new RegExp(`CREATE FUNCTION public\\.${FN}\\(`, "i"));
  const revoke = sql.search(new RegExp(`REVOKE ALL ON FUNCTION ${SIG_RE}\\s*FROM PUBLIC,anon,authenticated,service_role;`, "i"));
  const grants = [...sql.matchAll(new RegExp(`GRANT EXECUTE ON FUNCTION ${SIG_RE}\\s*TO ([^;]+);`, "gi"))];
  expect(create).toBeGreaterThanOrEqual(0);
  expect(revoke, "REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role after the CREATE").toBeGreaterThan(create);
  expect(grants.map((g) => g[1].trim())).toEqual(["authenticated"]);
  expect(grants[0].index ?? -1).toBeGreaterThan(revoke);
}

describe("migration 188_workspace_kb_sync_pull_blocked (D42)", () => {
  it("the up, down and verify files exist", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });

  it("adds kb_sync_pull_blocked as nullable text with the named closed-value check, no DEFAULT or NOT NULL", () => {
    const m = upExec.match(
      /ALTER TABLE public\.workspaces ADD COLUMN IF NOT EXISTS kb_sync_pull_blocked text CONSTRAINT workspaces_kb_sync_pull_blocked_values CHECK\(kb_sync_pull_blocked IN\('merge_conflict_precheck','untracked_collision'\)\)\s*;/i,
    );
    expect(m, upExec.slice(0, 900)).not.toBeNull();
    expect(m?.[0]).not.toMatch(/\bDEFAULT\b|\bNOT NULL\b/i);
  });

  it("adds exactly one column and touches no 187 column but its comment", () => {
    expect(positions(upExec, /\bADD COLUMN\b/)).toHaveLength(1);
    expect(upExec).not.toMatch(/\b(?:ALTER|DROP) COLUMN\b/i);
  });

  it("sets a 5 s lock_timeout before the first ALTER TABLE, in the up and the down (RC-I)", () => {
    for (const [name, sql] of [["up", upExec], ["down", downExec]] as const) {
      const lock = sql.search(/SET LOCAL lock_timeout\s*=\s*'5s'\s*;/i);
      const firstAlter = sql.search(/\bALTER TABLE\b/i);
      expect(lock, name).toBeGreaterThanOrEqual(0);
      expect(firstAlter, name).toBeGreaterThan(lock);
      // and before the DROP FUNCTION, which takes its own lock
      expect(sql.search(/\bDROP FUNCTION\b/i), name).toBeGreaterThan(lock);
    }
  });

  it("carries a LAWFUL_BASIS line covering 187's two columns and 188's, and states that RLS is the anon barrier (D45(c))", () => {
    const header = up.split("\n").filter((l) => l.startsWith("--")).join("\n");
    const lawful = header.match(/^-- LAWFUL_BASIS: \S[\s\S]*?(?=\n--\n|\n-- [A-Z][a-z]+\.)/m)?.[0] ?? "";
    expect(lawful, "a LAWFUL_BASIS paragraph").not.toBe("");
    for (const col of ["kb_sync_held_files", "kb_sync_held_checked_at", "kb_sync_pull_blocked"]) expect(lawful, col).toContain(col);
    expect(header).toMatch(/\banon\b[^\n]*\bRLS\b|\bRLS\b[^\n]*\banon\b/i);
  });

  it("comments the new column (workspace scope, display-only)", () => {
    const c = up.match(/COMMENT ON COLUMN public\.workspaces\.kb_sync_pull_blocked IS[\s\S]*?';/i)?.[0] ?? "";
    expect(c).not.toBe("");
    expect(c).toMatch(/display-only/i);
    expect(c).toMatch(/workspace/i);
  });

  it("carries no GRANT or REVOKE on workspaces (174's column-split SELECT keeps the column from authenticated)", () => {
    expect(upExec).not.toMatch(/\bGRANT\b[^;]*\bON\s+(TABLE\s+)?public\.("?)workspaces\2\b/i);
    expect(upExec).not.toMatch(/\bREVOKE\b[^;]*\bON\s+(TABLE\s+)?public\.("?)workspaces\2\b/i);
    expect(downExec).not.toMatch(/\bGRANT\b[^;]*\bON\s+(TABLE\s+)?public\.("?)workspaces\2\b/i);
  });

  it("drops the two-column RPC first (RETURNS TABLE cannot change shape under CREATE OR REPLACE), then creates the three-column one", () => {
    const drop = upExec.search(new RegExp(`DROP FUNCTION IF EXISTS ${SIG_RE};`, "i"));
    const create = upExec.search(new RegExp(`CREATE FUNCTION public\\.${FN}\\(`, "i"));
    expect(drop).toBeGreaterThanOrEqual(0);
    expect(create).toBeGreaterThan(drop);
    expect(upExec).not.toMatch(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${FN}\\b`, "i"));
    const stmt = fnStmt(upExec);
    expectHardenedRpc(stmt);
    expect(stmt).toMatch(
      /RETURNS TABLE\(kb_sync_held_files integer,kb_sync_held_checked_at timestamptz,kb_sync_pull_blocked text\)/i,
    );
    expect(stmt).toMatch(/SELECT w\.kb_sync_held_files,w\.kb_sync_held_checked_at,w\.kb_sync_pull_blocked FROM/i);
  });

  it("re-issues the RPC's grants after the CREATE: revoked from every role, EXECUTE to authenticated only", () => {
    expectGrantsAfterCreate(upExec);
  });

  it("is idempotent on re-apply: the column add is IF NOT EXISTS, the RPC is DROP IF EXISTS then CREATE, no separate ADD CONSTRAINT", () => {
    expect(upExec).not.toMatch(/\bADD COLUMN\b(?! IF NOT EXISTS)/i);
    expect(upExec).not.toMatch(/\bADD CONSTRAINT\b/i);
    expect(upExec).not.toMatch(/\bDROP FUNCTION\b(?! IF EXISTS)/i);
    // every CREATE FUNCTION is preceded by a DROP FUNCTION IF EXISTS of the same signature
    const drops = positions(upExec, new RegExp(`DROP FUNCTION IF EXISTS ${SIG_RE};`));
    const creates = positions(upExec, new RegExp(`CREATE FUNCTION public\\.${FN}\\(`));
    expect(creates).toHaveLength(1);
    expect(drops.some((d) => d < creates[0])).toBe(true);
  });

  it("down then up: the down restores 187's two-column RPC with the same hardening and grants, then drops the column", () => {
    expect(downExec).not.toMatch(/\bDROP (COLUMN|FUNCTION)\b(?! IF EXISTS)/i);
    const drop = downExec.search(new RegExp(`DROP FUNCTION IF EXISTS ${SIG_RE};`, "i"));
    const create = downExec.search(new RegExp(`CREATE FUNCTION public\\.${FN}\\(`, "i"));
    const dropCol = downExec.search(/DROP COLUMN IF EXISTS kb_sync_pull_blocked\s*;/i);
    expect(drop).toBeGreaterThanOrEqual(0);
    expect(create).toBeGreaterThan(drop);
    // the RPC that names the column is gone before the column is
    expect(dropCol).toBeGreaterThan(drop);
    const stmt = fnStmt(downExec);
    expectHardenedRpc(stmt);
    expect(stmt).toMatch(/RETURNS TABLE\(kb_sync_held_files integer,kb_sync_held_checked_at timestamptz\)/i);
    expect(stmt).not.toMatch(/kb_sync_pull_blocked/i);
    expectGrantsAfterCreate(downExec);
    // 187's columns survive the down (they belong to 187's own down)
    expect(downExec).not.toMatch(/DROP COLUMN IF EXISTS kb_sync_held_(files|checked_at)\b/i);
    const header = down.split("\n").filter((l) => l.startsWith("--")).join("\n");
    expect(header).toMatch(/revert the code first/i);
  });

  it("uses no CONCURRENTLY (each migration file runs in one transaction)", () => {
    expect(upExec).not.toMatch(/\bCONCURRENTLY\b/i);
    expect(downExec).not.toMatch(/\bCONCURRENTLY\b/i);
  });

  it("verify/188 checks the column privilege, the named check, the three-column RPC and its re-issued ACL", () => {
    expect(verifyExec).toMatch(/has_column_privilege\('authenticated','public\.workspaces','kb_sync_pull_blocked','SELECT'\)/i);
    expect(verifyExec).toMatch(/conname\s*=\s*'workspaces_kb_sync_pull_blocked_values'/i);
    expect(verifyExec).toMatch(/proargnames\s*@>\s*ARRAY\['kb_sync_held_files','kb_sync_held_checked_at','kb_sync_pull_blocked'\]/i);
    expect(verifyExec).toMatch(/prosecdef/i);
    expect(verifyExec).toMatch(/search_path=public, pg_temp/i);
    for (const role of ["anon", "public", "authenticated"]) {
      expect(verifyExec, role).toMatch(new RegExp(`has_function_privilege\\('${role}','${SIG_RE}','EXECUTE'\\)`, "i"));
    }
  });
});

import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { stripSqlComments, collapseSql } from "../helpers/sql-lex";

// Migration-shape test for 187_workspace_kb_sync_held_files.sql (#12714, rulings W2 and D29(1)/(3)/(10), AC21).
//
// Offline text lint: nothing in CI applies or reverts 187. The live catalog proof is
// supabase/verify/187_workspace_kb_sync_held_files.sql, run by hand like verify/186.
//
// What the grants do (D29(10)), stated here because the migration deliberately carries NO grant on `workspaces`:
//   - `authenticated` SELECT on `workspaces` is column-split (migration 174 re-issues the column list), so a new
//     column is NOT readable by `authenticated` unless a later grant names it. 187 names none.
//   - the table-level INSERT/UPDATE that 174 grants `authenticated` remains; RLS (no UPDATE policy on `workspaces`,
//     053) is the barrier for writes, exactly as for every other `workspaces` column.
//   - the cc agent line reads the two columns through the member-checked SECURITY DEFINER RPC; Settings reads them
//     through the service client.

const MIG = path.join(__dirname, "../../supabase/migrations");
const UP = path.join(MIG, "187_workspace_kb_sync_held_files.sql");
const DOWN = path.join(MIG, "187_workspace_kb_sync_held_files.down.sql");
const VERIFY = path.join(__dirname, "../../supabase/verify/187_workspace_kb_sync_held_files.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const up = read(UP);
const down = read(DOWN);
const verify = read(VERIFY);
const upExec = collapseSql(stripSqlComments(up));
const downExec = collapseSql(stripSqlComments(down));
const verifyExec = collapseSql(stripSqlComments(verify));

const FN = "get_workspace_kb_sync_held";
const SIG = `public.${FN}(uuid)`;
const COLS = ["kb_sync_held_files", "kb_sync_held_checked_at"] as const;

/** The CREATE FUNCTION statement for the RPC, comments stripped, whitespace collapsed; "" when absent. */
const fnStmt = (): string =>
  upExec.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${FN}\\([\\s\\S]*?\\$\\$[\\s\\S]*?\\$\\$;`, "i"))?.[0] ?? "";

describe("migration 187_workspace_kb_sync_held_files (AC21)", () => {
  it("the up, down and verify files exist", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });

  it("adds kb_sync_held_files as a nullable integer with the named 0..10000 range check", () => {
    const m = upExec.match(
      /ALTER TABLE public\.workspaces ADD COLUMN IF NOT EXISTS kb_sync_held_files integer CONSTRAINT workspaces_kb_sync_held_files_range CHECK\(kb_sync_held_files\s*>=\s*0 AND kb_sync_held_files\s*<=\s*10000\)\s*;/i,
    );
    expect(m, upExec.slice(0, 600)).not.toBeNull();
  });

  it("adds kb_sync_held_checked_at as a nullable timestamptz", () => {
    expect(upExec).toMatch(/ALTER TABLE public\.workspaces ADD COLUMN IF NOT EXISTS kb_sync_held_checked_at timestamptz\s*;/i);
  });

  it("neither column carries a DEFAULT or NOT NULL (null means unknown, nothing shown)", () => {
    for (const col of COLS) {
      const clause = upExec.match(new RegExp(`ADD COLUMN IF NOT EXISTS ${col}[^;]*;`, "i"))?.[0] ?? "";
      expect(clause, col).not.toBe("");
      expect(clause, col).not.toMatch(/\bDEFAULT\b/i);
      expect(clause, col).not.toMatch(/\bNOT NULL\b/i);
    }
  });

  it("comments each column (workspace scope, display-only)", () => {
    for (const col of COLS) {
      const c = up.match(new RegExp(`COMMENT ON COLUMN public\\.workspaces\\.${col} IS[\\s\\S]*?';`, "i"))?.[0] ?? "";
      expect(c, col).not.toBe("");
      expect(c, col).toMatch(/display-only/i);
      expect(c, col).toMatch(/workspace/i);
    }
  });

  it("carries no GRANT or REVOKE on workspaces (174's column-split SELECT keeps the columns from authenticated)", () => {
    expect(upExec).not.toMatch(/\bGRANT\b[^;]*\bON\s+(TABLE\s+)?public\.("?)workspaces\2\b/i);
    expect(upExec).not.toMatch(/\bREVOKE\b[^;]*\bON\s+(TABLE\s+)?public\.("?)workspaces\2\b/i);
  });

  it("defines the RPC as a member-checked SECURITY DEFINER read with search_path pinned to public, pg_temp", () => {
    const stmt = fnStmt();
    expect(stmt, "CREATE OR REPLACE FUNCTION public.get_workspace_kb_sync_held(...) missing").not.toBe("");
    expect(stmt).toMatch(new RegExp(`public\\.${FN}\\(p_workspace_id uuid\\)`, "i"));
    expect(stmt).toMatch(/RETURNS TABLE\(kb_sync_held_files integer,kb_sync_held_checked_at timestamptz\)/i);
    expect(stmt).toMatch(/\bSECURITY DEFINER\b/i);
    expect(stmt).toMatch(/SET search_path\s*=\s*public,pg_temp/i);
    expect(stmt).toMatch(/\bSTABLE\b/i);
    // Member check keyed on the caller's identity, never a caller-supplied user id.
    expect(stmt).toMatch(/public\.is_workspace_member\(p_workspace_id,auth\.uid\(\)\)/i);
    // Reads only the two held columns, keyed on the argument.
    expect(stmt).toMatch(/FROM public\.workspaces w WHERE w\.id\s*=\s*p_workspace_id/i);
    expect(stmt).not.toMatch(/repo_url|github_installation_id|repo_error/i);
  });

  it("revokes the RPC from PUBLIC, anon, authenticated and service_role, then grants EXECUTE to authenticated only", () => {
    expect(upExec).toMatch(
      new RegExp(`REVOKE ALL ON FUNCTION public\\.${FN}\\(uuid\\)\\s*FROM PUBLIC,anon,authenticated,service_role;`, "i"),
    );
    const grants = [...upExec.matchAll(new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${FN}\\(uuid\\)\\s*TO ([^;]+);`, "gi"))];
    expect(grants.map((g) => g[1].trim())).toEqual(["authenticated"]);
  });

  it("the down drops the RPC and both columns, and its header says to revert the code first", () => {
    expect(downExec).toMatch(new RegExp(`DROP FUNCTION IF EXISTS public\\.${FN}\\(uuid\\);`, "i"));
    for (const col of COLS) {
      expect(downExec).toMatch(new RegExp(`DROP COLUMN IF EXISTS ${col}\\b`, "i"));
    }
    const header = down.split("\n").filter((l) => l.startsWith("--")).join("\n");
    expect(header).toMatch(/revert the code first/i);
  });

  it("uses no CONCURRENTLY (each migration file runs in one transaction)", () => {
    expect(upExec).not.toMatch(/\bCONCURRENTLY\b/i);
    expect(downExec).not.toMatch(/\bCONCURRENTLY\b/i);
  });

  it("verify/187 checks authenticated has no SELECT on either column, and the RPC is definer with a pinned path", () => {
    for (const col of COLS) {
      expect(verifyExec).toMatch(
        new RegExp(`has_column_privilege\\('authenticated','public\\.workspaces','${col}','SELECT'\\)`, "i"),
      );
    }
    expect(verifyExec).toMatch(/prosecdef/i);
    expect(verifyExec).toMatch(/search_path=public, pg_temp/i);
    expect(verifyExec).toContain(SIG);
    // anon must never EXECUTE the RPC; authenticated must.
    expect(verifyExec).toMatch(new RegExp(`has_function_privilege\\('anon','${SIG.replace(/[.()]/g, "\\$&")}','EXECUTE'\\)`, "i"));
    expect(verifyExec).toMatch(
      new RegExp(`has_function_privilege\\('authenticated','${SIG.replace(/[.()]/g, "\\$&")}','EXECUTE'\\)`, "i"),
    );
  });
});

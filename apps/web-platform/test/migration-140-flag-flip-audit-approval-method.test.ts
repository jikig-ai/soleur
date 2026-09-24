import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration 140 (#8486, ADR-249): flag_flip_audit gains an enum-checked,
// nullable `approval_method` column, and the writer RPC gains a trailing
// `p_approval_method text DEFAULT NULL` so callers that still send seven keys
// keep working through PostgREST named arguments.
const MIGRATIONS = path.join(__dirname, "../supabase/migrations");
const sql = readFileSync(path.join(MIGRATIONS, "140_flag_flip_audit_approval_method.sql"), "utf-8");
const downSql = readFileSync(
  path.join(MIGRATIONS, "140_flag_flip_audit_approval_method.down.sql"),
  "utf-8",
);
const verifySql = readFileSync(
  path.join(__dirname, "../supabase/verify/140_flag_flip_audit_approval_method.sql"),
  "utf-8",
);

const SIG7 = "public.audit_flag_flip(text,text,text,text,bool,bool,text)";
const SIG8 = "public.audit_flag_flip(text,text,text,text,bool,bool,text,text)";

// Comment lines are prose, not SQL: every assertion below reads the code only,
// so a header that NAMES a statement can never satisfy the statement's check.
const code = (s: string) =>
  s
    .split("\n")
    .filter((l) => !/^\s*--/.test(l))
    .join("\n");
const upCode = code(sql);
const downCode = code(downSql);

describe("migration 140: flag_flip_audit.approval_method", () => {
  it("runs inside one transaction", () => {
    expect(upCode).toMatch(/^\s*BEGIN;/m);
    expect(upCode).toMatch(/^\s*COMMIT;/m);
  });

  it("adds a nullable approval_method column whose CHECK admits only NULL or 'tty-ack'", () => {
    expect(upCode).toMatch(
      /ALTER TABLE public\.flag_flip_audit\s+ADD COLUMN approval_method text\s+CHECK \(approval_method IS NULL OR approval_method IN \('tty-ack'\)\);/,
    );
    // No DEFAULT and no NOT NULL: existing rows stay NULL and no table rewrite happens.
    const addCol = upCode.slice(upCode.indexOf("ADD COLUMN approval_method"));
    expect(addCol.slice(0, addCol.indexOf(";"))).not.toMatch(/DEFAULT|NOT NULL/);
  });

  it("drops the 7-arg writer BEFORE creating the 8-arg one, and never uses CREATE OR REPLACE", () => {
    const drop7 = upCode.indexOf(`DROP FUNCTION IF EXISTS ${SIG7};`);
    const create8 = upCode.indexOf("CREATE FUNCTION public.audit_flag_flip(");
    expect(drop7).toBeGreaterThan(-1);
    expect(create8).toBeGreaterThan(drop7);
    // CREATE OR REPLACE cannot change a signature; it would leave both overloads live.
    expect(upCode).not.toMatch(/CREATE OR REPLACE FUNCTION public\.audit_flag_flip/);
  });

  it("gives ONLY the last parameter a default, and that default is NULL", () => {
    const sigStart = upCode.indexOf("CREATE FUNCTION public.audit_flag_flip(");
    const sig = upCode.slice(sigStart, upCode.indexOf(")", sigStart) + 1);
    const defaults = sig.match(/DEFAULT/g) ?? [];
    expect(defaults).toHaveLength(1);
    expect(sig).toMatch(/p_approval_method text DEFAULT NULL\s*\)$/);
    expect(sig).toMatch(
      /p_flag_name text,\s*p_env text,\s*p_target text,\s*p_action text,\s*p_before_bool bool,\s*p_after_bool bool,\s*p_actor text,\s*p_approval_method text DEFAULT NULL/,
    );
  });

  it("the 8-arg writer is SECURITY DEFINER with search_path pinned to public, pg_temp", () => {
    const fn = upCode.slice(upCode.indexOf("CREATE FUNCTION public.audit_flag_flip("));
    expect(fn).toMatch(/SECURITY DEFINER SET search_path = public, pg_temp/);
  });

  it("writes approval_method and keeps the lower(p_actor) normalisation", () => {
    const fn = upCode.slice(upCode.indexOf("CREATE FUNCTION public.audit_flag_flip("));
    expect(fn).toMatch(/INSERT INTO public\.flag_flip_audit \([^)]*approval_method\)/);
    expect(fn).toMatch(/VALUES \([^)]*lower\(p_actor\), p_approval_method\)/);
  });

  it("REVOKEs the 8-arg writer from PUBLIC, anon, authenticated and GRANTs it to service_role only", () => {
    expect(upCode).toContain(`REVOKE ALL ON FUNCTION ${SIG8} FROM PUBLIC, anon, authenticated;`);
    expect(upCode).toContain(`GRANT EXECUTE ON FUNCTION ${SIG8} TO service_role;`);
    expect(upCode).not.toMatch(/GRANT EXECUTE ON FUNCTION public\.audit_flag_flip\([^)]*\) TO (anon|authenticated|PUBLIC)/);
  });

  it("does not touch the WORM triggers", () => {
    expect(upCode).not.toMatch(/flag_flip_audit_no_(update|delete)/);
  });
});

describe("migration 140 down: order is load-bearing", () => {
  it("drops the 8-arg function FIRST, then recreates the 7-arg one, then drops the column", () => {
    // Recreating the 7-arg function while the 8-arg DEFAULT NULL one exists makes
    // every 7-key call ambiguous ("function ... is not unique") and every flag
    // write exit 4.
    const drop8 = downCode.indexOf(`DROP FUNCTION IF EXISTS ${SIG8};`);
    const create7 = downCode.indexOf("CREATE FUNCTION public.audit_flag_flip(");
    const dropCol = downCode.indexOf("DROP COLUMN IF EXISTS approval_method");
    expect(drop8).toBeGreaterThan(-1);
    expect(create7).toBeGreaterThan(drop8);
    expect(dropCol).toBeGreaterThan(create7);
  });

  it("recreates the 7-arg writer with its SECURITY DEFINER pin and REVOKE/GRANT", () => {
    expect(downCode).toMatch(/SECURITY DEFINER SET search_path = public, pg_temp/);
    expect(downCode).toContain(`REVOKE ALL ON FUNCTION ${SIG7} FROM PUBLIC, anon, authenticated;`);
    expect(downCode).toContain(`GRANT EXECUTE ON FUNCTION ${SIG7} TO service_role;`);
    expect(downCode).not.toMatch(/DEFAULT/);
  });

  it("states the rollback order and the data loss in its header", () => {
    expect(downSql).toMatch(/audit-flag-flip\.sh/);
    expect(downSql).toMatch(/BEFORE this down migration/i);
    expect(downSql).toMatch(/destroys every recorded approval_method value/i);
  });
});

describe("verify/140 sentinel", () => {
  it("checks the live column, the CHECK, and the grants on the exact 8-arg signature", () => {
    expect(verifySql).toContain("approval_method");
    expect(verifySql).toContain("'public.audit_flag_flip(text,text,text,text,bool,bool,text,text)'");
    expect(verifySql).toMatch(/has_function_privilege\('anon'/);
    expect(verifySql).toMatch(/has_function_privilege\('authenticated'/);
    expect(verifySql).toMatch(/has_function_privilege\('service_role'/);
    // The 7-arg overload must be gone, or 7-key calls become ambiguous.
    expect(verifySql).toMatch(/to_regprocedure\('public\.audit_flag_flip\(text,text,text,text,bool,bool,text\)'\)/);
  });
});

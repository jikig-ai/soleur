import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const MIGRATION_PATH = path.join(
  __dirname,
  "../supabase/migrations/071_flag_flip_audit.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../supabase/migrations/071_flag_flip_audit.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf-8");
const downSql = readFileSync(DOWN_PATH, "utf-8");

describe("migration 071: flag_flip_audit WORM table", () => {
  it("creates flag_flip_audit table with RLS enabled", () => {
    expect(sql).toContain("CREATE TABLE public.flag_flip_audit");
    expect(sql).toContain("ENABLE ROW LEVEL SECURITY");
  });

  it("has zero RLS policies (service-role only via SECURITY DEFINER RPC)", () => {
    expect(sql).not.toMatch(/CREATE POLICY/);
  });

  it("has two separate WORM trigger functions (not a single combined)", () => {
    expect(sql).toContain("CREATE FUNCTION public.flag_flip_audit_no_update()");
    expect(sql).toContain("CREATE FUNCTION public.flag_flip_audit_no_delete()");
  });

  it("no_update trigger unconditionally raises (no TG_OP check)", () => {
    const noUpdateFn = sql.slice(
      sql.indexOf("CREATE FUNCTION public.flag_flip_audit_no_update()"),
      sql.indexOf("REVOKE ALL ON FUNCTION public.flag_flip_audit_no_update()"),
    );
    expect(noUpdateFn).toContain("RAISE EXCEPTION");
    expect(noUpdateFn).not.toContain("TG_OP");
  });

  it("no_delete trigger has row-state bypass for expired rows", () => {
    const noDeleteFn = sql.slice(
      sql.indexOf("CREATE FUNCTION public.flag_flip_audit_no_delete()"),
      sql.indexOf("REVOKE ALL ON FUNCTION public.flag_flip_audit_no_delete()"),
    );
    expect(noDeleteFn).toContain("OLD.retention_until");
    expect(noDeleteFn).toContain("< now()");
    expect(noDeleteFn).toContain("RETURN OLD");
  });

  it("actor CHECK constraint enforces lowercase email pattern", () => {
    expect(sql).toMatch(
      /actor text NOT NULL CHECK \(actor ~ '\^\[a-z0-9\._\+\-\]\+@\[a-z0-9\.\-\]\+\\\.\[a-z\]\{2,\}\$'\)/,
    );
  });

  it("writer RPC is SECURITY DEFINER with search_path pinned", () => {
    expect(sql).toContain("CREATE FUNCTION public.audit_flag_flip(");
    expect(sql).toContain("SECURITY DEFINER SET search_path = public, pg_temp");
  });

  it("writer RPC normalizes actor via lower()", () => {
    expect(sql).toContain("lower(p_actor)");
  });

  it("REVOKEs execute from PUBLIC, anon, authenticated on writer RPC", () => {
    expect(sql).toContain(
      "REVOKE ALL ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text) FROM PUBLIC, anon, authenticated",
    );
  });

  it("GRANTs execute to service_role only on writer RPC", () => {
    expect(sql).toContain(
      "GRANT EXECUTE ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text) TO service_role",
    );
  });

  it("trigger functions have SECURITY INVOKER (not DEFINER)", () => {
    const noUpdateFn = sql.slice(
      sql.indexOf("CREATE FUNCTION public.flag_flip_audit_no_update()"),
      sql.indexOf("CREATE FUNCTION public.flag_flip_audit_no_delete()"),
    );
    expect(noUpdateFn).toContain("SECURITY INVOKER");
    expect(noUpdateFn).not.toContain("SECURITY DEFINER");
  });

  it("two BEFORE triggers are created (not AFTER)", () => {
    expect(sql).toContain("BEFORE UPDATE ON public.flag_flip_audit");
    expect(sql).toContain("BEFORE DELETE ON public.flag_flip_audit");
  });

  it("env column has CHECK constraint with valid values", () => {
    expect(sql).toContain("env text NOT NULL CHECK (env IN ('dev','prd'))");
  });

  it("action column has CHECK constraint with valid values", () => {
    expect(sql).toContain(
      "action text NOT NULL CHECK (action IN ('on','off','create','archive'))",
    );
  });

  it("down migration drops in correct dependency order", () => {
    const triggerDrop = downSql.indexOf("DROP TRIGGER");
    const functionDrop = downSql.indexOf("DROP FUNCTION");
    const tableDrop = downSql.indexOf("DROP TABLE");
    expect(triggerDrop).toBeLessThan(functionDrop);
    expect(functionDrop).toBeLessThan(tableDrop);
  });

  it("references LIA document", () => {
    expect(sql).toContain("legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md");
  });
});

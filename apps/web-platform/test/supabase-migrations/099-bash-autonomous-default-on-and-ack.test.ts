import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration 099 — Concierge Autonomous mode (bash_autonomous) DEFAULT flip to
// `true` for NEW workspaces + per-workspace first-run consent ack column and
// its member-read / owner-write RPCs (verbatim structural mirror of 097).
//
// SHARP EDGE (GDPR): the default flip is FORWARD-ONLY. The migration MUST NOT
// contain any `UPDATE ... bash_autonomous` statement — silently enabling
// auto-execution on a workspace whose owner never consented is the violation
// this plan exists to avoid. Existing `false` rows MUST stay `false`.

const MIGRATIONS_DIR = path.join(__dirname, "../../supabase/migrations");
const VERIFY_DIR = path.join(__dirname, "../../supabase/verify");

const sql = readFileSync(
  path.join(MIGRATIONS_DIR, "099_bash_autonomous_default_on_and_ack.sql"),
  "utf-8",
);
const downSql = readFileSync(
  path.join(MIGRATIONS_DIR, "099_bash_autonomous_default_on_and_ack.down.sql"),
  "utf-8",
);
const verifySql = readFileSync(
  path.join(VERIFY_DIR, "099_bash_autonomous_default_on_and_ack.sql"),
  "utf-8",
);

describe("migration 099: bash_autonomous default ON + ack RPCs", () => {
  it("flips the bash_autonomous column DEFAULT to true (forward-only)", () => {
    expect(sql).toMatch(
      /ALTER\s+TABLE\s+public\.workspaces\s+ALTER\s+COLUMN\s+bash_autonomous\s+SET\s+DEFAULT\s+true/i,
    );
  });

  it("contains ZERO `UPDATE ... bash_autonomous` statements (no backfill — GDPR)", () => {
    // Any UPDATE that names bash_autonomous would silently enable existing
    // un-consented workspaces. Forbidden in the forward migration.
    expect(sql).not.toMatch(/UPDATE[\s\S]*?bash_autonomous/i);
  });

  it("does NOT re-CREATE OR REPLACE handle_new_user (insert relies on column default)", () => {
    expect(sql).not.toMatch(/handle_new_user/i);
  });

  it("adds the nullable autonomous_disclosure_ack_at column (no default)", () => {
    expect(sql).toMatch(
      /ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+autonomous_disclosure_ack_at\s+timestamptz/i,
    );
    // Nullable + no default: NULL = not yet acked = HOLD.
    expect(sql).not.toMatch(
      /autonomous_disclosure_ack_at\s+timestamptz[^;]*DEFAULT/i,
    );
  });

  it("defines get_workspace_autonomous_ack (member read) mirroring 097 shape", () => {
    expect(sql).toContain(
      "CREATE OR REPLACE FUNCTION public.get_workspace_autonomous_ack(p_workspace_id uuid)",
    );
    const fn = sql.slice(
      sql.indexOf("FUNCTION public.get_workspace_autonomous_ack"),
    );
    expect(fn).toContain("SECURITY DEFINER");
    expect(fn).toContain("SET search_path = public, pg_temp");
    expect(fn).toContain("is_workspace_member(p_workspace_id, auth.uid())");
    expect(fn).toContain("RETURN NULL");
  });

  it("defines set_workspace_autonomous_ack (owner-only write) mirroring 097 shape", () => {
    expect(sql).toContain(
      "FUNCTION public.set_workspace_autonomous_ack(",
    );
    const fn = sql.slice(
      sql.indexOf("FUNCTION public.set_workspace_autonomous_ack"),
    );
    expect(fn).toContain("SECURITY DEFINER");
    expect(fn).toContain("SET search_path = public, pg_temp");
    // Owner check via the R8 composite-key EXISTS pattern.
    expect(fn).toMatch(/FROM\s+public\.workspace_members/i);
    expect(fn).toContain("role         = 'owner'");
    expect(fn).toContain("RAISE EXCEPTION");
    // Idempotent: COALESCE existing ack or now().
    expect(fn).toMatch(/COALESCE\(autonomous_disclosure_ack_at,\s*now\(\)\)/i);
  });

  it("REVOKEs + GRANTs both ack RPCs exactly as 097 (authenticated only)", () => {
    expect(sql).toContain(
      "REVOKE ALL ON FUNCTION public.get_workspace_autonomous_ack(uuid)\n  FROM PUBLIC, anon, authenticated, service_role;",
    );
    expect(sql).toContain(
      "GRANT EXECUTE ON FUNCTION public.get_workspace_autonomous_ack(uuid)\n  TO authenticated;",
    );
    expect(sql).toMatch(
      /REVOKE ALL ON FUNCTION public\.set_workspace_autonomous_ack\([^)]*\)\s*\n\s*FROM PUBLIC, anon, authenticated, service_role;/,
    );
    expect(sql).toMatch(
      /GRANT EXECUTE ON FUNCTION public\.set_workspace_autonomous_ack\([^)]*\)\s*\n\s*TO authenticated;/,
    );
  });

  it("down migration drops both RPCs, drops the ack column, and resets DEFAULT false", () => {
    expect(downSql).toContain(
      "DROP FUNCTION IF EXISTS public.set_workspace_autonomous_ack",
    );
    expect(downSql).toContain(
      "DROP FUNCTION IF EXISTS public.get_workspace_autonomous_ack",
    );
    expect(downSql).toMatch(
      /DROP\s+COLUMN\s+IF\s+EXISTS\s+autonomous_disclosure_ack_at/i,
    );
    expect(downSql).toMatch(
      /ALTER\s+COLUMN\s+bash_autonomous\s+SET\s+DEFAULT\s+false/i,
    );
  });

  it("verify SQL asserts live GRANT/REVOKE state for both ack RPCs", () => {
    expect(verifySql).toContain("get_workspace_autonomous_ack");
    expect(verifySql).toContain("set_workspace_autonomous_ack");
    expect(verifySql).toContain("has_function_privilege");
    expect(verifySql).toContain("'anon'");
    expect(verifySql).toContain("'authenticated'");
  });
});

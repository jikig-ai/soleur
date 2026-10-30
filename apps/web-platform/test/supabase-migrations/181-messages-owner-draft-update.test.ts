import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 181_messages_owner_draft_update.sql (#11569).
//
// File-parse test, deliberately thin: the policy semantics are owned by the real-DB
// test/server/messages-owner-draft-update.tenant-isolation.test.ts and by
// supabase/verify/181 (run against prd by verify-migrations). This file pins only what a text
// test alone can see: statement ORDER (a later REVOKE would strip the column GRANT, migration 178),
// the absence of a bare auth.uid() (only the InitPlan form), the exact two-column GRANT, the
// down file, the verify contract, and the verify/174 edit that keeps verify-migrations green.

const ROOT = path.resolve(__dirname, "../..");
const read = (rel: string) => readFileSync(path.join(ROOT, rel), "utf8");
const stripComments = (sql: string) =>
  sql.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");

const upExec = stripComments(read("supabase/migrations/181_messages_owner_draft_update.sql"));
const downExec = stripComments(read("supabase/migrations/181_messages_owner_draft_update.down.sql"));
const verifyExec = stripComments(read("supabase/verify/181_messages_owner_draft_update.sql"));
const verify174 = read("supabase/verify/174_api_data_grants_snapshot.sql");

describe("181_messages_owner_draft_update.sql", () => {
  it("anti-vacuity: the parser extracted the statements this file asserts on", () => {
    expect(upExec).toMatch(/CREATE POLICY messages_owner_draft_update/);
    expect(upExec).toMatch(/REVOKE UPDATE ON TABLE public\.messages/);
    expect(upExec).toMatch(/GRANT UPDATE \(/);
    expect(upExec.length).toBeGreaterThan(300);
  });

  it("creates exactly one PERMISSIVE UPDATE policy for authenticated, dropping any prior copy first", () => {
    expect(upExec.match(/CREATE POLICY/g)).toHaveLength(1);
    expect(upExec).toMatch(
      /CREATE POLICY messages_owner_draft_update ON public\.messages\s+AS PERMISSIVE FOR UPDATE TO authenticated/,
    );
    const drop = upExec.indexOf("DROP POLICY IF EXISTS messages_owner_draft_update");
    expect(drop).toBeGreaterThan(-1);
    expect(drop).toBeLessThan(upExec.indexOf("CREATE POLICY"));
  });

  it("uses only the InitPlan form of auth.uid() (a bare call is evaluated per row)", () => {
    const calls = upExec.match(/auth\.uid\(\)/g) ?? [];
    const wrapped = upExec.match(/\(SELECT auth\.uid\(\)\)/g) ?? [];
    expect(calls.length).toBeGreaterThan(0);
    expect(calls).toHaveLength(wrapped.length);
  });

  it("scopes rows: USING pins draft, WITH CHECK allows draft or archived only", () => {
    expect(upExec).toMatch(/USING \(user_id = \(SELECT auth\.uid\(\)\)\s+AND status = 'draft'/);
    expect(upExec).toMatch(/WITH CHECK \(user_id = \(SELECT auth\.uid\(\)\)\s+AND status IN \('draft', 'archived'\)/);
  });

  it("revokes the table-level UPDATE BEFORE granting the two columns (a later REVOKE would strip the grant)", () => {
    const revoke = upExec.indexOf("REVOKE UPDATE ON TABLE public.messages FROM PUBLIC, anon, authenticated");
    const grant = upExec.indexOf("GRANT UPDATE (status, draft_preview) ON TABLE public.messages TO authenticated");
    expect(revoke).toBeGreaterThan(-1);
    expect(grant).toBeGreaterThan(-1);
    expect(revoke).toBeLessThan(grant);
  });

  it("grants UPDATE on exactly status and draft_preview and nothing else", () => {
    const grants = upExec.match(/GRANT UPDATE \(([^)]*)\)/g) ?? [];
    expect(grants).toHaveLength(1);
    const cols = grants[0]!.replace(/^GRANT UPDATE \(/, "").replace(/\)$/, "").split(",").map((s) => s.trim());
    expect(cols).toEqual(["status", "draft_preview"]);
    expect(upExec).not.toMatch(/GRANT (ALL|INSERT|DELETE|TRUNCATE)/);
  });

  it("the down file drops the policy, drops the column grants, then restores the table-level UPDATE", () => {
    expect(downExec).toMatch(/DROP POLICY IF EXISTS messages_owner_draft_update ON public\.messages/);
    const revoke = downExec.indexOf("REVOKE UPDATE (status, draft_preview)");
    const grant = downExec.indexOf("GRANT UPDATE ON TABLE public.messages TO anon, authenticated");
    expect(revoke).toBeGreaterThan(-1);
    expect(grant).toBeGreaterThan(revoke);
  });

  it("verify/181 carries the check_name/bad contract with the policy, grant and PUBLIC-ACL rows", () => {
    expect(verifyExec).toMatch(/AS check_name/);
    expect(verifyExec).toMatch(/\bbad\b/);
    for (const name of [
      "messages_policy_single_permissive_update",
      "messages_policy_using_author_member_draft",
      "messages_policy_with_check_author_member_draft_archived",
      "messages_jti_policy_still_restrictive_all",
      "messages_authenticated_update_columns_exact",
      "messages_no_uncovered_update_col_grants",
      "messages_public_no_update_acl",
    ]) {
      expect(verifyExec, name).toContain(`'${name}'`);
    }
    // The deparsed literal, not a bare auth.uid() (tautological: is_workspace_member(..., auth.uid()) contains it).
    expect(verifyExec).toContain("user_id = ( SELECT auth.uid()");
  });

  it("verify/174 no longer asserts a table-level UPDATE on messages for anon or authenticated", () => {
    for (const role of ["anon", "authenticated"]) {
      const line = verify174.split("\n").find((l) => l.startsWith(`SELECT 'grants_messages_${role}'`));
      expect(line, `grants_messages_${role} row`).toBeDefined();
      expect(line).not.toContain("('UPDATE')");
      expect(line).toContain("('TRUNCATE')");
    }
    // service_role keeps its full set.
    const svc = verify174.split("\n").find((l) => l.startsWith("SELECT 'grants_messages_service_role'"));
    expect(svc).toContain("('UPDATE')");
  });
});

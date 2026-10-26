import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 177_egress_audit_summary_rpc.sql (#9545, PR2).
// Offline text lint. Everything that needs an auth boundary or real rows (cross-tenant, pending and
// removed members, grants as seen by the engine, aggregation, window edges) runs in the live-database
// harness: test/rls-fuzz/egress-audit-rollup.integration.test.ts. This file pins the SHAPE only:
//   1. one SECURITY DEFINER, STABLE function with search_path pinned incl. pg_temp;
//   2. the membership check is the FIRST statement after BEGIN (before any argument handling), raises
//      42501 with a constant message, and a bad p_decision raises 22023 only after it;
//   3. every aggregate over the rollup carries the tenant predicate;
//   4. grants: REVOKE from PUBLIC/anon/authenticated/service_role then GRANT to authenticated only;
//   5. no table grant, no policy, no statement_timeout clause (proved ineffective), no dynamic SQL;
//   6. the .down.sql drops exactly that function and nothing else.

const DIR = path.join(__dirname, "../../supabase/migrations");
const UP = path.join(DIR, "177_egress_audit_summary_rpc.sql");
const DOWN = path.join(DIR, "177_egress_audit_summary_rpc.down.sql");
const VERIFY = path.join(__dirname, "../../supabase/verify/177_egress_audit_summary_rpc.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const up = read(UP);
const down = read(DOWN);
const verify = read(VERIFY);
const exec = (s: string): string => s.replace(/--[^\n]*/g, "");
const upExec = exec(up);
const downExec = exec(down);

const SIG = "public.get_egress_audit_summary(uuid, integer, text)";

describe("177_egress_audit_summary_rpc.sql (shape)", () => {
  it("all three files exist", () => {
    expect(up).not.toBe("");
    expect(down).not.toBe("");
    expect(verify).not.toBe("");
  });

  it("defines exactly one function, SECURITY DEFINER + STABLE, with search_path pinned incl. pg_temp", () => {
    expect(upExec.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION/gi)).toHaveLength(1);
    const header = upExec.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_egress_audit_summary[\s\S]*?AS\s+\$\$/i)?.[0] ?? "";
    expect(header).toMatch(/SECURITY\s+DEFINER/i);
    expect(header).toMatch(/\bSTABLE\b/i);
    expect(header).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
  });

  it("the membership check is the first statement after BEGIN and raises 42501 with a constant message", () => {
    const body = upExec.match(/\$\$\s*DECLARE[\s\S]*?BEGIN([\s\S]*?)\$\$;/i)?.[1] ?? "";
    const firstStmt = body.trimStart();
    expect(firstStmt).toMatch(
      /^IF\s+auth\.uid\(\)\s+IS\s+NULL\s+OR\s+NOT\s+public\.is_workspace_member\(p_workspace_id,\s*auth\.uid\(\)\)\s+THEN/i,
    );
    const authz = firstStmt.match(/^IF[\s\S]*?END\s+IF;/i)?.[0] ?? "";
    expect(authz).toContain("'egress audit: workspace membership required'");
    expect(authz).toMatch(/ERRCODE\s*=\s*'42501'/);
    // constant message: no interpolation of workspace or user ids
    expect(authz).not.toMatch(/%|format\(|\|\|/);
  });

  it("the invalid-decision check (22023) comes after the authz check, not before", () => {
    const authzAt = upExec.indexOf("workspace membership required");
    const decisionAt = upExec.indexOf("invalid decision filter");
    expect(authzAt).toBeGreaterThan(-1);
    expect(decisionAt).toBeGreaterThan(authzAt);
    expect(upExec).toMatch(/ERRCODE\s*=\s*'22023'/);
  });

  it("every read of the rollup table carries the tenant predicate", () => {
    const reads = [...upExec.matchAll(/FROM\s+public\.workspace_egress_audit_rollup\s+(\w+)([\s\S]*?)(?=\)\s*;|\)\s*,|\bGROUP\s+BY\b|\bINTO\b|\)\s*\n)/gi)];
    expect(reads.length).toBeGreaterThanOrEqual(3);
    for (const m of reads) {
      expect(m[0]).toMatch(new RegExp(`${m[1]}\\.workspace_id\\s*=\\s*p_workspace_id`));
    }
  });

  it("window is fixed at 30 days and bounded above by now()", () => {
    expect(upExec).toMatch(/v_lo\s+timestamptz\s*:=\s*now\(\)\s*-\s*interval\s*'30 days'/);
    expect(upExec).toMatch(/last_seen\s*>=\s*v_lo/);
    expect(upExec).toMatch(/last_seen\s*<=\s*v_now/);
    expect(upExec).not.toMatch(/p_window/);
  });

  it("revokes from PUBLIC, anon, authenticated and service_role, then grants authenticated only", () => {
    expect(upExec).toMatch(
      new RegExp(`REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+${SIG.replace(/[().]/g, "\\$&")}\\s+FROM\\s+PUBLIC,\\s*anon,\\s*authenticated,\\s*service_role`, "i"),
    );
    const grants = [...upExec.matchAll(/GRANT\s+EXECUTE\s+ON\s+FUNCTION[\s\S]*?;/gi)].map((m) => m[0]);
    expect(grants).toHaveLength(1);
    expect(grants[0]).toMatch(/TO\s+authenticated\s*;/i);
    // inspect the grantee list only: the function's schema is also spelled `public`
    const grantees = grants[0].split(/\bTO\b/i)[1] ?? "";
    expect(grantees).not.toMatch(/anon|service_role|PUBLIC/i);
  });

  it("adds no table grant, no policy, no trigger and no statement_timeout clause", () => {
    expect(upExec).not.toMatch(/\bCREATE\s+POLICY\b/i);
    expect(upExec).not.toMatch(/\bGRANT\s+(SELECT|INSERT|UPDATE|DELETE|ALL)\b/i);
    expect(upExec).not.toMatch(/\bCREATE\s+(OR\s+REPLACE\s+)?TRIGGER\b/i);
    expect(upExec).not.toMatch(/statement_timeout/i);
    expect(upExec).not.toMatch(/\bEXECUTE\b\s+(format|')/i);
  });

  it("returns the typed contract: window, truncated, summary, rows, overflow; source_host is never selected", () => {
    for (const key of ["'window'", "'truncated'", "'summary'", "'rows'", "'overflow'", "'last_request_at'"]) {
      expect(upExec).toContain(key);
    }
    expect(upExec).toMatch(/COALESCE\(\(\s*SELECT\s+jsonb_agg/gi);
    expect(upExec).not.toMatch(/source_host/);
  });

  it(".down.sql drops only that function", () => {
    expect(downExec.match(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.get_egress_audit_summary\(uuid,\s*integer,\s*text\)\s*;/gi)).toHaveLength(1);
    expect(downExec).not.toMatch(/DROP\s+TABLE/i);
  });

  it("the verify sentinel asserts the live catalog facts (definer, stable, search_path, grantee set, table privilege, policies)", () => {
    for (const check of [
      "egress_summary_is_definer",
      "egress_summary_is_stable",
      "egress_summary_search_path_pinned",
      "egress_summary_anon_revoked",
      "egress_summary_service_role_revoked",
      "egress_summary_public_revoked",
      "egress_summary_authenticated_granted",
      "egress_summary_grantee_set_is_only_authenticated",
      "egress_rollup_authenticated_select_revoked",
      "egress_rollup_has_no_policy",
    ]) {
      expect(verify).toContain(check);
    }
  });
});

import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { PAGE_LIMIT, RPC_DENIAL_PREFIX } from "@/lib/egress-audit/summary";

// Migration-shape test for 177_egress_audit_summary_rpc.sql (#9545, PR2).
// Offline text lint. Everything that needs an auth boundary or real rows (cross-tenant, pending and
// removed members, grants as seen by the engine, aggregation, window edges) runs in the live-database
// harness: test/rls-fuzz/egress-audit-rollup.integration.test.ts. This file pins the SHAPE only:
//   1. one SECURITY DEFINER, STABLE function with search_path pinned incl. pg_temp;
//   2. the membership check is the FIRST statement after BEGIN (before any argument handling), raises
//      42501 with a constant message; the jti denylist check is the SECOND statement (42501, own
//      constant message); a bad p_decision raises 22023 and the p_limit = 0 probe runs only after both;
//      every denial message starts with RPC_DENIAL_PREFIX (the prefix the loader discriminates on);
//   2b. plan_cache_mode = force_custom_plan is pinned (no generic-plan flip after five calls), the
//      host rows are a top-N (no row_number, no count(*)), every sum is clamped to the JS-safe maximum,
//      and the probe's inner newest-bucket subquery applies the same last_seen window and tenant predicate;
//   2c. the p_limit clamp LEAST(GREATEST(COALESCE(p_limit, 200), 0), 500) and the signature default 200 are
//      pinned (the cost bound), with PAGE_LIMIT equal to that default, and both bucket_start lower bounds
//      (the w CTE and the probe's inner subquery) keep the 15-minute bucket slack;
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
const verifyExec = exec(verify);
const upExec = exec(up);
const downExec = exec(down);

const SIG = "public.get_egress_audit_summary(uuid, integer, text)";
const escapeRe = (t: string): string => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// The one place that pins the VALUE of the prefix, independent of the constant (every other test imports it).
const DENIAL_PREFIX_VALUE = "egress audit: ";

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

  it("pins plan_cache_mode = force_custom_plan in the function header (the generic plan walks the last_seen index across all workspaces)", () => {
    const header = upExec.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_egress_audit_summary[\s\S]*?AS\s+\$\$/i)?.[0] ?? "";
    expect(header).toMatch(/SET\s+plan_cache_mode\s*=\s*force_custom_plan\b/i);
  });

  it("RPC_DENIAL_PREFIX is exactly 'egress audit: ' (the single literal pin of the value)", () => {
    expect(RPC_DENIAL_PREFIX).toBe(DENIAL_PREFIX_VALUE);
  });

  it("the p_limit clamp is LEAST(GREATEST(COALESCE(p_limit, 200), 0), 500) and the signature default is 200", () => {
    expect(upExec).toMatch(/\bv_limit\s*:=\s*LEAST\(\s*GREATEST\(\s*COALESCE\(\s*p_limit\s*,\s*200\s*\)\s*,\s*0\s*\)\s*,\s*500\s*\)\s*;/i);
    expect(upExec).toMatch(/\bp_limit\s+integer\s+DEFAULT\s+200\b/i);
  });

  it("PAGE_LIMIT equals the migration's p_limit default and sits inside the 1..clamp range", () => {
    const def = Number(upExec.match(/\bp_limit\s+integer\s+DEFAULT\s+(\d+)\b/i)?.[1]);
    const max = Number(upExec.match(/GREATEST\([^)]*\)\s*,\s*0\s*\)\s*,\s*(\d+)\s*\)/i)?.[1]);
    expect(Number.isInteger(def)).toBe(true);
    expect(Number.isInteger(max)).toBe(true);
    expect(PAGE_LIMIT).toBe(def);
    expect(PAGE_LIMIT).toBeGreaterThanOrEqual(1);
    expect(PAGE_LIMIT).toBeLessThanOrEqual(max);
  });

  it("both bucket_start lower bounds keep the 15-minute slack: the w CTE and the probe's inner subquery", () => {
    const w = upExec.match(/WITH\s+w\s+AS\s*\(([\s\S]*?)\n\s*\),\s*\n\s*g\s+AS/i)?.[1] ?? "";
    expect(w).toMatch(/t\.bucket_start\s*>=\s*v_lo\s*-\s*interval\s*'15 minutes'/i);
    const inner = upExec.match(/t\.bucket_start\s*=\s*\(\s*SELECT\s+max\(b\.bucket_start\)([\s\S]*?)\);/i)?.[1] ?? "";
    expect(inner).toMatch(/b\.bucket_start\s*>=\s*v_lo\s*-\s*interval\s*'15 minutes'/i);
  });

  it("the membership check is the first statement after BEGIN and raises 42501 with a constant message", () => {
    const body = upExec.match(/\$\$\s*DECLARE[\s\S]*?BEGIN([\s\S]*?)\$\$;/i)?.[1] ?? "";
    const firstStmt = body.trimStart();
    expect(firstStmt).toMatch(
      /^IF\s+auth\.uid\(\)\s+IS\s+NULL\s+OR\s+NOT\s+public\.is_workspace_member\(p_workspace_id,\s*auth\.uid\(\)\)\s+THEN/i,
    );
    const authz = firstStmt.match(/^IF[\s\S]*?END\s+IF;/i)?.[0] ?? "";
    expect(authz).toContain(`'${RPC_DENIAL_PREFIX}workspace membership required'`);
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

  it("the jti denylist check is the second statement: membership -> jti -> 22023 -> the p_limit = 0 probe", () => {
    const body = upExec.match(/\$\$\s*DECLARE[\s\S]*?BEGIN([\s\S]*?)\$\$;/i)?.[1] ?? "";
    const afterAuthz = body.trimStart().replace(/^IF[\s\S]*?END\s+IF;\s*/i, "");
    expect(afterAuthz).toMatch(
      new RegExp(
        `^IF\\s+public\\.is_jti_denied_from_jwt\\(\\)\\s+THEN\\s+RAISE\\s+EXCEPTION\\s+'${escapeRe(RPC_DENIAL_PREFIX)}token denied'\\s+USING\\s+ERRCODE\\s*=\\s*'42501'\\s*;\\s*END\\s+IF;`,
        "i",
      ),
    );
    const authzAt = body.indexOf("workspace membership required");
    const jtiAt = body.indexOf("is_jti_denied_from_jwt()");
    const decisionAt = body.indexOf("invalid decision filter");
    const probeAt = body.search(/IF\s+v_limit\s*=\s*0\s+THEN/i);
    expect(authzAt).toBeGreaterThan(-1);
    expect(jtiAt).toBeGreaterThan(authzAt);
    expect(decisionAt).toBeGreaterThan(jtiAt);
    expect(probeAt).toBeGreaterThan(decisionAt);
    // the denylist is checked exactly once, as a statement (not inside a query)
    expect(body.match(/is_jti_denied_from_jwt\(\)/g)).toHaveLength(1);
  });

  it("every in-body message starts with RPC_DENIAL_PREFIX, the prefix the loader discriminates on", () => {
    const messages = [...upExec.matchAll(/RAISE\s+EXCEPTION\s+'([^']*)'/gi)].map((m) => m[1]);
    expect(messages).toEqual([
      `${RPC_DENIAL_PREFIX}workspace membership required`,
      `${RPC_DENIAL_PREFIX}token denied`,
      `${RPC_DENIAL_PREFIX}invalid decision filter`,
    ]);
    for (const m of messages) expect(m.startsWith(RPC_DENIAL_PREFIX)).toBe(true);
  });

  it("host rows are a top-N: LIMIT v_limit + 1 over the ordered groups, no row_number and no count(*)", () => {
    expect(upExec).not.toMatch(/row_number\s*\(/i);
    expect(upExec).not.toMatch(/count\s*\(\s*\*\s*\)/i);
    const r = upExec.match(/\br\s+AS\s*\(([\s\S]*?)\n\s*\),\s*\n\s*o\s+AS/i)?.[1] ?? "";
    expect(r).toMatch(/ORDER\s+BY\s+g\.last_seen\s+DESC,\s*g\.host,\s*g\.decision\s+LIMIT\s+v_limit\s*\+\s*1\b/i);
    // truncated = a row exists beyond p_limit; rows = the first v_limit of r
    expect(upExec).toMatch(/'truncated',\s*EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+r\s+ORDER\s+BY[^)]*OFFSET\s+v_limit/i);
    expect(upExec).toMatch(/FROM\s+r\s+ORDER\s+BY\s+r\.last_seen\s+DESC,\s*r\.host,\s*r\.decision\s+LIMIT\s+v_limit\s*\)\s*x/i);
  });

  it("the window CTE w keeps the default materialization (NOT MATERIALIZED measured 3-5x slower at 50k-250k rows)", () => {
    expect(upExec).toMatch(/WITH\s+w\s+AS\s*\(/i);
    expect(upExec).not.toMatch(/\bNOT\s+MATERIALIZED\b/i);
  });

  it("the summary is computed from the window rows (w), not from the grouped CTE", () => {
    const s = upExec.match(/\bs\s+AS\s*\(([\s\S]*?)\n\s*\),\s*\n\s*r\s+AS/i)?.[1] ?? "";
    expect(s).toMatch(/FROM\s+w\b/i);
    expect(s).not.toMatch(/FROM\s+g\b/i);
  });

  it("every sum is clamped to 9007199254740991 (JS MAX_SAFE_INTEGER): per-group, total and blocked", () => {
    const clamps = upExec.match(/least\(\s*(?:coalesce\()?\s*sum\([\s\S]*?9007199254740991\s*\)::bigint/gi) ?? [];
    expect(clamps).toHaveLength(3);
    // no unclamped bigint cast of a sum remains
    expect(upExec).not.toMatch(/sum\([^)]*\)\s*(?:FILTER\s*\([^)]*\)\s*)?::bigint/i);
  });

  it("the p_limit = 0 probe's inner newest-bucket subquery applies the same last_seen window and the tenant predicate", () => {
    const inner = upExec.match(/t\.bucket_start\s*=\s*\(\s*SELECT\s+max\(b\.bucket_start\)([\s\S]*?)\);/i)?.[1] ?? "";
    expect(inner).toMatch(/FROM\s+public\.workspace_egress_audit_rollup\s+b\b/i);
    expect(inner).toMatch(/b\.workspace_id\s*=\s*p_workspace_id/);
    expect(inner).toMatch(/b\.bucket_start\s*<=\s*v_now/);
    expect(inner).toMatch(/b\.last_seen\s*>=\s*v_lo/);
    expect(inner).toMatch(/b\.last_seen\s*<=\s*v_now/);
    // and the outer query keeps its own tenant predicate
    const outer = upExec.match(/SELECT\s+max\(t\.last_seen\)[\s\S]*?WHERE([\s\S]*?)AND\s+t\.bucket_start\s*=/i)?.[1] ?? "";
    expect(outer).toMatch(/t\.workspace_id\s*=\s*p_workspace_id/);
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
      new RegExp(`REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+${SIG.replace(/[\\().]/g, "\\$&")}\\s+FROM\\s+PUBLIC,\\s*anon,\\s*authenticated,\\s*service_role`, "i"),
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

  describe("the verify sentinel asserts the live catalog PREDICATES, not just the check names", () => {
    // One row per UNION ALL branch, comments stripped so a comment cannot satisfy an anchor.
    const rows = new Map<string, string>();
    for (const seg of verifyExec.split(/\bUNION\s+ALL\b/i)) {
      const name = seg.match(/SELECT\s+'([a-z_]+)'/i)?.[1];
      if (name) rows.set(name, seg.replace(/\s+/g, " "));
    }
    const FN = "'public\\.get_egress_audit_summary\\(uuid, integer, text\\)'";
    const jtiName = upExec.match(/\bpublic\.(is_jti_denied_from_jwt)\(\)/)?.[1] ?? "";
    // check name -> the predicate and its polarity (bad = 1 on drift)
    const predicates: Record<string, RegExp> = {
      egress_summary_is_definer: /CASE WHEN p\.prosecdef THEN 0 ELSE 1 END/,
      egress_summary_is_stable: /CASE WHEN p\.provolatile = 's' THEN 0 ELSE 1 END/,
      egress_summary_search_path_pinned: /p\.proconfig IS NOT NULL AND EXISTS \(SELECT 1 FROM unnest\(p\.proconfig\) c WHERE c LIKE 'search_path=%pg_temp%'\) THEN 0 ELSE 1/,
      egress_summary_plan_cache_mode_custom: /p\.proconfig IS NOT NULL AND EXISTS \(SELECT 1 FROM unnest\(p\.proconfig\) c WHERE c = 'plan_cache_mode=force_custom_plan'\) THEN 0 ELSE 1/,
      egress_summary_checks_jti_denylist: /CASE WHEN p\.prosrc LIKE '%is_jti_denied_from_jwt\(\)%' THEN 0 ELSE 1 END/,
      egress_summary_anon_revoked: /CASE WHEN has_function_privilege\('anon', .*'EXECUTE'\) THEN 1 ELSE 0 END/,
      egress_summary_service_role_revoked: /CASE WHEN has_function_privilege\('service_role', .*'EXECUTE'\) THEN 1 ELSE 0 END/,
      egress_summary_public_revoked: /a\.grantee = 0 AND a\.privilege_type = 'EXECUTE'\) THEN 1 ELSE 0 END/,
      egress_summary_authenticated_granted: /CASE WHEN has_function_privilege\('authenticated', .*'EXECUTE'\) THEN 0 ELSE 1 END/,
      egress_summary_grantee_set_is_only_authenticated: /a\.privilege_type = 'EXECUTE' AND a\.grantee NOT IN \(.*rolname = 'authenticated'\).*proowner.*\) = 0 THEN 0 ELSE 1 END/,
      egress_rollup_authenticated_select_revoked: /CASE WHEN has_table_privilege\('authenticated', 'public\.workspace_egress_audit_rollup', 'SELECT'\) THEN 1 ELSE 0 END/,
      egress_rollup_has_no_policy: /CASE WHEN EXISTS \(SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_egress_audit_rollup'\) THEN 1 ELSE 0 END/,
    };

    it("has exactly the twelve expected rows", () => {
      expect([...rows.keys()].sort()).toEqual(Object.keys(predicates).sort());
    });

    it.each(Object.entries(predicates))("%s has its predicate and polarity", (name, re) => {
      expect([name, re.test(rows.get(name) ?? "")]).toEqual([name, true]);
    });

    it.each(["egress_summary_is_definer", "egress_summary_is_stable", "egress_summary_search_path_pinned", "egress_summary_plan_cache_mode_custom", "egress_summary_checks_jti_denylist"])(
      "%s reads the function's own pg_proc row (the regprocedure of the signature)",
      (name) => {
        expect(rows.get(name) ?? "").toMatch(new RegExp(`p\\.oid = ${FN}::regprocedure`));
      },
    );

    it("the jti check names the very function the migration calls (a typo'd name would pass a bare-name check)", () => {
      expect(jtiName).toBe("is_jti_denied_from_jwt");
      expect(rows.get("egress_summary_checks_jti_denylist") ?? "").toContain(`LIKE '%${jtiName}()%'`);
    });
  });
});

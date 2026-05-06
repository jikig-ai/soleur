import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 037_audit_byok_use.sql.
//
// File-parse contract test (mirrors 036 precedent), pinning the SQL
// invariants required by PR-B §1.2:
//   1. audit_byok_use table + RLS-on + founder-readable SELECT policy
//      + WORM triggers on UPDATE/DELETE.
//   2. write_byok_audit SECURITY DEFINER RPC, service_role-only.
//   3. denied_jti table + RLS-on + zero policies (service-role-only via
//      is_jti_denied SECURITY DEFINER fn).
//   4. mint_rate_window table + RLS-on + zero policies.
//   5. precheck_jwt_mint SECURITY DEFINER RPC: atomic rate-limit
//      increment + jti generation + 60/hour ceiling enforcement.
//      Resolution A (#3363): Node holds SUPABASE_JWT_SECRET; this RPC
//      supplies non-secret claims (jti, exp, iat) and gates rate.
//   6. cq-pg-security-definer-search-path-pin-pg-temp: every
//      SECURITY DEFINER fn pins SET search_path = public, pg_temp
//      (in that order) and qualifies relations as public.<table>.
//   7. cq-supabase-migration-no-concurrently: NO CREATE INDEX
//      CONCURRENTLY (Supabase wraps each migration in a transaction).
//
// Plan: knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md §1.2/§1.3/§1.4

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/037_audit_byok_use.sql",
);

describe("migration 037_audit_byok_use", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");

  // Strip line-comments before pattern checks (mirrors 036 pattern).
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("audit_byok_use table", () => {
    it("creates the table with founder_id FK to public.users", () => {
      expect(executable).toMatch(
        /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.audit_byok_use[\s\S]*?founder_id\s+uuid\s+NOT\s+NULL\s+REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });

    it("includes unit_cost_cents column (data-integrity P2-1)", () => {
      // §3.5 SUM hot path references this column; missing column was
      // flagged in deepen-pass.
      expect(executable).toMatch(/unit_cost_cents\s+int\s+NOT\s+NULL/i);
    });

    it("enables RLS", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.audit_byok_use\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
    });

    it("declares founder-readable SELECT policy (data-integrity P1-3)", () => {
      // Usage dashboard needs a read path without service-role; WORM
      // is enforced by trigger, not by zero-policies.
      expect(executable).toMatch(
        /CREATE\s+POLICY\s+\w+\s+ON\s+public\.audit_byok_use[\s\S]*?FOR\s+SELECT[\s\S]*?USING\s*\(\s*auth\.uid\(\)\s*=\s*founder_id\s*\)/i,
      );
    });

    it("declares NO INSERT/UPDATE/DELETE policies (writes via SECURITY DEFINER only)", () => {
      // FOR INSERT / FOR UPDATE / FOR DELETE / FOR ALL must NOT appear
      // for audit_byok_use.
      const policyBlock = executable.match(
        /CREATE\s+POLICY\s+\w+\s+ON\s+public\.audit_byok_use[\s\S]*?(?=CREATE\s+|$)/gi,
      );
      expect(policyBlock, "expected at least one policy on audit_byok_use").not.toBeNull();
      // Across all policies on the table, none may be FOR INSERT/UPDATE/DELETE/ALL.
      for (const p of policyBlock || []) {
        expect(p).not.toMatch(/FOR\s+(INSERT|UPDATE|DELETE|ALL)/i);
      }
    });

    it("declares WORM triggers on UPDATE and DELETE (security P3-B)", () => {
      // Service-role can drop the trigger but the drop is a forensic
      // signal logged elsewhere; trigger is the load-bearing WORM.
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+\w+\s+BEFORE\s+UPDATE\s+ON\s+public\.audit_byok_use/i,
      );
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+\w+\s+BEFORE\s+DELETE\s+ON\s+public\.audit_byok_use/i,
      );
    });

    it("WORM trigger function pins search_path and is SECURITY DEFINER", () => {
      // cq-pg-security-definer-search-path-pin-pg-temp.
      const fnBlock = executable.match(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.audit_byok_use_no_mutate\s*\(\s*\)[\s\S]*?\$\$;/i,
      );
      expect(fnBlock, "expected audit_byok_use_no_mutate function").not.toBeNull();
      expect(fnBlock![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock![0]).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });

    it("declares the covering index on (founder_id, ts DESC) (data-integrity P2-2)", () => {
      // INCLUDE (token_count, unit_cost_cents) for index-only scans on
      // the §3.5 sliding-window SUM hot path.
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+\w+\s+ON\s+public\.audit_byok_use\s*\(\s*founder_id\s*,\s*ts\s+DESC\s*\)\s*INCLUDE\s*\(\s*token_count\s*,\s*unit_cost_cents\s*\)/i,
      );
    });

    it("does NOT use CREATE INDEX CONCURRENTLY (supabase wraps in tx)", () => {
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });

  describe("write_byok_audit RPC", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.write_byok_audit[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("function exists with the unit_cost_cents parameter (data-integrity P2-1)", () => {
      expect(fnBlock).not.toBe("");
      expect(fnBlock).toMatch(/p_unit_cost_cents\s+int/i);
    });

    it("is SECURITY DEFINER with search_path pinned to public, pg_temp", () => {
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });

    it("body INSERTs into public.audit_byok_use (qualified relation)", () => {
      expect(fnBlock).toMatch(/INSERT\s+INTO\s+public\.audit_byok_use/i);
    });

    it("revokes default PUBLIC execute and grants service_role only", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.write_byok_audit\([^)]*\)\s+FROM\s+PUBLIC/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.write_byok_audit\([^)]*\)\s+TO\s+service_role/i,
      );
      // Belt-and-suspenders: must NOT grant to authenticated.
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.write_byok_audit\([^)]*\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("denied_jti table + is_jti_denied RPC", () => {
    it("creates denied_jti table with founder_id FK and PK on jti", () => {
      expect(executable).toMatch(
        /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.denied_jti[\s\S]*?jti\s+uuid\s+PRIMARY\s+KEY[\s\S]*?founder_id\s+uuid\s+NOT\s+NULL\s+REFERENCES\s+public\.users\(id\)/i,
      );
    });

    it("enables RLS with zero policies (service-role-only)", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.denied_jti\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
      // No CREATE POLICY ... ON public.denied_jti anywhere.
      expect(executable).not.toMatch(
        /CREATE\s+POLICY\s+\w+\s+ON\s+public\.denied_jti/i,
      );
    });

    it("declares is_jti_denied SECURITY DEFINER read fn with pinned search_path", () => {
      const fnBlock =
        executable.match(
          /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.is_jti_denied[\s\S]*?\$\$;/i,
        )?.[0] || "";
      expect(fnBlock).not.toBe("");
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
      expect(fnBlock).toMatch(/FROM\s+public\.denied_jti/i);
    });

    it("revokes is_jti_denied PUBLIC and grants service_role only", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.is_jti_denied\([^)]*\)\s+FROM\s+PUBLIC/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.is_jti_denied\([^)]*\)\s+TO\s+service_role/i,
      );
    });
  });

  describe("mint_rate_window table", () => {
    it("creates table with founder_id PK + window_start + mints_count", () => {
      expect(executable).toMatch(
        /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.mint_rate_window[\s\S]*?founder_id\s+uuid\s+PRIMARY\s+KEY[\s\S]*?window_start\s+timestamptz[\s\S]*?mints_count\s+int/i,
      );
    });

    it("enables RLS with zero policies (service-role-only via RPC)", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.mint_rate_window\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
      expect(executable).not.toMatch(
        /CREATE\s+POLICY\s+\w+\s+ON\s+public\.mint_rate_window/i,
      );
    });
  });

  describe("precheck_jwt_mint RPC", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.precheck_jwt_mint[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("function exists with founder_id + ttl_sec parameters", () => {
      expect(fnBlock).not.toBe("");
      expect(fnBlock).toMatch(/p_founder_id\s+uuid/i);
      expect(fnBlock).toMatch(/p_ttl_sec\s+int/i);
    });

    it("returns jti + exp_epoch + iat_epoch (Node mints with these + static claims)", () => {
      // Resolution A (#3363): Node-side HS256 mint. RPC supplies the
      // claims that need DB-side coordination (jti, validity window),
      // Node fills sub/role/aud/iss and signs.
      expect(fnBlock).toMatch(/RETURNS\s+TABLE\s*\(\s*jti\s+uuid/i);
      expect(fnBlock).toMatch(/exp_epoch\s+int/i);
      expect(fnBlock).toMatch(/iat_epoch\s+int/i);
    });

    it("is SECURITY DEFINER with search_path pinned to public, pg_temp", () => {
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });

    it("uses gen_random_uuid for jti (entropy floor)", () => {
      expect(fnBlock).toMatch(/gen_random_uuid\(\)/i);
    });

    it("enforces 60/hour rate limit with mint_rate_exceeded exception", () => {
      // 60 is the plan-specified ceiling per rolling hour.
      expect(fnBlock).toMatch(/>\s*60/);
      expect(fnBlock).toMatch(/mint_rate_exceeded/);
      expect(fnBlock).toMatch(/RAISE\s+EXCEPTION/i);
    });

    it("uses ON CONFLICT atomic increment (race-safe across concurrent mints)", () => {
      // Two concurrent mints must increment exactly once each. The
      // INSERT ... ON CONFLICT DO UPDATE pattern with row-level lock
      // provides the atomicity guarantee.
      expect(fnBlock).toMatch(/INSERT\s+INTO\s+public\.mint_rate_window/i);
      expect(fnBlock).toMatch(/ON\s+CONFLICT\s*\(\s*founder_id\s*\)\s+DO\s+UPDATE/i);
    });

    it("resets the rolling window after 1 hour (sliding-window contract)", () => {
      // window_start updates when older than 1 hour; mints_count
      // resets to 1 in the same branch.
      expect(fnBlock).toMatch(/interval\s+'1\s+hour'/i);
    });

    it("revokes PUBLIC and grants service_role only", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.precheck_jwt_mint\([^)]*\)\s+FROM\s+PUBLIC/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.precheck_jwt_mint\([^)]*\)\s+TO\s+service_role/i,
      );
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.precheck_jwt_mint\([^)]*\)\s+TO\s+authenticated/i,
      );
    });

    it("references public.mint_rate_window with public schema qualified", () => {
      // cq-pg-security-definer-search-path-pin-pg-temp: every relation
      // must be qualified, even though search_path is pinned (belt +
      // suspenders against pg_temp.<table> attacks).
      expect(fnBlock).toMatch(/public\.mint_rate_window/);
    });
  });
});

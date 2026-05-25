import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 064_anonymise_scope_grants_workspace_id_and_
// member_actions_grant.sql (#4356). Offline lint — runs without a live DB.
//
// Pins the two load-bearing invariants:
//   1. anonymise_scope_grants UPDATE sets BOTH founder_id AND workspace_id
//      to NULL (mig 059:358 CHECK requires either both or neither NULL).
//   2. GRANT SELECT ON workspace_member_actions TO service_role (mig 063's
//      explicit REVOKE on SELECT was the outlier; this restores parity with
//      sibling WORM tables).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");

describe("migration 064_anonymise_scope_grants_workspace_id_and_member_actions_grant", () => {
  describe("Part 1: anonymise_scope_grants both-NULL UPDATE", () => {
    it("declares the function as SECURITY DEFINER with search_path pin", () => {
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_scope_grants\s*\(\s*p_user_id\s+uuid\s*\)[\s\S]*?\$\$;/i,
      );
      expect(fnBlock, "expected anonymise_scope_grants function block").not.toBeNull();
      expect(fnBlock![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock![0]).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });

    it("UPDATE SET clause NULLs both founder_id AND workspace_id", () => {
      // Mig 059:358 CHECK is `(founder_id IS NULL AND workspace_id IS NULL)
      // OR (both NOT NULL)`. Single-column NULL transition (mig 050's
      // legacy body) would violate the CHECK.
      expect(executable).toMatch(
        /UPDATE\s+public\.scope_grants\s+SET\s+founder_id\s*=\s*NULL\s*,\s*workspace_id\s*=\s*NULL\s+WHERE\s+founder_id\s*=\s*p_user_id/is,
      );
    });

    it("REVOKEs the function from PUBLIC + anon + authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.anonymise_scope_grants\(uuid\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated/i,
      );
    });

    it("GRANTs EXECUTE on the function to service_role", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.anonymise_scope_grants\(uuid\)\s+TO\s+service_role/i,
      );
    });
  });

  describe("Part 2: workspace_member_actions service_role SELECT GRANT", () => {
    it("GRANTs SELECT only (not UPDATE/DELETE/INSERT) on workspace_member_actions to service_role", () => {
      expect(executable).toMatch(
        /GRANT\s+SELECT\s+ON\s+public\.workspace_member_actions\s+TO\s+service_role/i,
      );
      // INSERT/UPDATE/DELETE must NOT be GRANTed to service_role in mig
      // 064 — those stay REVOKEd per mig 063's defense-in-depth posture.
      expect(executable).not.toMatch(
        /GRANT\s+(INSERT|UPDATE|DELETE|ALL)\s+ON\s+public\.workspace_member_actions\s+TO\s+service_role/i,
      );
    });
  });
});

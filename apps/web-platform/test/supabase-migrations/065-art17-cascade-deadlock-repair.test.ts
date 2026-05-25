import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 065_art17_cascade_deadlock_repair.sql (#4356).
// Offline lint — runs without a live DB.
//
// Pins the load-bearing invariants:
//   1. to_regclass preconditions present (per lint-migration-fk-preconditions).
//   2. organizations.owner_user_id ALTER drops NOT NULL + redeclares FK as
//      ON DELETE SET NULL.
//   3. audit_byok_use.founder_id same pair of ALTERs.
//   4. anonymise_organization_membership simplified — orphan-delete path
//      REMOVED (no DELETE FROM workspaces or organizations inside the
//      function body); reassign path retains tiebreak on user_id.
//   5. REVOKE/GRANT EXECUTE on the function.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/065_art17_cascade_deadlock_repair.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/065_art17_cascade_deadlock_repair.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

describe("migration 065_art17_cascade_deadlock_repair", () => {
  describe("preconditions", () => {
    it("guards public.users with to_regclass", () => {
      expect(executable).toMatch(
        /IF\s+to_regclass\(\s*'public\.users'\s*\)\s+IS\s+NULL\s+THEN/i,
      );
    });

    it("guards public.organizations with to_regclass", () => {
      expect(executable).toMatch(
        /IF\s+to_regclass\(\s*'public\.organizations'\s*\)\s+IS\s+NULL\s+THEN/i,
      );
    });

    it("guards public.audit_byok_use with to_regclass", () => {
      expect(executable).toMatch(
        /IF\s+to_regclass\(\s*'public\.audit_byok_use'\s*\)\s+IS\s+NULL\s+THEN/i,
      );
    });
  });

  describe("Part 1: organizations.owner_user_id RESTRICT → SET NULL", () => {
    it("drops NOT NULL on owner_user_id", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.organizations\s+ALTER\s+COLUMN\s+owner_user_id\s+DROP\s+NOT\s+NULL/i,
      );
    });

    it("drops the old FK constraint", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.organizations\s+DROP\s+CONSTRAINT\s+IF\s+EXISTS\s+organizations_owner_user_id_fkey/i,
      );
    });

    it("re-adds the FK with ON DELETE SET NULL (NOT RESTRICT, NOT CASCADE)", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.organizations\s+ADD\s+CONSTRAINT\s+organizations_owner_user_id_fkey\s+FOREIGN\s+KEY\s+\(owner_user_id\)\s+REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+SET\s+NULL/i,
      );
      // Defensive negative checks — RESTRICT or CASCADE here would silently
      // reintroduce the #4356 deadlock or hard-delete the org on user
      // delete (different bug class).
      expect(executable).not.toMatch(
        /ADD\s+CONSTRAINT\s+organizations_owner_user_id_fkey[\s\S]*?ON\s+DELETE\s+RESTRICT/i,
      );
      expect(executable).not.toMatch(
        /ADD\s+CONSTRAINT\s+organizations_owner_user_id_fkey[\s\S]*?ON\s+DELETE\s+CASCADE/i,
      );
    });
  });

  describe("Part 2: audit_byok_use.founder_id RESTRICT → SET NULL", () => {
    it("drops NOT NULL on founder_id", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.audit_byok_use\s+ALTER\s+COLUMN\s+founder_id\s+DROP\s+NOT\s+NULL/i,
      );
    });

    it("drops the old FK constraint", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.audit_byok_use\s+DROP\s+CONSTRAINT\s+IF\s+EXISTS\s+audit_byok_use_founder_id_fkey/i,
      );
    });

    it("re-adds the FK with ON DELETE SET NULL (NOT RESTRICT, NOT CASCADE)", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.audit_byok_use\s+ADD\s+CONSTRAINT\s+audit_byok_use_founder_id_fkey\s+FOREIGN\s+KEY\s+\(founder_id\)\s+REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+SET\s+NULL/i,
      );
      expect(executable).not.toMatch(
        /ADD\s+CONSTRAINT\s+audit_byok_use_founder_id_fkey[\s\S]*?ON\s+DELETE\s+RESTRICT/i,
      );
      expect(executable).not.toMatch(
        /ADD\s+CONSTRAINT\s+audit_byok_use_founder_id_fkey[\s\S]*?ON\s+DELETE\s+CASCADE/i,
      );
    });
  });

  describe("Part 3: anonymise_organization_membership simplified", () => {
    it("redeclares the function as SECURITY DEFINER with search_path pin", () => {
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_organization_membership\s*\(\s*p_user_id\s+uuid\s*\)[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fnBlock![0]).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });

    it("body has NO orphan-delete path (no DELETE FROM workspaces or organizations inside the function)", () => {
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_organization_membership[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      // The mig 058 legacy body DELETEd from workspaces and organizations
      // inside the function — mig 065 Part 3 simplification removes both.
      expect(fnBlock![0]).not.toMatch(/DELETE\s+FROM\s+public\.workspaces/i);
      expect(fnBlock![0]).not.toMatch(
        /DELETE\s+FROM\s+public\.organizations/i,
      );
    });

    it("reassign UPDATE has deterministic ORDER BY tiebreak (created_at + user_id)", () => {
      const fnBlock = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_organization_membership[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(
        /ORDER\s+BY\s+m\.created_at\s+ASC\s*,\s*m\.user_id\s+ASC/i,
      );
    });

    it("REVOKEs from PUBLIC + anon + authenticated and GRANTs EXECUTE to service_role", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.anonymise_organization_membership\(uuid\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.anonymise_organization_membership\(uuid\)\s+TO\s+service_role/i,
      );
    });
  });

  describe("down migration", () => {
    it("restores the legacy orphan-delete path (DELETE FROM workspaces + organizations inside the fn body)", () => {
      const fnBlock = downExecutable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_organization_membership[\s\S]*?\$\$;/i,
      );
      expect(fnBlock).not.toBeNull();
      expect(fnBlock![0]).toMatch(/DELETE\s+FROM\s+public\.workspaces/i);
      expect(fnBlock![0]).toMatch(/DELETE\s+FROM\s+public\.organizations/i);
    });

    it("disables WORM trigger via session_replication_role=replica around the audit_byok_use DELETE", () => {
      // Without the bracket, the WORM trigger raises P0001 on the
      // pre-NOT-NULL DELETE and rollback aborts.
      expect(downExecutable).toMatch(
        /SET\s+LOCAL\s+session_replication_role\s*=\s*'replica'\s*;[\s\S]*?DELETE\s+FROM\s+public\.audit_byok_use\s+WHERE\s+founder_id\s+IS\s+NULL/i,
      );
    });

    it("restores RESTRICT FK on audit_byok_use.founder_id", () => {
      expect(downExecutable).toMatch(
        /ADD\s+CONSTRAINT\s+audit_byok_use_founder_id_fkey\s+FOREIGN\s+KEY\s+\(founder_id\)\s+REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });

    it("restores RESTRICT FK on organizations.owner_user_id", () => {
      expect(downExecutable).toMatch(
        /ADD\s+CONSTRAINT\s+organizations_owner_user_id_fkey\s+FOREIGN\s+KEY\s+\(owner_user_id\)\s+REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });
  });
});

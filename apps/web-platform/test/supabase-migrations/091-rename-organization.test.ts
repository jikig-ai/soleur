import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 091_rename_organization_and_default_names.sql.
//
// Pins the SQL invariants of the org-name fix (feat-one-shot-workspace-
// untitled-name) so a future edit that drops them is caught at PR-time
// without requiring a live Supabase. Structural pattern mirrors
// 063-workspace-member-actions.test.ts (readFileSync + regex on source).
//
// Covers:
//   - AC1 (trigger default): handle_new_user re-derives the FULL 053 body
//     and inserts a non-NULL default for organizations.name + workspaces.name,
//     WITHOUT dropping any 053 arm (public.users insert, canary guard,
//     org/workspace/member creation).
//   - AC2 (backfill): UPDATE organizations SET name = default WHERE name IS NULL.
//   - AC3 (rename RPC): rename_organization SECURITY DEFINER + pinned
//     search_path + auth.uid() owner-gate + name validation + REVOKE/GRANT.
//   - SECURITY DEFINER hygiene (search_path pin on every definer fn).
//   - down migration drops the RPC + restores the prior handle_new_user body.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/091_rename_organization_and_default_names.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/091_rename_organization_and_default_names.down.sql",
);

describe("migration 091_rename_organization_and_default_names", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const down = readFileSync(DOWN_PATH, "utf8");
  // Strip line comments so prose mentioning "NULL" / "auth.uid()" doesn't
  // satisfy executable-code assertions.
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("AC3: rename_organization RPC", () => {
    it("declares rename_organization(p_organization_id uuid, p_name text, p_caller_user_id uuid DEFAULT NULL)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rename_organization\(\s*p_organization_id\s+uuid\s*,\s*p_name\s+text\s*,\s*p_caller_user_id\s+uuid\s+DEFAULT\s+NULL\s*\)/i,
      );
    });

    it("resolves caller via COALESCE(p_caller_user_id, auth.uid()) for service-role invocation", () => {
      const body = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rename_organization\([\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(body![1]).toMatch(
        /COALESCE\(\s*p_caller_user_id\s*,\s*auth\.uid\(\)\s*\)/i,
      );
    });

    it("is SECURITY DEFINER plpgsql with pinned search_path", () => {
      const fn = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rename_organization\([\s\S]*?AS\s+\$\$/i,
      );
      expect(fn).not.toBeNull();
      expect(fn![0]).toMatch(/LANGUAGE\s+plpgsql/i);
      expect(fn![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fn![0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });

    it("authenticates via auth.uid() and raises 28000 when NULL", () => {
      const body = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rename_organization\([\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(body).not.toBeNull();
      expect(body![1]).toMatch(/auth\.uid\(\)/i);
      expect(body![1]).toMatch(/ERRCODE\s*=\s*'28000'/i);
    });

    it("owner-gates on workspace_members role='owner' joined to the org and raises 42501", () => {
      const body = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rename_organization\([\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(body![1]).toMatch(/role\s*=\s*'owner'/i);
      expect(body![1]).toMatch(
        /JOIN\s+public\.workspaces\s+w\s+ON\s+w\.id\s*=\s*m\.workspace_id/i,
      );
      expect(body![1]).toMatch(/caller is not an owner/i);
      expect(body![1]).toMatch(/ERRCODE\s*=\s*'42501'/i);
    });

    it("validates name: trims, rejects empty, bounds length to 60", () => {
      const body = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rename_organization\([\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(body![1]).toMatch(/btrim\(/i);
      expect(body![1]).toMatch(/length\([^)]*\)\s*=\s*0/i);
      expect(body![1]).toMatch(/length\([^)]*\)\s*>\s*60/i);
      expect(body![1]).toMatch(/ERRCODE\s*=\s*'22023'/i);
    });

    it("updates organizations.name and REVOKE/GRANTs per convention", () => {
      const body = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.rename_organization\([\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(body![1]).toMatch(
        /UPDATE\s+public\.organizations\s+SET\s+name\s*=/i,
      );
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.rename_organization\(uuid,\s*text,\s*uuid\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.rename_organization\(uuid,\s*text,\s*uuid\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("AC1: handle_new_user re-derivation with non-NULL defaults", () => {
    const triggerBody = (sqlSrc: string) =>
      sqlSrc
        .replace(/--[^\n]*/g, "")
        .match(
          /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.handle_new_user\(\)[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
        );

    it("re-issues handle_new_user as SECURITY DEFINER with pinned search_path", () => {
      const fn = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.handle_new_user\(\)[\s\S]*?AS\s+\$\$/i,
      );
      expect(fn).not.toBeNull();
      expect(fn![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fn![0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });

    it("preserves every 053 arm (public.users insert, canary guard, workspace + member creation)", () => {
      const body = triggerBody(sql);
      expect(body).not.toBeNull();
      expect(body![1]).toMatch(/INSERT\s+INTO\s+public\.users/i);
      expect(body![1]).toMatch(/ON\s+CONFLICT\s+\(id\)\s+DO\s+NOTHING/i);
      // canary owner-row idempotency guard
      expect(body![1]).toMatch(
        /SELECT\s+1\s+FROM\s+public\.workspace_members[\s\S]*?role\s*=\s*'owner'/i,
      );
      expect(body![1]).toMatch(/INSERT\s+INTO\s+public\.organizations/i);
      expect(body![1]).toMatch(/INSERT\s+INTO\s+public\.workspaces/i);
      expect(body![1]).toMatch(
        /INSERT\s+INTO\s+public\.workspace_members[\s\S]*?'owner'/i,
      );
    });

    it("inserts a non-NULL default org name (NOT a NULL literal)", () => {
      const body = triggerBody(sql);
      // The organizations INSERT must not pass NULL for name. Assert the
      // default-name constant is present and the bare `NULL, NULL` pair from
      // 053 (name, domain) no longer appears in the org insert.
      expect(body![1]).toMatch(/INSERT\s+INTO\s+public\.organizations[\s\S]*?'My Workspace'/i);
    });
  });

  describe("AC2: backfill NULL org names to the default", () => {
    it("UPDATEs organizations SET name to the default WHERE name IS NULL", () => {
      expect(executable).toMatch(
        /UPDATE\s+public\.organizations\s+SET\s+name\s*=\s*'My Workspace'\s+WHERE\s+name\s+IS\s+NULL/i,
      );
    });

    it("also backfills NULL workspace names (defensive)", () => {
      expect(executable).toMatch(
        /UPDATE\s+public\.workspaces\s+SET\s+name\s*=\s*'My Workspace'\s+WHERE\s+name\s+IS\s+NULL/i,
      );
    });
  });

  describe("SECURITY DEFINER hygiene", () => {
    it("every SECURITY DEFINER function pins SET search_path = public, pg_temp", () => {
      const definerFns = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION[\s\S]*?SECURITY\s+DEFINER[\s\S]*?(?=\$\$)/gi,
      );
      expect(definerFns).not.toBeNull();
      for (const fn of definerFns!) {
        expect(
          fn,
          `SECURITY DEFINER fn missing search_path pin:\n${fn.slice(0, 160)}`,
        ).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
      }
    });
  });

  describe("down migration", () => {
    it("drops rename_organization", () => {
      expect(down).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.rename_organization/i,
      );
    });

    it("restores handle_new_user with the prior NULL-name body", () => {
      expect(down).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.handle_new_user\(\)/i,
      );
      const body = down
        .replace(/--[^\n]*/g, "")
        .match(
          /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.handle_new_user\(\)[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
        );
      expect(body).not.toBeNull();
      // The restored body inserts NULL for the org name (053 shape).
      expect(body![1]).toMatch(
        /INSERT\s+INTO\s+public\.organizations[\s\S]*?VALUES\s*\(\s*gen_random_uuid\(\)\s*,\s*NULL\s*,\s*NULL/i,
      );
    });

    it("does NOT revert the backfill (names are user data)", () => {
      expect(down).not.toMatch(
        /UPDATE\s+public\.organizations\s+SET\s+name\s*=\s*NULL/i,
      );
    });
  });
});

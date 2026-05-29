import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 085_revoke_workspace_invitation.sql
// (feat-cancel-pending-invite, #4634). Offline lint — live WORM/RPC/predicate
// behavior is covered by the opt-in TENANT_INTEGRATION_TEST=1 suite.
//
// Owner-side soft revoke: adds revoked_at/revoked_by to workspace_invitations
// (075), extends the 075 WORM trigger with negative-rejection arms for the two
// new columns (NULL→NOT-NULL permitted by fall-through; re-mutation rejected),
// adds the revoke_workspace_invitation SECURITY DEFINER RPC (mirrors
// decline_workspace_invitation), and filters revoked rows out of
// lookup_invitation_by_token + the create_workspace_invitation duplicate guard.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/085_revoke_workspace_invitation.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/085_revoke_workspace_invitation.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

describe("migration 085_revoke_workspace_invitation", () => {
  describe("header", () => {
    it("references the issue and the table it extends", () => {
      expect(sql).toMatch(/#4634/);
      expect(sql).toMatch(/workspace_invitations/);
    });
  });

  describe("columns (TR1)", () => {
    it("adds revoked_at timestamptz NULL (idempotent)", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.workspace_invitations\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+revoked_at\s+timestamptz/i,
      );
    });
    it("adds revoked_by uuid REFERENCES public.users ON DELETE RESTRICT (idempotent)", () => {
      expect(executable).toMatch(
        /ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+revoked_by\s+uuid[\s\S]*?REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });
  });

  describe("WORM trigger extension (075 negative-rejection idiom)", () => {
    const fn = () =>
      executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_invitations_no_mutate\(\)[\s\S]*?\$\$;/i,
      )![0];
    it("re-issues the no_mutate fn with search_path pinned", () => {
      expect(fn()).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });
    it("rejects re-mutation of revoked_at once set (NOT NULL → distinct)", () => {
      expect(fn()).toMatch(
        /OLD\.revoked_at\s+IS\s+NOT\s+NULL\s+AND\s+NEW\.revoked_at\s+IS\s+DISTINCT\s+FROM\s+OLD\.revoked_at/i,
      );
    });
    it("rejects re-mutation of revoked_by once set, but permits NOT NULL → NULL for Art. 17", () => {
      // NEW.revoked_by IS NOT NULL guard keeps the anonymise (NOT NULL → NULL)
      // path open while still rejecting NOT NULL → different NOT NULL.
      expect(fn()).toMatch(
        /OLD\.revoked_by\s+IS\s+NOT\s+NULL[\s\S]*?NEW\.revoked_by\s+IS\s+DISTINCT\s+FROM\s+OLD\.revoked_by/i,
      );
    });
    it("does NOT DROP the trigger (CREATE OR REPLACE updates in place)", () => {
      expect(executable).not.toMatch(/DROP\s+TRIGGER[\s\S]*?workspace_invitations_no_update/i);
    });
  });

  describe("revoke_workspace_invitation RPC (TR2)", () => {
    const fn = () =>
      executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.revoke_workspace_invitation\s*\([^)]*\)[\s\S]*?\$\$;/i,
      )![0];
    it("takes p_invitation_id and p_caller_user_id (DEFAULT NULL)", () => {
      const params = executable.match(/revoke_workspace_invitation\s*\(([^)]*)\)/i)![1];
      expect(params).toMatch(/p_invitation_id\s+uuid/i);
      expect(params).toMatch(/p_caller_user_id\s+uuid\s+DEFAULT\s+NULL/i);
    });
    it("is SECURITY DEFINER with search_path pinned to public, pg_temp", () => {
      expect(fn()).toMatch(/SECURITY\s+DEFINER/i);
      expect(fn()).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });
    it("locks the row FOR UPDATE", () => {
      expect(fn()).toMatch(/FOR\s+UPDATE/i);
    });
    it("returns terminal-state reasons rather than RAISE (mirrors decline)", () => {
      const body = fn();
      expect(body).toMatch(/'invitation_not_found'/);
      expect(body).toMatch(/'already_accepted'/);
      expect(body).toMatch(/'already_declined'/);
      expect(body).toMatch(/'already_revoked'/);
    });
    it("re-checks caller is workspace owner → caller_not_owner", () => {
      const body = fn();
      expect(body).toMatch(/role\s*=\s*'owner'/i);
      expect(body).toMatch(/'caller_not_owner'/);
    });
    it("sets revoked_at = now() and revoked_by = caller", () => {
      const body = fn();
      expect(body).toMatch(/SET\s+revoked_at\s*=\s*now\(\)/i);
      expect(body).toMatch(/revoked_by\s*=\s*/i);
    });
    it("grants EXECUTE to service_role only", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.revoke_workspace_invitation\([^)]*\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.revoke_workspace_invitation\([^)]*\)\s+TO\s+service_role/i,
      );
    });
  });

  describe("accept_workspace_invitation: revoked arm (FR4 — mutation gate)", () => {
    const fn = () =>
      executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.accept_workspace_invitation[\s\S]*?\$\$;/i,
      )![0];
    it("re-issues accept and rejects a revoked invite with reason 'revoked'", () => {
      const body = fn();
      expect(body).toMatch(/revoked_at\s+IS\s+NOT\s+NULL/i);
      expect(body).toMatch(/'revoked'/);
    });
    it("the down migration also restores accept_workspace_invitation (before column drop)", () => {
      expect(downExecutable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.accept_workspace_invitation[\s\S]*?DROP\s+COLUMN\s+IF\s+EXISTS\s+revoked_by/i,
      );
    });
  });

  describe("lookup_invitation_by_token: revoked arm (TR3/FR4)", () => {
    const fn = () =>
      executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.lookup_invitation_by_token[\s\S]*?\$\$;/i,
      )![0];
    it("rejects a revoked invite with reason 'revoked'", () => {
      const body = fn();
      expect(body).toMatch(/revoked_at\s+IS\s+NOT\s+NULL/i);
      expect(body).toMatch(/'revoked'/);
    });
  });

  describe("create_workspace_invitation: revoked-aware duplicate guard (TR3/FR5)", () => {
    const fn = () =>
      executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.create_workspace_invitation[\s\S]*?\$\$;/i,
      )![0];
    it("excludes revoked rows from the duplicate-pending guard", () => {
      // The pending-duplicate EXISTS must require revoked_at IS NULL so a
      // re-invite after cancel is not blocked.
      expect(fn()).toMatch(/accepted_at\s+IS\s+NULL[\s\S]*?declined_at\s+IS\s+NULL[\s\S]*?revoked_at\s+IS\s+NULL/i);
    });
  });

  describe("GDPR Art. 17 follow-through (TR2.4)", () => {
    it("anonymise_workspace_invitations nulls revoked_by", () => {
      const m = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_workspace_invitations[\s\S]*?\$\$;/i,
      );
      expect(m, "anonymise RPC must be re-issued to null revoked_by").not.toBeNull();
      expect(m![0]).toMatch(/revoked_by\s*=\s*NULL/i);
    });
  });

  describe("down migration", () => {
    it("drops the revoke RPC", () => {
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.revoke_workspace_invitation\([^)]*\)/i,
      );
    });
    it("drops revoked_by and revoked_at columns", () => {
      expect(downExecutable).toMatch(/DROP\s+COLUMN\s+IF\s+EXISTS\s+revoked_by/i);
      expect(downExecutable).toMatch(/DROP\s+COLUMN\s+IF\s+EXISTS\s+revoked_at/i);
    });
    it("restores lookup + create + WORM without the revoked arms", () => {
      expect(downExecutable).toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.lookup_invitation_by_token/i);
      expect(downExecutable).toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.create_workspace_invitation/i);
      expect(downExecutable).toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_invitations_no_mutate/i);
    });
  });
});

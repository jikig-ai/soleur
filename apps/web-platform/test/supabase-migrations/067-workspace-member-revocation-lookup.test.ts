import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 067_workspace_member_revocation_lookup.sql
// (issue #4307, feat-rls-known-gaps-4233-bundle PR-1). Offline lint —
// runs without a live database.
//
// Enforces the F1 / F2 / F6 invariants from the v2 plan-review:
//   F1: EXACTLY TWO `CREATE OR REPLACE FUNCTION` bodies in mig 067
//       contain `INSERT INTO public.workspace_member_removals` —
//       `remove_workspace_member` (revocation_reason='removed') AND
//       `update_workspace_member_role` (revocation_reason='role-changed').
//   F2: `update_workspace_member_role` body contains
//       `PERFORM set_config('workspace_audit.actor_user_id'` so the
//       PA-20 §(g)(3) trigger-driven writer captures the actor.
//   F6: BOTH RPCs contain an `UPDATE public.user_session_state` that
//       clears `current_organization_id` when affected.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/067_workspace_member_revocation_lookup.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/067_workspace_member_revocation_lookup.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
// Strip line-comments so per-line `--` prose doesn't false-match the patterns.
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

// Extract `CREATE OR REPLACE FUNCTION <name>(...) ... AS $$ ... $$;` bodies.
// Non-greedy match up to the next `$$;` closer.
function extractFunctionBodies(src: string): Map<string, string> {
  const re =
    /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.(\w+)\s*\(([^)]*)\)[\s\S]*?\$\$([\s\S]*?)\$\$\s*;/gi;
  const out = new Map<string, string>();
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    out.set(m[1], m[3]);
  }
  return out;
}

const fnBodies = extractFunctionBodies(executable);

describe("migration 067_workspace_member_revocation_lookup", () => {
  describe("schema additions", () => {
    it("ALTERs workspace_member_removals to ADD revoked_after timestamptz NULL", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.workspace_member_removals[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+revoked_after\s+timestamptz\s+NULL/i,
      );
    });

    it("ALTERs workspace_member_removals to ADD revocation_reason text NULL", () => {
      expect(executable).toMatch(
        /ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+revocation_reason\s+text\s+NULL/i,
      );
    });

    it("backfills legacy rows with revoked_after = removed_at and revocation_reason = 'removed'", () => {
      expect(executable).toMatch(
        /UPDATE\s+public\.workspace_member_removals[\s\S]*?SET\s+revoked_after\s*=\s*removed_at[\s\S]*?revocation_reason\s*=\s*'removed'[\s\S]*?WHERE\s+revoked_after\s+IS\s+NULL/i,
      );
    });

    it("creates the lookup index on (removed_user_id, revoked_after)", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+workspace_member_removals_revocation_lookup_idx\s+ON\s+public\.workspace_member_removals\s*\(removed_user_id,\s*revoked_after\)/i,
      );
    });
  });

  describe("check_my_revocation RPC", () => {
    it("declares the function with the (p_jwt_iat timestamptz) signature", () => {
      expect(executable).toMatch(
        /CREATE\s+FUNCTION\s+public\.check_my_revocation\s*\(\s*p_jwt_iat\s+timestamptz\s*\)/i,
      );
    });

    it("returns TABLE(revoked boolean, workspace_id uuid, reason text)", () => {
      expect(executable).toMatch(
        /RETURNS\s+TABLE\s*\(\s*revoked\s+boolean\s*,\s*workspace_id\s+uuid\s*,\s*reason\s+text\s*\)/i,
      );
    });

    it("is SECURITY DEFINER with search_path pinned to public, pg_temp (cq-pg-security-definer-search-path-pin-pg-temp)", () => {
      const body = fnBodies.get("check_my_revocation") ?? "";
      expect(executable).toMatch(
        /FUNCTION\s+public\.check_my_revocation[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
      expect(body).toBeTruthy();
    });

    it("REVOKEs from PUBLIC, anon, authenticated, service_role and GRANTs EXECUTE TO authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.check_my_revocation\(timestamptz\)\s+FROM\s+PUBLIC,\s+anon,\s+authenticated,\s+service_role/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.check_my_revocation\(timestamptz\)\s+TO\s+authenticated/i,
      );
    });

    it("uses strict `>` (not `>=`) on revoked_after vs p_jwt_iat — ±1s skew lands on the safer (deny) side", () => {
      const body = fnBodies.get("check_my_revocation") ?? "";
      expect(body).toMatch(/wmr\.revoked_after\s*>\s*p_jwt_iat/i);
      expect(body).not.toMatch(/wmr\.revoked_after\s*>=\s*p_jwt_iat/i);
    });

    it("user-global predicate (F5): filters on removed_user_id = auth.uid() with NO current_organization_id reference", () => {
      const body = fnBodies.get("check_my_revocation") ?? "";
      expect(body).toMatch(/removed_user_id\s*=\s*auth\.uid\(\)/i);
      expect(body).not.toMatch(/current_organization_id/i);
    });
  });

  describe("update_workspace_member_role RPC", () => {
    it("declares the function with (p_workspace_id uuid, p_user_id uuid, p_new_role text)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.update_workspace_member_role\s*\(\s*p_workspace_id\s+uuid\s*,\s*p_user_id\s+uuid\s*,\s*p_new_role\s+text\s*\)/i,
      );
    });

    it("is SECURITY DEFINER with search_path pinned", () => {
      expect(executable).toMatch(
        /FUNCTION\s+public\.update_workspace_member_role[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("F2: body contains PERFORM set_config('workspace_audit.actor_user_id'", () => {
      const body = fnBodies.get("update_workspace_member_role") ?? "";
      expect(body).toMatch(
        /PERFORM\s+set_config\(\s*'workspace_audit\.actor_user_id'/i,
      );
    });

    it("enforces caller-is-owner (42501) and validates role in {owner,member}", () => {
      const body = fnBodies.get("update_workspace_member_role") ?? "";
      expect(body).toMatch(/p_new_role\s+NOT\s+IN\s*\(\s*'owner'\s*,\s*'member'\s*\)/i);
      expect(body).toMatch(/role\s*=\s*'owner'/i);
      expect(body).toMatch(/ERRCODE\s*=\s*'42501'/i);
    });

    it("REVOKEs from PUBLIC + anon + authenticated (NOT service_role; TS wrapper calls via createServiceClient) and GRANTs EXECUTE TO authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.update_workspace_member_role\(uuid,\s+uuid,\s+text\)\s+FROM\s+PUBLIC,\s+anon,\s+authenticated;/i,
      );
      // Negative-space gate: service_role MUST NOT be in the REVOKE list
      // (would strip default EXECUTE → wrapper gets 42501).
      expect(executable).not.toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.update_workspace_member_role\(uuid,\s+uuid,\s+text\)\s+FROM[^;]*service_role/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.update_workspace_member_role\(uuid,\s+uuid,\s+text\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("F1: exactly two function bodies INSERT into workspace_member_removals", () => {
    it("exactly two CREATE OR REPLACE FUNCTION bodies contain the INSERT", () => {
      const inserters = Array.from(fnBodies.entries()).filter(([, body]) =>
        /INSERT\s+INTO\s+public\.workspace_member_removals\b/i.test(body),
      );
      const names = inserters.map(([n]) => n).sort();
      expect(names).toEqual(
        ["remove_workspace_member", "update_workspace_member_role"].sort(),
      );
    });

    it("remove_workspace_member INSERTs with revocation_reason = 'removed'", () => {
      const body = fnBodies.get("remove_workspace_member") ?? "";
      expect(body).toMatch(
        /INSERT\s+INTO\s+public\.workspace_member_removals[\s\S]*?'removed'/i,
      );
    });

    it("update_workspace_member_role INSERTs with revocation_reason = 'role-changed'", () => {
      const body = fnBodies.get("update_workspace_member_role") ?? "";
      expect(body).toMatch(
        /INSERT\s+INTO\s+public\.workspace_member_removals[\s\S]*?'role-changed'/i,
      );
    });
  });

  describe("F6: both RPCs UPDATE user_session_state to clear current_organization_id", () => {
    it("remove_workspace_member body contains the user_session_state clear", () => {
      const body = fnBodies.get("remove_workspace_member") ?? "";
      expect(body).toMatch(
        /UPDATE\s+public\.user_session_state[\s\S]*?SET\s+current_organization_id\s*=\s*NULL/i,
      );
    });

    it("update_workspace_member_role body contains the user_session_state clear", () => {
      const body = fnBodies.get("update_workspace_member_role") ?? "";
      expect(body).toMatch(
        /UPDATE\s+public\.user_session_state[\s\S]*?SET\s+current_organization_id\s*=\s*NULL/i,
      );
    });
  });

  describe("down migration", () => {
    it("DROPs both new functions", () => {
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.update_workspace_member_role/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.check_my_revocation/i,
      );
    });

    it("DROPs the lookup index and the two columns", () => {
      expect(downExecutable).toMatch(
        /DROP\s+INDEX\s+IF\s+EXISTS\s+public\.workspace_member_removals_revocation_lookup_idx/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+COLUMN\s+IF\s+EXISTS\s+revoked_after/i,
      );
      expect(downExecutable).toMatch(
        /DROP\s+COLUMN\s+IF\s+EXISTS\s+revocation_reason/i,
      );
    });
  });
});

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for
// 094_member_rpc_caller_override_and_byok_cap_update.sql.
//
// Pins the SQL invariants of three changes so a future edit that drops them is
// caught at PR-time without a live Supabase (mirrors
// 092-transfer-ownership-caller-override.test.ts; per learning
// 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md vitest mocks resolve
// .rpc to vi.fn() and CANNOT catch a GRANT mismatch, so this source-regex test
// is the canonical plan-time grant gate).
//
// Covers:
//   Problem 1 (member-removal 500): remove_workspace_member widened to 3-arg
//     with COALESCE(p_caller_user_id, auth.uid()) caller resolution +
//     service_role-only grant (the sole caller invokes via createServiceClient
//     where auth.uid() is NULL → every removal raised 28000 → rpc_failed → 500).
//   Defense-in-depth: update_workspace_member_role patched identically.
//   Problem 2 (no post-join cap update): new update_byok_delegation_cap RPC
//     performs the WORM Shape-3 cap-update flip, granted authenticated +
//     service_role (impersonation-guarded, like grant/revoke_byok_delegation).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/094_member_rpc_caller_override_and_byok_cap_update.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/094_member_rpc_caller_override_and_byok_cap_update.down.sql",
);

describe("migration 094_member_rpc_caller_override_and_byok_cap_update", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const down = readFileSync(DOWN_PATH, "utf8");
  // Strip line comments so prose mentioning "auth.uid()" / "authenticated"
  // doesn't satisfy executable-code assertions.
  const executable = sql.replace(/--[^\n]*/g, "");

  const fnBody = (src: string, name: string) =>
    src.match(
      new RegExp(
        `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${name}\\([\\s\\S]*?\\$\\$([\\s\\S]*?)\\$\\$;`,
        "i",
      ),
    );

  // ---------------------------------------------------------------
  // remove_workspace_member (Problem 1)
  // ---------------------------------------------------------------
  describe("remove_workspace_member: 3-arg caller-override", () => {
    it("declares remove_workspace_member(p_workspace_id, p_user_id, p_caller_user_id uuid DEFAULT NULL)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.remove_workspace_member\(\s*p_workspace_id\s+uuid\s*,\s*p_user_id\s+uuid\s*,\s*p_caller_user_id\s+uuid\s+DEFAULT\s+NULL\s*\)/i,
      );
    });

    it("resolves caller via COALESCE(p_caller_user_id, auth.uid())", () => {
      const body = fnBody(executable, "remove_workspace_member");
      expect(body).not.toBeNull();
      expect(body![1]).toMatch(
        /v_caller_user_id\s+uuid\s*:=\s*COALESCE\(\s*p_caller_user_id\s*,\s*auth\.uid\(\)\s*\)/i,
      );
    });

    it("DROPs the old 2-arg overload (so authenticated cannot reach the superseded form)", () => {
      expect(executable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.remove_workspace_member\(uuid,\s*uuid\)\s*;/i,
      );
    });

    it("REVOKEs the 3-arg form from PUBLIC, anon, authenticated and GRANTs service_role ONLY", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.remove_workspace_member\(uuid,\s*uuid,\s*uuid\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.remove_workspace_member\(uuid,\s*uuid,\s*uuid\)\s+TO\s+service_role/i,
      );
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.remove_workspace_member\(uuid,\s*uuid,\s*uuid\)\s+TO\s+authenticated/i,
      );
    });

    it("preserves every behavioral arm (28000/42501/self/owner-target, attachment cascade, WORM row, session clear)", () => {
      const body = fnBody(executable, "remove_workspace_member")![1];
      expect(body).toMatch(/ERRCODE\s*=\s*'28000'/i);
      expect(body).toMatch(/caller is not an owner/i);
      expect(body).toMatch(/ERRCODE\s*=\s*'42501'/i);
      expect(body).toMatch(/owner cannot remove themselves/i);
      expect(body).toMatch(/cannot remove another owner/i);
      // mig 068 attachment-anonymisation cascade MUST survive.
      expect(body).toMatch(/_anonymise_authored_messages_internal/i);
      expect(body).toMatch(/INSERT\s+INTO\s+public\.workspace_member_removals/i);
      expect(body).toMatch(/DELETE\s+FROM\s+public\.workspace_members/i);
      expect(body).toMatch(
        /UPDATE\s+public\.user_session_state[\s\S]*?current_organization_id\s*=\s*NULL/i,
      );
    });
  });

  // ---------------------------------------------------------------
  // update_workspace_member_role (defense-in-depth)
  // ---------------------------------------------------------------
  describe("update_workspace_member_role: 4-arg caller-override", () => {
    it("declares update_workspace_member_role(..., p_caller_user_id uuid DEFAULT NULL)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.update_workspace_member_role\(\s*p_workspace_id\s+uuid\s*,\s*p_user_id\s+uuid\s*,\s*p_new_role\s+text\s*,\s*p_caller_user_id\s+uuid\s+DEFAULT\s+NULL\s*\)/i,
      );
    });

    it("resolves caller via COALESCE and DROPs the old 3-arg overload", () => {
      const body = fnBody(executable, "update_workspace_member_role")![1];
      expect(body).toMatch(
        /v_caller_user_id\s+uuid\s*:=\s*COALESCE\(\s*p_caller_user_id\s*,\s*auth\.uid\(\)\s*\)/i,
      );
      expect(executable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.update_workspace_member_role\(uuid,\s*uuid,\s*text\)\s*;/i,
      );
    });

    it("preserves last-owner-demote guard + invalid-role guard + audit GUC", () => {
      const body = fnBody(executable, "update_workspace_member_role")![1];
      expect(body).toMatch(/cannot demote the last owner/i);
      expect(body).toMatch(/invalid role/i);
      expect(body).toMatch(/set_config\(\s*'workspace_audit\.actor_user_id'/i);
    });

    it("REVOKEs the 4-arg form from PUBLIC, anon, authenticated and GRANTs service_role ONLY", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.update_workspace_member_role\(uuid,\s*uuid,\s*text,\s*uuid\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.update_workspace_member_role\(uuid,\s*uuid,\s*text,\s*uuid\)\s+TO\s+service_role/i,
      );
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.update_workspace_member_role\(uuid,\s*uuid,\s*text,\s*uuid\)\s+TO\s+authenticated/i,
      );
    });
  });

  // ---------------------------------------------------------------
  // update_byok_delegation_cap (Problem 2)
  // ---------------------------------------------------------------
  describe("update_byok_delegation_cap: new WORM Shape-3 cap-update RPC", () => {
    it("declares the 4-arg signature", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.update_byok_delegation_cap\(\s*p_delegation_id\s+uuid\s*,\s*p_daily_usd_cap_cents\s+int\s*,\s*p_hourly_usd_cap_cents\s+int\s*,\s*p_actor_user_id\s+uuid\s+DEFAULT\s+NULL\s*\)/i,
      );
    });

    it("is SECURITY DEFINER with pinned search_path", () => {
      const decl = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.update_byok_delegation_cap\([\s\S]*?AS\s+\$\$/i,
      );
      expect(decl).not.toBeNull();
      expect(decl![0]).toMatch(/LANGUAGE\s+plpgsql/i);
      expect(decl![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(decl![0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });

    it("branches on auth.uid() IS NULL like revoke_byok_delegation (service-role requires actor; authenticated forbids impersonation)", () => {
      const body = fnBody(executable, "update_byok_delegation_cap")![1];
      expect(body).toMatch(/v_caller_jwt\s+uuid\s*:=\s*auth\.uid\(\)/i);
      expect(body).toMatch(/service-role caller MUST supply p_actor_user_id/i);
      expect(body).toMatch(/MAY NOT impersonate another actor/i);
    });

    it("rejects revoked/not-found rows and restricts actor to grantor/created_by (grantee may NOT raise own cap)", () => {
      const body = fnBody(executable, "update_byok_delegation_cap")![1];
      expect(body).toMatch(/FOR\s+UPDATE/i);
      expect(body).toMatch(/ERRCODE\s*=\s*'P0002'/i); // not found
      expect(body).toMatch(/already revoked/i);
      // actor ∈ {grantor, created_by} — grantee is intentionally NOT included.
      expect(body).toMatch(
        /v_actor\s+NOT\s+IN\s*\(\s*v_row\.grantor_user_id\s*,\s*v_row\.created_by_user_id\s*\)/i,
      );
      expect(body).not.toMatch(/v_row\.grantee_user_id/i);
    });

    it("enforces cap range checks identical to grant_byok_delegation", () => {
      const body = fnBody(executable, "update_byok_delegation_cap")![1];
      expect(body).toMatch(/p_daily_usd_cap_cents[\s\S]*?1000000/i);
      expect(body).toMatch(/p_hourly_usd_cap_cents[\s\S]*?p_daily_usd_cap_cents/i);
    });

    it("performs the WORM Shape-3 UPDATE (caps + cap_updated_at + cap_updated_by_user_id, nothing else)", () => {
      const body = fnBody(executable, "update_byok_delegation_cap")![1];
      expect(body).toMatch(
        /UPDATE\s+public\.byok_delegations[\s\S]*?daily_usd_cap_cents\s*=\s*p_daily_usd_cap_cents[\s\S]*?hourly_usd_cap_cents\s*=\s*p_hourly_usd_cap_cents[\s\S]*?cap_updated_at\s*=\s*now\(\)[\s\S]*?cap_updated_by_user_id\s*=\s*v_actor/i,
      );
    });

    it("GRANTs authenticated + service_role (internal impersonation guard makes authenticated safe)", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.update_byok_delegation_cap\(uuid,\s*int,\s*int,\s*uuid\)\s+FROM\s+PUBLIC,\s*anon/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.update_byok_delegation_cap\(uuid,\s*int,\s*int,\s*uuid\)\s+TO\s+authenticated,\s*service_role/i,
      );
    });
  });

  // ---------------------------------------------------------------
  // down migration
  // ---------------------------------------------------------------
  describe("down migration", () => {
    it("DROPs the new overloads + cap RPC", () => {
      expect(down).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.remove_workspace_member\(uuid,\s*uuid,\s*uuid\)/i,
      );
      expect(down).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.update_workspace_member_role\(uuid,\s*uuid,\s*text,\s*uuid\)/i,
      );
      expect(down).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.update_byok_delegation_cap\(uuid,\s*int,\s*int,\s*uuid\)/i,
      );
    });

    it("recreates the 2-arg remove + 3-arg role forms", () => {
      expect(down).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.remove_workspace_member\(\s*p_workspace_id\s+uuid\s*,\s*p_user_id\s+uuid\s*\)/i,
      );
      expect(down).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.update_workspace_member_role\(\s*p_workspace_id\s+uuid\s*,\s*p_user_id\s+uuid\s*,\s*p_new_role\s+text\s*\)/i,
      );
    });
  });
});

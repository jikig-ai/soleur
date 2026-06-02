import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 092_transfer_ownership_caller_override.sql.
//
// Pins the SQL invariants of the transfer-ownership service-role fix (#4765)
// so a future edit that drops them is caught at PR-time without requiring a
// live Supabase. Structural pattern mirrors 091-rename-organization.test.ts
// (readFileSync + regex on source). Per learning
// 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md: vitest mocks
// resolve .rpc to vi.fn() and CANNOT catch a GRANT mismatch, so this
// migration-shape regex test is the canonical plan-time grant gate (AC3).
//
// Covers:
//   - AC1 (signature): transfer_workspace_ownership widened to 4-arg with
//     p_caller_user_id uuid DEFAULT NULL.
//   - AC2 (caller resolution): COALESCE(p_caller_user_id, auth.uid()) so the
//     service-role caller (auth.uid() NULL) resolves to the route-verified id.
//   - AC3 (grant flip): REVOKE from PUBLIC/anon/authenticated + GRANT to
//     service_role ONLY (the forgeable override must be unreachable by
//     authenticated via PostgREST — same P1 class fixed in #4762).
//   - AC4 (drop old overload): the 075 3-arg authenticated-granted form is
//     DROPped so no orphaned reachable overload remains.
//   - AC5 (definer hygiene): LANGUAGE plpgsql + SECURITY DEFINER + pinned
//     search_path.
//   - AC6 (body invariants): every 075 behavioral arm survives unchanged.
//   - AC8 (down migration): drops the 4-arg form, recreates the 075 3-arg form.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/092_transfer_ownership_caller_override.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/092_transfer_ownership_caller_override.down.sql",
);

describe("migration 092_transfer_ownership_caller_override", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const down = readFileSync(DOWN_PATH, "utf8");
  // Strip line comments so prose mentioning "auth.uid()" / "authenticated"
  // doesn't satisfy executable-code assertions.
  const executable = sql.replace(/--[^\n]*/g, "");

  const fnBody = (src: string) =>
    src.match(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.transfer_workspace_ownership\([\s\S]*?\$\$([\s\S]*?)\$\$;/i,
    );

  describe("AC1: signature widened to 4-arg", () => {
    it("declares transfer_workspace_ownership(p_workspace_id, p_new_owner_user_id, p_attestation_text, p_caller_user_id uuid DEFAULT NULL)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.transfer_workspace_ownership\(\s*p_workspace_id\s+uuid\s*,\s*p_new_owner_user_id\s+uuid\s*,\s*p_attestation_text\s+text\s*,\s*p_caller_user_id\s+uuid\s+DEFAULT\s+NULL\s*\)/i,
      );
    });
  });

  describe("AC2: caller resolved via COALESCE", () => {
    it("resolves caller via COALESCE(p_caller_user_id, auth.uid()) for service-role invocation", () => {
      const body = fnBody(executable);
      expect(body).not.toBeNull();
      expect(body![1]).toMatch(
        /v_caller_user_id\s+uuid\s*:=\s*COALESCE\(\s*p_caller_user_id\s*,\s*auth\.uid\(\)\s*\)/i,
      );
    });
  });

  describe("AC3: grant flipped to service_role-only", () => {
    it("REVOKEs ALL from PUBLIC, anon, authenticated on the 4-arg signature", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.transfer_workspace_ownership\(uuid,\s*uuid,\s*text,\s*uuid\)\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
    });

    it("GRANTs EXECUTE to service_role on the 4-arg signature", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.transfer_workspace_ownership\(uuid,\s*uuid,\s*text,\s*uuid\)\s+TO\s+service_role/i,
      );
    });

    it("does NOT GRANT the 4-arg signature to authenticated (forgeable override must be service-role-only)", () => {
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.transfer_workspace_ownership\(uuid,\s*uuid,\s*text,\s*uuid\)\s+TO\s+authenticated/i,
      );
    });
  });

  describe("AC4: old 3-arg overload dropped", () => {
    it("DROPs the 075 3-arg authenticated-granted form", () => {
      expect(executable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.transfer_workspace_ownership\(uuid,\s*uuid,\s*text\)\s*;/i,
      );
    });
  });

  describe("AC5: SECURITY DEFINER hygiene preserved", () => {
    it("recreates the function as LANGUAGE plpgsql, SECURITY DEFINER, pinned search_path", () => {
      const fn = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.transfer_workspace_ownership\([\s\S]*?AS\s+\$\$/i,
      );
      expect(fn).not.toBeNull();
      expect(fn![0]).toMatch(/LANGUAGE\s+plpgsql/i);
      expect(fn![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(fn![0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });

    it("every SECURITY DEFINER function in the migration pins search_path", () => {
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

  describe("AC6: every 075 behavioral arm preserved", () => {
    const body = fnBody(executable);

    it("preserves the owner-gate (role='owner' FOR UPDATE) raising 42501", () => {
      expect(body).not.toBeNull();
      expect(body![1]).toMatch(/role\s*=\s*'owner'/i);
      expect(body![1]).toMatch(/FOR\s+UPDATE/i);
      expect(body![1]).toMatch(/caller is not an owner/i);
      expect(body![1]).toMatch(/ERRCODE\s*=\s*'42501'/i);
    });

    it("preserves NULL-caller authentication gate raising 28000", () => {
      expect(body![1]).toMatch(/ERRCODE\s*=\s*'28000'/i);
    });

    it("preserves the self-transfer guard raising 22023", () => {
      expect(body![1]).toMatch(/cannot transfer ownership to self/i);
    });

    it("preserves target-not-member guard raising P0001", () => {
      expect(body![1]).toMatch(/target user is not a member/i);
      expect(body![1]).toMatch(/ERRCODE\s*=\s*'P0001'/i);
    });

    it("preserves target-already-owner guard", () => {
      expect(body![1]).toMatch(/target user is already the owner/i);
    });

    it("preserves attestation length validation (>= 16 chars)", () => {
      expect(body![1]).toMatch(/length\(p_attestation_text\)\s*<\s*16/i);
    });

    it("preserves the audit actor GUC set_config", () => {
      expect(body![1]).toMatch(
        /set_config\(\s*'workspace_audit\.actor_user_id'/i,
      );
    });

    it("preserves attestation insert + promote-before-demote ordering", () => {
      expect(body![1]).toMatch(
        /INSERT\s+INTO\s+public\.workspace_member_attestations/i,
      );
      // promote target (role='owner') appears before demote caller (role='member')
      const promoteIdx = body![1].search(/SET\s+role\s*=\s*'owner'/i);
      const demoteIdx = body![1].search(/SET\s+role\s*=\s*'member'/i);
      expect(promoteIdx).toBeGreaterThanOrEqual(0);
      expect(demoteIdx).toBeGreaterThan(promoteIdx);
    });

    it("preserves organizations.owner_user_id dual-write", () => {
      expect(body![1]).toMatch(
        /UPDATE\s+public\.organizations\s+SET\s+owner_user_id/i,
      );
    });

    it("preserves the workspace_member_removals revocation row", () => {
      expect(body![1]).toMatch(
        /INSERT\s+INTO\s+public\.workspace_member_removals/i,
      );
      expect(body![1]).toMatch(/ownership-transferred/i);
    });

    it("preserves the demoted-owner user_session_state clear", () => {
      expect(body![1]).toMatch(
        /UPDATE\s+public\.user_session_state[\s\S]*?current_organization_id\s*=\s*NULL/i,
      );
    });

    it("does NOT re-emit update_workspace_member_role or anonymise_organization_membership (single source of truth)", () => {
      expect(executable).not.toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.update_workspace_member_role/i,
      );
      expect(executable).not.toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_organization_membership/i,
      );
    });
  });

  describe("AC8: down migration", () => {
    it("drops the 4-arg form", () => {
      expect(down).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.transfer_workspace_ownership\(uuid,\s*uuid,\s*text,\s*uuid\)/i,
      );
    });

    it("recreates the 075 3-arg form granted to authenticated", () => {
      expect(down).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.transfer_workspace_ownership\(\s*p_workspace_id\s+uuid\s*,\s*p_new_owner_user_id\s+uuid\s*,\s*p_attestation_text\s+text\s*\)/i,
      );
      expect(down).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.transfer_workspace_ownership\(uuid,\s*uuid,\s*text\)\s+TO\s+authenticated/i,
      );
    });
  });
});

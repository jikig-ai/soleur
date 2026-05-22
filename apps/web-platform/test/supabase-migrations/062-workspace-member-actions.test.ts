import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 062_workspace_member_actions.sql.
//
// Pins the SQL invariants of feat-workspace-member-actions-audit (#4231)
// so a future edit that drops them is caught at PR-time without
// requiring a live Supabase. Live-behavior ACs (AC1, AC2, AC4, AC5–AC9)
// live in test/server/workspace-member-actions.integration.test.ts and
// run under TENANT_INTEGRATION_TEST=1.
//
// Covers:
//   - AC1a: prosrc grep — invite/remove/anonymise contain expected calls.
//   - AC1c: trigger body does NOT contain auth.uid() fallback (TR10a).
//   - AC4 structural: RLS-zero + named-role REVOKE matrix.
//   - AC9 structural: pg_cron schedule name + cadence + wrapper invocation.
//   - AC10 structural: down migration reverse-dependency DROP order.
//   - TR2: SECURITY DEFINER functions pin SET search_path = public, pg_temp.
//   - TR5: no CREATE INDEX CONCURRENTLY.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/062_workspace_member_actions.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/062_workspace_member_actions.down.sql",
);

describe("migration 062_workspace_member_actions (#4231)", () => {
  const sql = readFileSync(MIGRATION_PATH, "utf8");
  const down = readFileSync(DOWN_PATH, "utf8");
  // Strip line-comments before pattern checks so a regex like
  // /auth\.uid\(\)/ does not match commentary inside the trigger body.
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("table shape (FR1)", () => {
    it("creates public.workspace_member_actions", () => {
      expect(executable).toMatch(
        /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.workspace_member_actions/i,
      );
    });

    it("FKs target public.users(id) NOT auth.users(id) (P0-3 fix)", () => {
      // actor_user_id + target_user_id must reference public.users(id).
      expect(executable).toMatch(
        /actor_user_id\s+uuid\s+NULL\s+REFERENCES\s+public\.users\(id\)/i,
      );
      expect(executable).toMatch(
        /target_user_id\s+uuid\s+NULL\s+REFERENCES\s+public\.users\(id\)/i,
      );
      // Defensive: no auth.users(id) anywhere in column definitions.
      expect(executable).not.toMatch(/REFERENCES\s+auth\.users/i);
    });

    it("action_type CHECK admits added/removed/role_changed only", () => {
      expect(executable).toMatch(
        /action_type\s+text\s+NOT\s+NULL\s+CHECK\s*\(\s*action_type\s+IN\s*\(\s*'added'\s*,\s*'removed'\s*,\s*'role_changed'\s*\)\s*\)/i,
      );
    });

    it("created_at NOT NULL DEFAULT now() explicit (plan §1.3)", () => {
      expect(executable).toMatch(
        /created_at\s+timestamptz\s+NOT\s+NULL\s+DEFAULT\s+now\(\)/i,
      );
    });
  });

  describe("RLS posture (TR4)", () => {
    it("enables RLS on the table", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.workspace_member_actions\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
    });

    it("declares ZERO RLS policies on the table", () => {
      const policyBlock = executable.match(
        /CREATE\s+POLICY\s+\w+\s+ON\s+public\.workspace_member_actions/gi,
      );
      expect(policyBlock).toBeNull();
    });

    it("explicit REVOKE matrix from PUBLIC, anon, authenticated, service_role", () => {
      // Per learning 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.
      expect(executable).toMatch(
        /REVOKE\s+INSERT,\s*UPDATE,\s*DELETE,\s*SELECT\s+ON\s+TABLE\s+public\.workspace_member_actions\s+FROM\s+PUBLIC,\s*anon,\s*authenticated,\s*service_role/i,
      );
    });
  });

  describe("WORM trigger (FR6)", () => {
    it("defines workspace_member_actions_no_mutate pure-reject", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_member_actions_no_mutate\(\)\s+RETURNS\s+trigger/i,
      );
      expect(executable).toMatch(
        /RAISE\s+EXCEPTION\s+'workspace_member_actions[^']*WORM[^']*'[\s\S]*?USING\s+ERRCODE\s*=\s*'P0001'/i,
      );
    });

    it("attaches BEFORE UPDATE + BEFORE DELETE triggers", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_member_actions_no_update[\s\S]*?BEFORE\s+UPDATE\s+ON\s+public\.workspace_member_actions/i,
      );
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_member_actions_no_delete[\s\S]*?BEFORE\s+DELETE\s+ON\s+public\.workspace_member_actions/i,
      );
    });
  });

  describe("AFTER trigger on workspace_members (FR2)", () => {
    it("defines workspace_members_audit SECURITY DEFINER + pinned search_path (TR2)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_members_audit\(\)\s+RETURNS\s+trigger[\s\S]*?LANGUAGE\s+plpgsql[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });

    it("AC1c: trigger body does NOT contain auth.uid() fallback (TR10a)", () => {
      // Extract the function body and assert auth.uid() is absent.
      const triggerBody = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_members_audit\(\)[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(triggerBody).not.toBeNull();
      expect(triggerBody![1]).not.toMatch(/auth\.uid\(\)/i);
    });

    it("uses NULLIF(current_setting(...), '')::uuid wrapped in EXCEPTION (TR10a + P0-4)", () => {
      expect(executable).toMatch(
        /NULLIF\s*\(\s*current_setting\(\s*'workspace_audit\.actor_user_id'/i,
      );
      expect(executable).toMatch(/WHEN\s+invalid_text_representation/i);
    });

    it("uses NEW.attestation_id directly (P1-4 — no race lookup)", () => {
      // Should reference NEW.attestation_id, NOT query workspace_member_attestations.
      const triggerBody = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.workspace_members_audit\(\)[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(triggerBody![1]).toMatch(/NEW\.attestation_id/);
      // No SELECT from workspace_member_attestations inside the body.
      expect(triggerBody![1]).not.toMatch(
        /FROM\s+(?:public\.)?workspace_member_attestations/i,
      );
    });

    it("TR13: orphan-actor RAISE LOG when session_user='authenticated'", () => {
      expect(executable).toMatch(/audit_orphan_actor/);
      expect(executable).toMatch(/session_user\s*=\s*'authenticated'/i);
    });

    it("attaches AFTER INSERT OR UPDATE OR DELETE trigger to workspace_members", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_members_audit_trigger[\s\S]*?AFTER\s+INSERT\s+OR\s+UPDATE\s+OR\s+DELETE\s+ON\s+public\.workspace_members[\s\S]*?FOR\s+EACH\s+ROW/i,
      );
    });
  });

  describe("RPC bodies (FR4, FR5, FR7)", () => {
    it("list_workspace_member_actions SECURITY DEFINER with cursor pagination", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.list_workspace_member_actions\(\s*p_workspace_id\s+uuid,\s*p_limit\s+int\s+DEFAULT\s+50,\s*p_cursor\s+timestamptz\s+DEFAULT\s+NULL\s*\)/i,
      );
      // Owner-check JOIN uses workspaces.organization_id (drift item #3).
      expect(executable).toMatch(
        /JOIN\s+public\.workspaces\s+w\s+ON\s+w\.organization_id\s*=\s*o\.id/i,
      );
      expect(executable).toMatch(
        /ORDER\s+BY\s+created_at\s+DESC,\s*id\s+DESC/i,
      );
    });

    it("anonymise_workspace_member_actions SECURITY DEFINER with replica-role bypass", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_workspace_member_actions\(p_user_id\s+uuid\)\s+RETURNS\s+int/i,
      );
      // Body must contain SET LOCAL session_replication_role = 'replica' and RESET.
      const anonBody = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_workspace_member_actions\(p_user_id\s+uuid\)[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(anonBody![1]).toMatch(
        /SET\s+LOCAL\s+session_replication_role\s*=\s*'replica'/i,
      );
      expect(anonBody![1]).toMatch(/RESET\s+session_replication_role/i);
      expect(anonBody![1]).toMatch(
        /UPDATE\s+public\.workspace_member_actions[\s\S]*?SET\s+actor_user_id\s*=\s*NULL[\s\S]*?target_user_id\s*=\s*NULL/i,
      );
    });

    it("purge_workspace_member_actions SECURITY DEFINER with 7y DELETE + RAISE LOG (TR12)", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.purge_workspace_member_actions\(\)\s+RETURNS\s+int/i,
      );
      const purgeBody = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.purge_workspace_member_actions\(\)[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(purgeBody![1]).toMatch(
        /SET\s+LOCAL\s+session_replication_role\s*=\s*'replica'/i,
      );
      expect(purgeBody![1]).toMatch(
        /DELETE\s+FROM\s+public\.workspace_member_actions\s+WHERE\s+created_at\s*<\s*now\(\)\s*-\s*interval\s+'7\s+years'/i,
      );
      expect(purgeBody![1]).toMatch(/RAISE\s+LOG\s+'audit_retention_purge/i);
    });
  });

  describe("mig 058 RPC re-CREATEs (FR3 + P0-5 + P1-2)", () => {
    it("AC1a: invite_workspace_member contains set_config('workspace_audit.actor_user_id', ...)", () => {
      const inviteBody = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.invite_workspace_member[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(inviteBody).not.toBeNull();
      // P0-5: use set_config(name, value, is_local), NOT SET LOCAL <key> = expr.
      expect(inviteBody![1]).toMatch(
        /set_config\(\s*'workspace_audit\.actor_user_id'\s*,\s*COALESCE\(auth\.uid\(\)::text,\s*''\),\s*true\s*\)/i,
      );
    });

    it("AC1a: remove_workspace_member contains the same set_config prepend", () => {
      const removeBody = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.remove_workspace_member[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(removeBody).not.toBeNull();
      expect(removeBody![1]).toMatch(
        /set_config\(\s*'workspace_audit\.actor_user_id'\s*,\s*COALESCE\(auth\.uid\(\)::text,\s*''\),\s*true\s*\)/i,
      );
    });

    it("AC1a: anonymise_workspace_members contains SET LOCAL session_replication_role='replica' (P1-2)", () => {
      const anonMembersBody = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_workspace_members\(p_user_id\s+uuid\)[\s\S]*?\$\$([\s\S]*?)\$\$;/i,
      );
      expect(anonMembersBody).not.toBeNull();
      expect(anonMembersBody![1]).toMatch(
        /SET\s+LOCAL\s+session_replication_role\s*=\s*'replica'/i,
      );
      expect(anonMembersBody![1]).toMatch(/RESET\s+session_replication_role/i);
    });
  });

  describe("backfill block (FR8, P1-1)", () => {
    it("LOCK TABLE workspace_members IN SHARE MODE", () => {
      expect(executable).toMatch(
        /LOCK\s+TABLE\s+public\.workspace_members\s+IN\s+SHARE\s+MODE/i,
      );
    });

    it("SET LOCAL session_replication_role='replica' before backfill INSERT", () => {
      expect(executable).toMatch(
        /SET\s+LOCAL\s+session_replication_role\s*=\s*'replica'/i,
      );
    });

    it("idempotent NOT EXISTS discriminator on (workspace_id, target_user_id, 'added')", () => {
      expect(executable).toMatch(
        /WHERE\s+NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.workspace_member_actions\s+a/i,
      );
    });
  });

  describe("pg_cron schedule (FR7, AC9)", () => {
    it("schedules workspace-member-actions-retention daily at 04:00 UTC", () => {
      expect(executable).toMatch(
        /SELECT\s+cron\.schedule\(\s*'workspace-member-actions-retention'\s*,\s*'0 4 \* \* \*'/i,
      );
    });

    it("invokes purge_workspace_member_actions wrapper (NOT direct DELETE)", () => {
      expect(executable).toMatch(
        /cron\.schedule\([\s\S]*?\$\$SELECT\s+public\.purge_workspace_member_actions\(\)\$\$/i,
      );
    });
  });

  describe("indexes (TR6)", () => {
    it("workspace_id + created_at DESC composite (owner-list hot path)", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?workspace_member_actions_workspace_created_idx\s+ON\s+public\.workspace_member_actions\s*\(workspace_id,\s*created_at\s+DESC\)/i,
      );
    });

    it("target_user_id partial (Art. 17 anonymise sweep)", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?workspace_member_actions_target_idx\s+ON\s+public\.workspace_member_actions\s*\(target_user_id\)\s+WHERE\s+target_user_id\s+IS\s+NOT\s+NULL/i,
      );
    });

    it("TR5: no CREATE INDEX CONCURRENTLY (Supabase wraps each migration in TX)", () => {
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });

  describe("SECURITY DEFINER hygiene (TR2)", () => {
    it("every SECURITY DEFINER function pins SET search_path = public, pg_temp", () => {
      const definerFns = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION[\s\S]*?SECURITY\s+DEFINER[\s\S]*?(?=\$\$)/gi,
      );
      expect(definerFns).not.toBeNull();
      for (const fn of definerFns!) {
        expect(
          fn,
          `SECURITY DEFINER function missing SET search_path = public, pg_temp:\n${fn.slice(0, 200)}`,
        ).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
      }
    });
  });

  describe("AC10: down migration reverse-dependency DROP order", () => {
    it("unschedules cron job before dropping wrapper RPCs", () => {
      const cronIdx = down.search(/cron\.unschedule/i);
      const purgeIdx = down.search(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.purge_workspace_member_actions/i,
      );
      expect(cronIdx).toBeGreaterThanOrEqual(0);
      expect(purgeIdx).toBeGreaterThan(cronIdx);
    });

    it("drops wrapper RPCs before triggers", () => {
      const anonIdx = down.search(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.anonymise_workspace_member_actions/i,
      );
      const triggerIdx = down.search(
        /DROP\s+TRIGGER\s+IF\s+EXISTS\s+workspace_members_audit_trigger/i,
      );
      expect(anonIdx).toBeGreaterThanOrEqual(0);
      expect(triggerIdx).toBeGreaterThan(anonIdx);
    });

    it("drops both triggers before dropping the table", () => {
      const wormIdx = down.search(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.workspace_member_actions_no_mutate/i,
      );
      const tableIdx = down.search(
        /DROP\s+TABLE\s+IF\s+EXISTS\s+public\.workspace_member_actions/i,
      );
      expect(wormIdx).toBeGreaterThanOrEqual(0);
      expect(tableIdx).toBeGreaterThan(wormIdx);
    });

    it("does NOT revert mig 058 RPC bodies (P0-4 — set_config calls are harmless no-ops once trigger is gone)", () => {
      expect(down).not.toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.invite_workspace_member/i,
      );
      expect(down).not.toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.remove_workspace_member/i,
      );
    });
  });
});

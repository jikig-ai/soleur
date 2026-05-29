import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 084_byok_delegation_withdrawals.sql
// (feat-byok-delegation-consent, #4625, Phase 3). Offline lint — live
// WORM/RLS/predicate behavior is TENANT_INTEGRATION_TEST=1.
//
// Withdrawal = gate-side, append-only. The withdraw RPC writes ONLY a
// byok_delegation_withdrawals WORM row; the resolver gains a second clause
// `AND NOT EXISTS(withdrawal newer than the latest current-version
// acceptance)`. It does NOT set byok_delegations.revoked_at (the 064 WORM
// trigger requires the 3-field revoke flip together, and revocation_reason
// has no consent_withdrawn value). A per-turn re-gate in the cap RPC stops
// in-flight billing within one turn (debits grantee).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/084_byok_delegation_withdrawals.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/084_byok_delegation_withdrawals.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

describe("migration 084_byok_delegation_withdrawals", () => {
  describe("header", () => {
    it("carries LAWFUL_BASIS Art. 7(3) + RETENTION 7 years + #4625", () => {
      expect(sql).toMatch(/#4625/);
      expect(sql).toMatch(/Art\.\s*7\(3\)/);
      expect(sql).toMatch(/RETENTION:\s*7\s*years/i);
    });
  });

  describe("table shape (AC5/AC14)", () => {
    const tbl = () =>
      executable.match(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.byok_delegation_withdrawals\s*\(([\s\S]*?)\n\);/i)![1];

    it("CREATEs public.byok_delegation_withdrawals", () => {
      expect(executable).toMatch(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.byok_delegation_withdrawals\s*\(/i);
    });
    it("user_id is NULLABLE (anonymise sets NULL — AC14) and ON DELETE RESTRICT", () => {
      // NOT NULL would make the Art. 17 anonymise UPDATE-to-NULL fail.
      expect(tbl()).toMatch(/user_id\s+uuid\s+(?:NULL\s+)?REFERENCES\s+public\.users\(id\)\s+ON\s+DELETE\s+RESTRICT/i);
      expect(tbl()).not.toMatch(/user_id\s+uuid\s+NOT\s+NULL/i);
    });
    it("delegation_id NOT NULL ON DELETE RESTRICT", () => {
      expect(tbl()).toMatch(/delegation_id\s+uuid\s+NOT\s+NULL\s+REFERENCES\s+public\.byok_delegations\(id\)\s+ON\s+DELETE\s+RESTRICT/i);
    });
    it("has withdrawn_at, side_letter_version, ip_hash, user_agent, retention_until(7y)", () => {
      expect(tbl()).toMatch(/withdrawn_at\s+timestamptz/i);
      expect(tbl()).toMatch(/side_letter_version\s+text/i);
      expect(tbl()).toMatch(/ip_hash\s+text/i);
      expect(tbl()).toMatch(/user_agent\s+text/i);
      expect(tbl()).toMatch(/retention_until\s+timestamptz[\s\S]*?7\s*years/i);
    });
    it("has NO UNIQUE(user_id, delegation_id) — append-only event log (non-terminal + Art. 17)", () => {
      expect(executable).not.toMatch(/UNIQUE\s*\(\s*user_id\s*,\s*delegation_id\s*\)/i);
    });
  });

  describe("WORM triggers (no_update / no_delete)", () => {
    it("defines the no_mutate trigger fn with search_path pinned", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.byok_delegation_withdrawals_no_mutate\(\)[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });
    it("creates BEFORE UPDATE and BEFORE DELETE triggers", () => {
      expect(executable).toMatch(/CREATE\s+TRIGGER\s+\w*no_update[\s\S]*?BEFORE\s+UPDATE\s+ON\s+public\.byok_delegation_withdrawals/i);
      expect(executable).toMatch(/CREATE\s+TRIGGER\s+\w*no_delete[\s\S]*?BEFORE\s+DELETE\s+ON\s+public\.byok_delegation_withdrawals/i);
    });
  });

  describe("RLS (AC13 defense-in-depth)", () => {
    it("enables RLS", () => {
      expect(executable).toMatch(/ALTER\s+TABLE\s+public\.byok_delegation_withdrawals\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i);
    });
    it("SELECT policy scoped to user_id = auth.uid()", () => {
      expect(executable).toMatch(/FOR\s+SELECT[\s\S]*?user_id\s*=\s*auth\.uid\(\)/i);
    });
    it("INSERT WITH CHECK constrains delegation to caller's grantee rows", () => {
      const m = executable.match(/FOR\s+INSERT[\s\S]*?WITH\s+CHECK\s*\(([\s\S]*?)\);/i);
      expect(m, "no INSERT WITH CHECK policy").not.toBeNull();
      expect(m![1]).toMatch(/user_id\s*=\s*auth\.uid\(\)/i);
      expect(m![1]).toMatch(/delegation_id\s+IN\s*\(\s*SELECT\s+id\s+FROM\s+(?:public\.)?byok_delegations\s+WHERE\s+grantee_user_id\s*=\s*auth\.uid\(\)/i);
    });
  });

  describe("withdraw_byok_delegation_consent RPC (AC13)", () => {
    const fn = () =>
      executable.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.withdraw_byok_delegation_consent\s*\(([^)]*)\)[\s\S]*?\$\$;/i)![0];
    it("takes NO p_user_id param (derives auth.uid() — SS-F3)", () => {
      const params = executable.match(/withdraw_byok_delegation_consent\s*\(([^)]*)\)/i)![1];
      expect(params).not.toMatch(/p_user_id/i);
      expect(params).toMatch(/p_delegation_id\s+uuid/i);
    });
    it("is SECURITY DEFINER, derives auth.uid(), grantee-only check, inserts WORM row", () => {
      const body = fn();
      expect(body).toMatch(/SECURITY\s+DEFINER/i);
      expect(body).toMatch(/auth\.uid\(\)/);
      expect(body).toMatch(/grantee_user_id\s*=\s*v_caller|grantee_user_id\s*=\s*auth\.uid\(\)/i);
      expect(body).toMatch(/INSERT\s+INTO\s+public\.byok_delegation_withdrawals/i);
      // Must NOT touch byok_delegations (no revoked_at write).
      expect(body).not.toMatch(/UPDATE\s+public\.byok_delegations/i);
    });
    it("GRANT EXECUTE to authenticated (invoked as the user)", () => {
      expect(executable).toMatch(/GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.withdraw_byok_delegation_consent\(uuid\)\s*TO\s+authenticated/i);
    });
  });

  describe("resolver second clause — version-agnostic NOT EXISTS(withdrawal) (AC5)", () => {
    const fn = () =>
      executable.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.resolve_byok_key_owner[\s\S]*?\$\$;/i)![0];
    it("keeps the acceptance EXISTS clause from 083", () => {
      expect(fn()).toMatch(/EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.byok_delegation_acceptances/i);
    });
    it("adds NOT EXISTS(withdrawal) using COALESCE(max(accepted_at), withdrawn_at) and >=", () => {
      const body = fn();
      expect(body).toMatch(/NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.byok_delegation_withdrawals/i);
      expect(body).toMatch(/w\.withdrawn_at\s*>=\s*COALESCE/i);
      expect(body).toMatch(/max\(\s*a2?\.accepted_at\s*\)/i);
    });
  });

  describe("per-turn consent re-gate in cap RPC (AC5)", () => {
    const fn = () =>
      executable.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.check_and_record_byok_delegation_use[\s\S]*?\$\$;/i)![0];
    it("extends attribution_shift_reason enum with consent_withdrawn", () => {
      expect(executable).toMatch(/attribution_shift_reason[\s\S]*?IN\s*\([^)]*'consent_withdrawn'[^)]*\)/i);
    });
    it("re-gate checks a withdrawal newer than latest acceptance and debits grantee", () => {
      const body = fn();
      expect(body).toMatch(/byok_delegation_withdrawals/i);
      expect(body).toMatch(/'consent_withdrawn'/);
      // founder_id debit uses the caller (grantee), like revoked_post_grace.
      expect(body).toMatch(/p_caller_user_id/);
      expect(body).toMatch(/byok_delegations:consent_withdrawn/i);
    });
  });

  describe("anonymise_byok_delegation_withdrawals (AC7/AC14)", () => {
    it("is SECURITY DEFINER and SET LOCAL session_replication_role = replica in its own body", () => {
      const m = executable.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.anonymise_byok_delegation_withdrawals\s*\(\s*p_user_id\s+uuid\s*\)[\s\S]*?\$\$;/i);
      expect(m, "anonymise RPC missing").not.toBeNull();
      expect(m![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(m![0]).toMatch(/SET\s+LOCAL\s+session_replication_role\s*=\s*'replica'/i);
      expect(m![0]).toMatch(/SET\s+user_id\s*=\s*NULL/i);
    });
  });

  describe("transaction safety + down", () => {
    it("wraps in BEGIN/COMMIT", () => {
      expect(executable).toMatch(/BEGIN;/);
      expect(executable).toMatch(/COMMIT;/);
    });
    it("down drops table + RPCs and restores cap RPC + resolver enum", () => {
      expect(downExecutable).toMatch(/DROP\s+TABLE\s+IF\s+EXISTS\s+public\.byok_delegation_withdrawals\s+CASCADE/i);
      expect(downExecutable).toMatch(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.withdraw_byok_delegation_consent\(uuid\)/i);
      expect(downExecutable).toMatch(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.anonymise_byok_delegation_withdrawals\(uuid\)/i);
      // resolver restored to 083 form (acceptance gate kept, withdrawal clause gone)
      const m = downExecutable.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.resolve_byok_key_owner[\s\S]*?\$\$;/i);
      expect(m).not.toBeNull();
      expect(m![0]).not.toMatch(/byok_delegation_withdrawals/i);
    });
  });
});

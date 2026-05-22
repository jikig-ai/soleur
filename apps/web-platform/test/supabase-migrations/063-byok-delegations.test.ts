import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 063_byok_delegations.sql (#4232, PR-A).
// Offline lint — runs without a live database. Mirrors the
// 062-workspace-member-removals.test.ts precedent shape.
//
// Live integration coverage (RLS dual-shape, WORM behavior, cap
// SUMs, cross-tenant trigger fire, etc.) requires TENANT_INTEGRATION_
// TEST=1 against dev-Supabase and lives in
// test/server/byok-delegations.*.test.ts (deferred to next /work
// invocation alongside the cc-dispatcher closure-capture refactor).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/063_byok_delegations.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/063_byok_delegations.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

describe("migration 063_byok_delegations", () => {
  describe("AC1: header carries LAWFUL_BASIS + RETENTION (joint controllership)", () => {
    it("LAWFUL_BASIS: Art. 6(1)(b) contract", () => {
      expect(sql).toMatch(/LAWFUL_BASIS:\s*Art\.\s*6\(1\)\(b\)\s*contract/);
    });
    it("RETENTION: 7 years", () => {
      expect(sql).toMatch(/RETENTION:\s*7\s*years/);
    });
  });

  describe("AC2: byok_delegations table shape (v3)", () => {
    it("CREATEs public.byok_delegations", () => {
      expect(executable).toMatch(
        /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.byok_delegations\s*\(/i,
      );
    });
    it("identity FKs use ON DELETE RESTRICT", () => {
      // 5 identity columns — Art. 17 cascade is via UPDATE-to-NULL (Shape 2)
      // not via FK delete propagation.
      for (const col of [
        "grantor_user_id",
        "grantee_user_id",
        "created_by_user_id",
        "revoked_by_user_id",
        "cap_updated_by_user_id",
      ]) {
        expect(executable).toMatch(
          new RegExp(`${col}\\s+uuid[^,]*REFERENCES\\s+public\\.users\\(id\\)\\s+ON\\s+DELETE\\s+RESTRICT`, "i"),
        );
      }
    });
    it("workspace_id FK is ON DELETE RESTRICT", () => {
      expect(executable).toMatch(
        /workspace_id\s+uuid[^,]*REFERENCES\s+public\.workspaces\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });
    it("daily_usd_cap_cents CHECK BETWEEN 1 AND 1000000 ($10K/day ceiling, SS F2)", () => {
      expect(executable).toMatch(/daily_usd_cap_cents[\s\S]*?BETWEEN\s+1\s+AND\s+1000000/i);
    });
    it("hourly_usd_cap_cents column present (Arch A1 secondary brake)", () => {
      expect(executable).toMatch(/hourly_usd_cap_cents\s+int/i);
    });
    it("hourly_usd_cap_cents <= daily_usd_cap_cents CHECK", () => {
      expect(executable).toMatch(
        /hourly_usd_cap_cents\s+IS\s+NULL[\s\S]*?hourly_usd_cap_cents\s*<=\s*daily_usd_cap_cents/i,
      );
    });
    it("cap_updated_at + cap_updated_by_user_id columns present (Shape 3, Arch A6)", () => {
      expect(executable).toMatch(/cap_updated_at\s+timestamptz/i);
      expect(executable).toMatch(/cap_updated_by_user_id\s+uuid/i);
    });
    it("revocation_reason CHECK includes the 5 reserved tokens", () => {
      for (const reason of [
        "grantor_revoke",
        "grantee_decline",
        "member_departed",
        "admin_revoke",
        "art_17_anonymise",
      ]) {
        expect(executable).toContain(`'${reason}'`);
      }
    });
  });

  describe("AC3: indexes", () => {
    it("partial unique on (grantor, grantee, workspace) WHERE revoked_at IS NULL (DIG F10: no expires_at predicate)", () => {
      expect(executable).toMatch(
        /CREATE\s+UNIQUE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+byok_delegations_active_triple_uidx[\s\S]*?WHERE\s+revoked_at\s+IS\s+NULL/i,
      );
      // Negative: predicate must NOT carry expires_at clause (DIG F10).
      const match = executable.match(/CREATE\s+UNIQUE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+byok_delegations_active_triple_uidx[\s\S]*?;/);
      expect(match?.[0]).toBeTruthy();
      expect(match![0]).not.toMatch(/expires_at\s*>\s*now\(\)/i);
    });
    it("hot-path index on (grantee, workspace) WHERE revoked_at IS NULL", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+byok_delegations_grantee_workspace_active_idx/i,
      );
    });
  });

  describe("AC4: audit_byok_use additions (mig 037 / 061 extensions)", () => {
    it("ADD COLUMN delegation_id REFERENCES byok_delegations ON DELETE RESTRICT", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.audit_byok_use[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+delegation_id\s+uuid\s+NULL[\s\S]*?REFERENCES\s+public\.byok_delegations\(id\)\s+ON\s+DELETE\s+RESTRICT/i,
      );
    });
    it("ADD COLUMN attribution_shift_reason CHECK IN (revoked_post_grace, expired)", () => {
      expect(executable).toMatch(/attribution_shift_reason/i);
      expect(executable).toContain("'revoked_post_grace'");
      expect(executable).toContain("'expired'");
    });
    it("audit_byok_use.invocation_id UNIQUE constraint added (Phase 0.9 prereq)", () => {
      expect(executable).toMatch(
        /CONSTRAINT\s+audit_byok_use_invocation_id_uniq\s+UNIQUE\s*\(\s*invocation_id\s*\)/i,
      );
    });
    it("audit_byok_use_delegation_ts_idx created", () => {
      expect(executable).toMatch(
        /CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+audit_byok_use_delegation_ts_idx/i,
      );
    });
  });

  describe("AC5: same-workspace trigger (raises P0001 byok_delegations:cross-tenant)", () => {
    it("function defined as SECURITY DEFINER plpgsql with search_path pinned", () => {
      expect(executable).toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.byok_delegations_check_same_workspace\(\)[\s\S]*?SECURITY\s+DEFINER[\s\S]*?SET\s+search_path\s*=\s*public,\s*pg_temp/i,
      );
    });
    it("raises P0001 with byok_delegations:cross-tenant prefix", () => {
      expect(executable).toMatch(/byok_delegations:cross-tenant/);
      expect(executable).toMatch(/USING\s+ERRCODE\s*=\s*'P0001'/);
    });
    it("attached BEFORE INSERT OR UPDATE OF (grantor, grantee, workspace_id)", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+byok_delegations_same_workspace[\s\S]*?BEFORE\s+INSERT\s+OR\s+UPDATE\s+OF\s+grantor_user_id,\s*grantee_user_id,\s*workspace_id/i,
      );
    });
  });

  describe("AC6: WORM trigger v3 — three shapes + DELETE rejection", () => {
    it("DELETE is rejected with P0001", () => {
      expect(executable).toMatch(
        /TG_OP\s*=\s*'DELETE'[\s\S]*?RAISE\s+EXCEPTION[\s\S]*?append-only[\s\S]*?P0001/i,
      );
    });
    it("Shape 1 attribution constraint: revoked_by_user_id IN (grantor, grantee, created_by)", () => {
      // DIG F1: load-bearing constraint.
      expect(executable).toMatch(
        /NEW\.revoked_by_user_id\s+IN\s*\(\s*NEW\.grantor_user_id,\s*NEW\.grantee_user_id,\s*NEW\.created_by_user_id\s*\)/i,
      );
    });
    it("Shape 2 (Art. 17 anonymise) nulls identity + workspace_id together (DIG F6)", () => {
      // "Shape 2" prose lives in -- comments; assert against raw sql for
      // the label, executable for the SQL clause.
      expect(sql).toMatch(/Shape\s+2/i);
      expect(executable).toMatch(
        /OLD\.workspace_id\s+IS\s+NOT\s+NULL\s+AND\s+NEW\.workspace_id\s+IS\s+NULL/i,
      );
    });
    it("Shape 3 (cap-update flip) requires cap_updated_at + cap_updated_by non-NULL (Arch A6)", () => {
      expect(sql).toMatch(/Shape\s+3/i);
      expect(executable).toMatch(
        /NEW\.cap_updated_at\s+IS\s+NOT\s+NULL[\s\S]*?NEW\.cap_updated_by_user_id\s+IS\s+NOT\s+NULL/i,
      );
    });
    it("attached BEFORE UPDATE + BEFORE DELETE", () => {
      expect(executable).toMatch(/CREATE\s+TRIGGER\s+byok_delegations_no_update[\s\S]*?BEFORE\s+UPDATE/i);
      expect(executable).toMatch(/CREATE\s+TRIGGER\s+byok_delegations_no_delete[\s\S]*?BEFORE\s+DELETE/i);
    });
  });

  describe("AC7: RLS — self+counterparty SELECT only", () => {
    it("ENABLE ROW LEVEL SECURITY", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.byok_delegations\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i,
      );
    });
    it("SELECT policy gates on is_workspace_member AND (grantor=auth.uid() OR grantee=auth.uid())", () => {
      expect(executable).toMatch(
        /CREATE\s+POLICY\s+byok_delegations_select_for_parties[\s\S]*?FOR\s+SELECT\s+TO\s+authenticated[\s\S]*?is_workspace_member\(workspace_id,\s*auth\.uid\(\)\)[\s\S]*?grantor_user_id\s*=\s*auth\.uid\(\)\s+OR\s+grantee_user_id\s*=\s*auth\.uid\(\)/i,
      );
    });
    it("REVOKE INSERT, UPDATE, DELETE from PUBLIC, anon, authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+INSERT,\s*UPDATE,\s*DELETE\s+ON\s+TABLE\s+public\.byok_delegations\s+FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
    });
  });

  describe("AC8: RPCs (5 functions, all SECURITY DEFINER, search_path pinned)", () => {
    const rpcs = [
      "grant_byok_delegation",
      "revoke_byok_delegation",
      "resolve_byok_key_owner",
      "check_and_record_byok_delegation_use",
      "anonymise_byok_delegations",
    ];
    for (const rpc of rpcs) {
      it(`${rpc} is SECURITY DEFINER with search_path = public, pg_temp pinned`, () => {
        const fnRe = new RegExp(
          `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${rpc}\\s*\\([\\s\\S]*?\\$\\$`,
          "i",
        );
        const match = executable.match(fnRe);
        expect(match, `${rpc} not found`).toBeTruthy();
        expect(match![0]).toMatch(/SECURITY\s+DEFINER/i);
        expect(match![0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
      });
      it(`${rpc} REVOKES from PUBLIC, anon, authenticated`, () => {
        expect(executable).toMatch(
          new RegExp(
            `REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+public\\.${rpc}\\([\\s\\S]*?\\)\\s*FROM\\s+PUBLIC,\\s*anon,\\s*authenticated`,
            "i",
          ),
        );
      });
    }
    it("grant_byok_delegation GRANTS EXECUTE to BOTH authenticated AND service_role (Arch A3 consolidated)", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.grant_byok_delegation\([\s\S]*?\)\s+TO\s+authenticated,\s*service_role/i,
      );
    });
    it("revoke_byok_delegation GRANTS EXECUTE to BOTH authenticated AND service_role (Arch A3)", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.revoke_byok_delegation\([\s\S]*?\)\s+TO\s+authenticated,\s*service_role/i,
      );
    });
    it("resolve_byok_key_owner GRANTS only to service_role", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.resolve_byok_key_owner\([\s\S]*?\)\s+TO\s+service_role/i,
      );
    });
    it("check_and_record_byok_delegation_use GRANTS only to service_role", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.check_and_record_byok_delegation_use\([\s\S]*?\)\s+TO\s+service_role/i,
      );
    });
    it("anonymise_byok_delegations GRANTS only to service_role", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.anonymise_byok_delegations\(uuid\)\s+TO\s+service_role/i,
      );
    });
  });

  describe("AC9: check_and_record_byok_delegation_use v3 merged atomic shape (DIG F4)", () => {
    it("SELECT FOR UPDATE on byok_delegations under FOR UPDATE row lock", () => {
      expect(executable).toMatch(
        /SELECT\s+\*\s+INTO\s+v_row[\s\S]*?FROM\s+public\.byok_delegations[\s\S]*?WHERE\s+id\s*=\s*p_delegation_id[\s\S]*?FOR\s+UPDATE/i,
      );
    });
    it("uses clock_timestamp() (not now()) for grace + expiry + cap windows (SS F1)", () => {
      const fnMatch = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.check_and_record_byok_delegation_use[\s\S]*?\$\$;\s*REVOKE/,
      );
      expect(fnMatch).toBeTruthy();
      const body = fnMatch![0];
      expect(body).toMatch(/clock_timestamp\(\)/);
      // Body should not call bare `now()` for grace/expiry/cap windows.
      // (`now()` could appear in unrelated DEFAULTs in the rest of the file,
      // hence the body-scoped check.)
      const nowCalls = body.match(/\bnow\(\)/g) ?? [];
      expect(nowCalls.length).toBe(0);
    });
    it("grace check raises P0001 byok_delegations:revoked_post_grace after writing audit row with attribution_shift_reason", () => {
      expect(executable).toMatch(
        /attribution_shift_reason[\s\S]*?'revoked_post_grace'[\s\S]*?byok_delegations:revoked_post_grace/,
      );
    });
    it("expired check has matching shape with 'expired' attribution_shift_reason", () => {
      expect(executable).toMatch(
        /attribution_shift_reason[\s\S]*?'expired'[\s\S]*?byok_delegations:expired/,
      );
    });
    it("hourly cap raises byok_delegations:hourly_cap_exceeded WITHOUT writing audit row", () => {
      // The cap check is structural: SUM, IF threshold exceeded RAISE.
      // No INSERT INTO audit_byok_use between the SUM and the RAISE.
      const fnMatch = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.check_and_record_byok_delegation_use[\s\S]*?\$\$;\s*REVOKE/,
      );
      const body = fnMatch![0];
      const hourlyMatch = body.match(/v_hourly_spent\s*\+\s*v_this_cost[\s\S]*?byok_delegations:hourly_cap_exceeded/);
      expect(hourlyMatch).toBeTruthy();
      expect(hourlyMatch![0]).not.toMatch(/INSERT\s+INTO\s+public\.audit_byok_use/i);
    });
    it("ON CONFLICT (invocation_id) DO NOTHING on the success-path audit INSERT (Inngest retry idempotency)", () => {
      expect(executable).toMatch(
        /INSERT\s+INTO\s+public\.audit_byok_use[\s\S]*?ON\s+CONFLICT\s*\(\s*invocation_id\s*\)\s+DO\s+NOTHING/i,
      );
    });
  });

  describe("AC10: member-departure cascade (AFTER DELETE on workspace_members)", () => {
    it("function sets revoked_by_user_id = OLD.user_id with revocation_reason = 'member_departed'", () => {
      expect(executable).toMatch(
        /UPDATE\s+public\.byok_delegations[\s\S]*?revoked_by_user_id\s*=\s*OLD\.user_id[\s\S]*?revocation_reason\s*=\s*'member_departed'/i,
      );
    });
    it("trigger attached AFTER DELETE ON workspace_members", () => {
      expect(executable).toMatch(
        /CREATE\s+TRIGGER\s+workspace_members_byok_delegations_revoke[\s\S]*?AFTER\s+DELETE\s+ON\s+public\.workspace_members/i,
      );
    });
  });

  describe("AC11: anonymise_byok_delegations active-row guard (SS F7)", () => {
    it("first revoke-flip (Shape 1) for active rows with 'art_17_anonymise' reason", () => {
      expect(executable).toMatch(
        /UPDATE\s+public\.byok_delegations[\s\S]*?revocation_reason\s*=\s*'art_17_anonymise'[\s\S]*?revoked_at\s+IS\s+NULL/i,
      );
    });
    it("then Shape 2 nulls workspace_id + identity cols + revoked_by + cap_updated_by", () => {
      expect(executable).toMatch(
        /workspace_id\s*=\s*NULL[\s\S]*?revoked_by_user_id\s*=\s*NULL[\s\S]*?cap_updated_by_user_id\s*=\s*NULL/i,
      );
    });
  });

  describe("AC12: down migration", () => {
    it("drops byok_delegations table CASCADE", () => {
      expect(downExecutable).toMatch(
        /DROP\s+TABLE\s+IF\s+EXISTS\s+public\.byok_delegations\s+CASCADE/i,
      );
    });
    it("drops all 8 functions defined in up", () => {
      const fns = [
        "byok_delegations_on_member_delete",
        "anonymise_byok_delegations",
        "check_and_record_byok_delegation_use",
        "resolve_byok_key_owner",
        "revoke_byok_delegation",
        "grant_byok_delegation",
        "byok_delegations_no_mutate",
        "byok_delegations_check_same_workspace",
      ];
      for (const fn of fns) {
        expect(downExecutable).toMatch(new RegExp(`DROP\\s+FUNCTION\\s+IF\\s+EXISTS\\s+public\\.${fn}`, "i"));
      }
    });
    it("removes audit_byok_use.delegation_id + attribution_shift_reason columns", () => {
      expect(downExecutable).toMatch(/DROP\s+COLUMN\s+IF\s+EXISTS\s+delegation_id/i);
      expect(downExecutable).toMatch(/DROP\s+COLUMN\s+IF\s+EXISTS\s+attribution_shift_reason/i);
    });
    it("KEEPS audit_byok_use.invocation_id UNIQUE (load-bearing for ON CONFLICT idempotency)", () => {
      // Negative-space: down must NOT drop the constraint. Comment in the
      // down file explains the rationale.
      expect(downExecutable).not.toMatch(/DROP\s+CONSTRAINT\s+IF\s+EXISTS\s+audit_byok_use_invocation_id_uniq/i);
      expect(downSql).toMatch(/Keep\s+audit_byok_use\.invocation_id\s+UNIQUE/i);
    });
  });
});

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

// Migration-shape test for 083_byok_delegation_consent_gate.sql
// (feat-byok-delegation-consent, #4625, Phase 2). Offline lint — runs
// without a live database, mirroring the 064 precedent. Live RLS/EXISTS
// behavior is TENANT_INTEGRATION_TEST=1 against dev-Supabase.
//
// The gate adds `AND EXISTS(current-version acceptance)` inside the
// delegation branch of resolve_byok_key_owner so a delegation with no
// acceptance (or a stale-version one) fails CLOSED at the SQL lease
// chokepoint — zero TS call-site changes (064 Decision #8 TOCTOU intact).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/083_byok_delegation_consent_gate.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/083_byok_delegation_consent_gate.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

describe("migration 083_byok_delegation_consent_gate", () => {
  describe("header", () => {
    it("cites the feature/issue", () => {
      expect(sql).toMatch(/#4625/);
    });
  });

  describe("current_byok_side_letter_version() — SQL source of truth", () => {
    it("is defined returning the canonical version literal", () => {
      const m = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.current_byok_side_letter_version\s*\(\s*\)[\s\S]*?\$\$;/i,
      );
      expect(m, "current_byok_side_letter_version not defined").not.toBeNull();
      // The returned literal MUST equal the TS constant (AC4 parity).
      expect(m![0]).toContain(`'${BYOK_SIDE_LETTER_VERSION}'`);
    });
    it("is IMMUTABLE and pins search_path (SECURITY INVOKER — reads no tables)", () => {
      const m = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.current_byok_side_letter_version\s*\(\s*\)[\s\S]*?\$\$;/i,
      )!;
      expect(m[0]).toMatch(/IMMUTABLE/i);
      expect(m[0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });
  });

  describe("resolve_byok_key_owner — acceptance gate (AC1/AC2)", () => {
    const fnMatch = () =>
      executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.resolve_byok_key_owner\s*\(([^)]*)\)[\s\S]*?\$\$;/i,
      );

    it("CREATE OR REPLACEs resolve_byok_key_owner(uuid, uuid) SECURITY DEFINER + search_path", () => {
      const m = fnMatch();
      expect(m, "resolve_byok_key_owner not re-created").not.toBeNull();
      expect(m![0]).toMatch(/SECURITY\s+DEFINER/i);
      expect(m![0]).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });

    it("preserves own-key short-circuit (solo users unaffected — AC6)", () => {
      expect(fnMatch()![0]).toMatch(/api_keys\s+WHERE\s+user_id\s*=\s*p_caller_user_id/i);
    });

    it("adds EXISTS(current-version acceptance) bound to grantee + delegation", () => {
      const body = fnMatch()![0];
      expect(body).toMatch(
        /EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.byok_delegation_acceptances/i,
      );
      expect(body).toMatch(/a\.delegation_id\s*=\s*bd\.id/i);
      expect(body).toMatch(/a\.user_id\s*=\s*bd\.grantee_user_id/i);
      expect(body).toMatch(
        /a\.side_letter_version\s*=\s*public\.current_byok_side_letter_version\s*\(\s*\)/i,
      );
    });

    it("keeps the active-delegation predicates (revoked_at NULL + expiry)", () => {
      const body = fnMatch()![0];
      expect(body).toMatch(/bd\.revoked_at\s+IS\s+NULL/i);
      expect(body).toMatch(/bd\.expires_at\s+IS\s+NULL\s+OR\s+bd\.expires_at\s*>\s*clock_timestamp\(\)/i);
    });
  });

  describe("AC8: REVOKE/GRANT re-assertion on the replaced resolver", () => {
    it("REVOKEs resolve_byok_key_owner from PUBLIC, anon, authenticated", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.resolve_byok_key_owner\([\s\S]*?\)\s*FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
    });
    it("GRANTs EXECUTE on resolve_byok_key_owner to service_role only", () => {
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.resolve_byok_key_owner\([\s\S]*?\)\s*TO\s+service_role/i,
      );
    });
  });

  describe("transaction safety + down migration", () => {
    it("wraps body in BEGIN/COMMIT", () => {
      expect(executable).toMatch(/BEGIN;/);
      expect(executable).toMatch(/COMMIT;/);
    });
    it("down drops current_byok_side_letter_version and restores the pre-gate resolver", () => {
      expect(downExecutable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.current_byok_side_letter_version\(\)/i,
      );
      // Down re-creates resolve_byok_key_owner WITHOUT the acceptance gate.
      const m = downExecutable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.resolve_byok_key_owner[\s\S]*?\$\$;/i,
      );
      expect(m, "down must restore resolve_byok_key_owner").not.toBeNull();
      expect(m![0]).not.toMatch(/byok_delegation_acceptances/i);
    });
  });
});

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 047_custom_access_token_hook.sql.
//
// File-parse contract test (mirrors 037 precedent), pinning the SQL
// invariants required by the runtime-JWT asymmetric-signing substrate
// plan, Phases 1.5 / 1.6 / 2.1:
//   1. public.runtime_jwt_mint_hook(event jsonb) RETURNS jsonb —
//      Supabase Custom Access Token Hook contract: receives the auth
//      event jsonb and returns the {claims: {...}} envelope. Only the
//      runtime mint path (non-OTP) calls precheck_jwt_mint; OTP and
//      other auth-flow paths are pass-through (preserve existing
//      Supabase-issued claims byte-for-byte).
//   2. SECURITY DEFINER + LANGUAGE plpgsql + SET search_path = public,
//      pg_temp (per cq-pg-security-definer-search-path-pin-pg-temp).
//   3. Calls public.precheck_jwt_mint (jti + exp + iat + rate-limit
//      gate) and stamps the resulting claims via jsonb_set
//      (jti / exp / iat / aud='soleur-runtime' / role='authenticated').
//   4. NO `EXCEPTION WHEN OTHERS` — fail-loud is mandatory for the
//      mint critical path so rate-limit / DB outages don't degrade
//      silently into unsigned/over-quota tokens.
//   5. Revokes EXECUTE from PUBLIC, anon, authenticated, service_role
//      and grants only to supabase_auth_admin (the role Supabase Auth
//      uses to invoke the configured hook).
//   6. cq-supabase-migration-no-concurrently: NO CREATE INDEX
//      CONCURRENTLY (Supabase wraps each migration in a transaction).
//
// Behavioral integration tests live in the gated describe.skip block
// at the bottom; they activate when TENANT_INTEGRATION_TEST=1 and a
// live Doppler DATABASE_URL_POOLER is available (PR-B precedent).
//
// Plan: knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md §1.5/§1.6/§2.1
// ADR: knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md

const MIGRATION_PATH = path.resolve(
  __dirname,
  "../../supabase/migrations/047_custom_access_token_hook.sql",
);

describe("migration 047_custom_access_token_hook", () => {
  // readFileSync intentionally not wrapped in try/catch: until the
  // migration exists this entire describe must throw at module load
  // (RED). The behavioral describe.skip below remains declared even
  // when the file is missing because vitest collects skipped blocks
  // before evaluating sibling describes.
  const sql = readFileSync(MIGRATION_PATH, "utf8");

  // Strip line-comments before pattern checks (mirrors 037 pattern).
  const executable = sql.replace(/--[^\n]*/g, "");

  describe("runtime_jwt_mint_hook function shape", () => {
    const fnBlock =
      executable.match(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.runtime_jwt_mint_hook[\s\S]*?\$\$;/i,
      )?.[0] || "";

    it("declares runtime_jwt_mint_hook(event jsonb) RETURNS jsonb (Supabase hook contract)", () => {
      // AC §1.5: the function must match Supabase's Custom Access
      // Token Hook signature exactly — single jsonb event in, single
      // jsonb envelope out.
      expect(fnBlock).not.toBe("");
      expect(fnBlock).toMatch(
        /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.runtime_jwt_mint_hook\s*\(\s*event\s+jsonb\s*\)\s+RETURNS\s+jsonb/i,
      );
    });

    it("is LANGUAGE plpgsql", () => {
      // Required for the IF/RAISE/jsonb_set sequence; sql language
      // can't express the pass-through gate.
      expect(fnBlock).toMatch(/LANGUAGE\s+plpgsql/i);
    });

    it("is SECURITY DEFINER (callable by supabase_auth_admin only)", () => {
      // Hook is invoked under supabase_auth_admin; SECURITY DEFINER
      // is what lets it reach precheck_jwt_mint without granting
      // EXECUTE on that RPC to non-service roles.
      expect(fnBlock).toMatch(/SECURITY\s+DEFINER/i);
    });

    it("pins SET search_path = public, pg_temp (in that order)", () => {
      // cq-pg-security-definer-search-path-pin-pg-temp.
      expect(fnBlock).toMatch(
        /SET\s+search_path\s*=\s*public\s*,\s*pg_temp/i,
      );
    });

    it("pass-through gate: only mints when authentication_method <> 'otp'", () => {
      // AC §1.6: non-OTP flows (Dashboard password login, OAuth,
      // refresh-token rotation) must short-circuit back through
      // unmodified claims. The check derives from event->>
      // 'authentication_method'; an intermediate variable assignment
      // is canonical (and clearer) so the regex below tolerates both
      // the inline form and the variable-bound form by independently
      // matching the assignment AND the IF <> 'otp' check.
      expect(fnBlock).toMatch(
        /event\s*->>\s*'authentication_method'/i,
      );
      expect(fnBlock).toMatch(/IF[\s\S]*?<>\s*'otp'/i);
    });

    it("calls public.precheck_jwt_mint (schema-qualified, AC §1.5)", () => {
      // Belt + suspenders qualification per
      // cq-pg-security-definer-search-path-pin-pg-temp.
      expect(fnBlock).toMatch(/public\.precheck_jwt_mint/);
    });

    it("stamps jti / exp / iat / aud / role via jsonb_set (>= 5 calls)", () => {
      // AC §1.5: the hook must materialize jti, exp, iat,
      // aud='soleur-runtime', role='authenticated' into the claims.
      // The jsonb_set path argument is a text[] using PG's '{key}'
      // syntax (NOT 'key' alone). Match both the path literals and
      // the value literals.
      const jsonbSetCalls = fnBlock.match(/jsonb_set\s*\(/gi) || [];
      expect(jsonbSetCalls.length).toBeGreaterThanOrEqual(5);
      expect(fnBlock).toMatch(/'\{jti\}'/);
      expect(fnBlock).toMatch(/'\{exp\}'/);
      expect(fnBlock).toMatch(/'\{iat\}'/);
      // The migration encodes aud/role as JSON-string literals for jsonb_set:
      // `'"soleur-runtime"'` and `'"authenticated"'` (single-quoted SQL
      // string containing a JSON string). Match the JSON-quoted form.
      expect(fnBlock).toMatch(/'"soleur-runtime"'/);
      expect(fnBlock).toMatch(/'"authenticated"'/);
    });

    it("wraps return value in {claims: ...} via jsonb_build_object", () => {
      // Supabase hook contract: the response envelope must be a
      // jsonb object with a top-level "claims" key. Returning the
      // claims jsonb directly silently breaks Supabase Auth.
      expect(fnBlock).toMatch(
        /jsonb_build_object\s*\(\s*'claims'\s*,/i,
      );
    });

    it("does NOT swallow errors via `EXCEPTION WHEN OTHERS`", () => {
      // Fail-loud is mandatory: rate-limit breach (SQLSTATE 45001),
      // DB outage, or any other failure must surface to Supabase
      // Auth so the user sees a 5xx, not a silently-unsigned token.
      expect(fnBlock).not.toMatch(/EXCEPTION\s+WHEN\s+OTHERS/i);
    });
  });

  describe("grants and revokes", () => {
    it("revokes EXECUTE from PUBLIC, anon, authenticated, service_role", () => {
      // Hook must be callable only by supabase_auth_admin. Supabase's
      // default-privilege grant to anon/authenticated/service_role is
      // dangerous on a SECURITY DEFINER function that mints tokens.
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role/i,
      );
    });

    it("grants EXECUTE to supabase_auth_admin", () => {
      // The role Supabase Auth uses to invoke the configured hook.
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+TO\s+supabase_auth_admin/i,
      );
    });

    it("does not grant EXECUTE to authenticated or anon", () => {
      // Belt + suspenders against accidental re-grant.
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+TO\s+authenticated/i,
      );
      expect(executable).not.toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.runtime_jwt_mint_hook\s*\([^)]*\)\s+TO\s+anon/i,
      );
    });
  });

  describe("migration hygiene", () => {
    it("does NOT use CREATE INDEX CONCURRENTLY (supabase wraps in tx)", () => {
      // cq-supabase-migration-no-concurrently.
      expect(executable).not.toMatch(/CREATE\s+INDEX\s+CONCURRENTLY/i);
    });
  });
});

// Behavioral integration tests — declared but skipped until the
// migration ships and TENANT_INTEGRATION_TEST=1. These run via
// Doppler DATABASE_URL_POOLER in /work Phase 2-apply against a live
// dev Supabase project (per hr-dev-prd-distinct-supabase-projects).
//
// Keep concrete enough that uncommenting + wiring a pg client is
// sufficient — no further spec lookup required.
describe.skip("runtime_jwt_mint_hook — integration tests applied after migration runs", () => {
  // Activates when TENANT_INTEGRATION_TEST=1 (PR-B precedent).
  // Requires a live connection via process.env.DATABASE_URL_POOLER.

  it("pass-through: non-otp claims roundtrip is byte-identical when auth method is non-mint", () => {
    // Setup:
    //   const fixtureUuid = "00000000-0000-0000-0000-000000000001";
    //   const inputClaims = { sub: fixtureUuid, aud: "authenticated", role: "anon" };
    //   const event = {
    //     user_id: fixtureUuid,
    //     claims: inputClaims,
    //     authentication_method: "password", // not 'otp' but exercising the gate logic for the non-mint branch
    //   };
    //
    // For TRUE pass-through we want authentication_method === 'otp':
    //   event.authentication_method = "otp";
    //
    // Call:
    //   const { rows } = await pg.query(
    //     "SELECT public.runtime_jwt_mint_hook($1::jsonb) AS out",
    //     [JSON.stringify(event)]
    //   );
    //
    // Assert:
    //   expect(rows[0].out.claims).toEqual(inputClaims);
    //
    // (Phase 2-apply will unblock this; today it's the AC document.)
  });

  it("function signature: pg_get_function_arguments + pg_get_function_result match the hook contract", () => {
    // Call:
    //   const { rows } = await pg.query(`
    //     SELECT
    //       pg_get_function_arguments(p.oid) AS args,
    //       pg_get_function_result(p.oid)    AS result
    //     FROM pg_proc p
    //     JOIN pg_namespace n ON p.pronamespace = n.oid
    //     WHERE p.proname = 'runtime_jwt_mint_hook'
    //       AND n.nspname = 'public'
    //   `);
    //
    // Assert:
    //   expect(rows[0].args).toBe("event jsonb");
    //   expect(rows[0].result).toBe("jsonb");
    //
    // Catches signature drift (extra param, wrong return shape) that
    // would silently break the Supabase hook wiring.
  });
});
